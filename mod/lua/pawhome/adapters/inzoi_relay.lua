-- B1 (game thread) relay between the B2 adapter and the HTML UI (design: docs/design/modkit-runtime.md).
--   B2 -> relay : inzoi.message to the Zoi binding (multi-part payloads, see inzoi_wire.lua)
--   relay -> UI : mailbox "bridge/to_ui" written with uimod.cfg_save
--   UI -> relay : mailbox "bridge/to_sim" read with uimod.cfg_load (polled)
--   relay -> B2 : inzoi.message.send_to_sim to the same Zoi
-- Game calls go through `platform`:
--   platform.cfgSave(section, key, value) -> bool
--   platform.cfgLoad(section, key)        -> string or nil
--   platform.sendToSim(entityId, channel, payload)
--   platform.toast(text)
--   platform.log(line)                    optional
-- r.onCoats(text), set by the owner, receives the coat list B2 sends (pawhome:coats).
local Wire = require("pawhome.adapters.inzoi_wire")

local Relay = { SECTION = "bridge", OUT = "to_ui", IN = "to_sim", POLL_SECONDS = 2, KEEP = 40,
    BACKUP_SECTION = "backup" }

function Relay.new(platform, opts)
    opts = opts or {}
    local r = {
        active = nil,                 -- entity id of the Zoi B2 talks to
        epoch = opts.epoch or tostring(math.random(100000, 999999)),
        outbox = {},
        nextSeq = 1,
        lastIn = nil,                 -- last UI entry handled, per UI epoch
        uiEpoch = nil,
        sincePoll = 0,
        assembler = Wire.assembler(),
        nextMsg = 0,
    }

    local function log(line)
        if platform.log then pcall(platform.log, "[PawHome relay] " .. line) end
    end

    local function flush()
        local entries = { { seq = 0, channel = "epoch", payload = r.epoch } }
        for _, e in ipairs(r.outbox) do entries[#entries + 1] = e end
        platform.cfgSave(Relay.SECTION, Relay.OUT, Wire.encodeMailbox(entries))
    end

    local function post(channel, payload)
        -- a newer save of the same key replaces the older one still waiting in the mailbox
        if channel == Wire.channel("save") then
            local data = payload:match("^[^|]*|(.*)$")
            local t = data and Wire.fromJson(data)
            local key = type(t) == "table" and t.key
            if key then
                for i = #r.outbox, 1, -1 do
                    local e = r.outbox[i]
                    if e.channel == channel and e.key == key then table.remove(r.outbox, i) end
                end
            end
            r.outbox[#r.outbox + 1] = { seq = r.nextSeq, channel = channel, payload = payload, key = key }
        else
            r.outbox[#r.outbox + 1] = { seq = r.nextSeq, channel = channel, payload = payload }
        end
        r.nextSeq = r.nextSeq + 1
        while #r.outbox > Relay.KEEP do table.remove(r.outbox, 1) end
        flush()
    end

    -- B1 Zoi binding on_lua_message(self, owner, channel, payload).
    function r.onMessage(ownerEid, channel, payload)
        local kind = Wire.kind(channel)
        if not kind then return end                       -- another mod's message
        if r.active ~= ownerEid then log("talking to Zoi " .. tostring(ownerEid) .. " (" .. kind .. ")") end
        r.active = ownerEid
        if kind == "diag" then
            log("B2: " .. tostring(payload))
        elseif kind == "toast" then
            platform.toast(payload)
        elseif kind == "hello" then
            post(channel, tostring(payload) .. "|")
        elseif kind == "save" or kind == "rpc_result" or kind == "open" then
            local session, _, data = r.assembler.add(payload)
            if data ~= nil then post(channel, session .. "|" .. data) end
        elseif kind == "backup" then
            -- a copy of the household's data, kept outside the savegame (see the adapter)
            local _, _, data = r.assembler.add(payload)
            local t = data and Wire.fromJson(data)
            if type(t) == "table" and t.hid ~= nil then
                platform.cfgSave(Relay.BACKUP_SECTION, "h" .. tostring(t.hid), Wire.escape(data))
            end
        elseif kind == "backup_get" then
            local session, hid = tostring(payload):match("^([^|]*)|(.*)$")
            if session then
                local stored = platform.cfgLoad(Relay.BACKUP_SECTION, "h" .. hid)
                local data = (type(stored) == "string" and stored ~= "") and Wire.unescape(stored) or ""
                r.nextMsg = r.nextMsg + 1
                for _, part in ipairs(Wire.split(session, "b" .. r.nextMsg, data)) do
                    platform.sendToSim(ownerEid, Wire.channel("backup_data"), part)
                end
                log("backup for household " .. hid .. (data ~= "" and " sent" or ": none"))
            end
        elseif kind == "coats" then
            -- stays on the game thread: the B1 cat binding applies it (inzoi_coats.lua)
            local _, _, data = r.assembler.add(payload)
            if data ~= nil and r.onCoats then pcall(r.onCoats, data) end
        end
    end

    -- Reads the UI's mailbox and forwards new entries to B2.
    function r.poll()
        local text = platform.cfgLoad(Relay.SECTION, Relay.IN)
        local entries = Wire.decodeMailbox(text)
        if #entries == 0 or r.active == nil then return end
        local epoch = entries[1].channel == "epoch" and entries[1].payload or nil
        if epoch ~= r.uiEpoch then r.uiEpoch, r.lastIn = epoch, nil end
        for _, e in ipairs(entries) do
            if e.seq > 0 and (r.lastIn == nil or e.seq > r.lastIn) then
                r.lastIn = e.seq
                local session, data = e.payload:match("^([^|]*)|(.*)$")
                if session and Wire.kind(e.channel) then
                    r.nextMsg = r.nextMsg + 1
                    for _, part in ipairs(Wire.split(session, "u" .. r.nextMsg, data)) do
                        platform.sendToSim(r.active, e.channel, part)
                    end
                end
            end
        end
    end

    -- Any B1 on_tick (real seconds). Polls at most every POLL_SECONDS.
    function r.tick(dt)
        r.sincePoll = r.sincePoll + (dt or 0)
        if r.sincePoll < Relay.POLL_SECONDS then return end
        r.sincePoll = 0
        local ok, err = pcall(r.poll)
        if not ok then log("poll failed: " .. tostring(err)) end
    end

    return r
end

return Relay
