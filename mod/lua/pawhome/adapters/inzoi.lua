-- Adapter for the official ModKit route (ADR 0007, 0008; design: docs/design/modkit-runtime.md).
-- Runs on the B2 (simulation) thread. Every game call goes through `platform`, a table of
-- small functions implemented by adapters/inzoi_platform.lua in the game and by a fake in
-- the tests:
--   platform.time()                      -> day, hour, minute
--   platform.possessed()                 -> entity id (number) of the Zoi the player controls, or nil
--   platform.household(zoiId)            -> household id or nil
--   platform.householdMembers(hid)       -> { zoi ids }
--   platform.funds(hid)                  -> number
--   platform.charge(hid, amount)         -> true when the money was taken
--   platform.send(entityId, channel, payload)        B2 -> B1 message (inzoi.message.send_to_client)
--   platform.enqueue(zoiId, targetId, interactionBagId) -> true when queued
--   platform.atHome(zoiId)               -> true when the Zoi is on the household's lot
--   platform.homeCats()                  -> entity ids of the summoned cats on the home lot (optional)
--   platform.homeObjects(watched)        -> object row ids from `watched` found on the home lot (optional)
--   platform.log(line)                   optional
--
-- Saving: B2 cannot write the savegame. The UI keeps the data in wf.state (saved inside the
-- game's save file) and hands it over after every load; until then slotId() returns nil and
-- the engine pauses (see core/api.lua). saveSet sends the new value back to the UI.
--
-- Cats: our "home cat" is a DEV_Void_Cat summoned by the data script PawHome_SpawnCat that
-- runs at the end of the interaction PawHome_WelcomeCat. The cat appears in front of the
-- Zoi, so the interaction is only started while the Zoi is at home; spawnPet returns a
-- placeholder ref ("pending:<n>") at once and binds it to the real entity when the cat
-- binding reports a new cat on the household's lot. Sending a cat away waits the same way.
local Wire = require("pawhome.adapters.inzoi_wire")
local Serialize = require("pawhome.core.serialize")

local ModKit = {
    HELLO_EVERY_SECONDS = 5,
    HELLO_WHEN_READY_SECONDS = 60,
    PENDING_MINUTES = 180,       -- give up on a summon after 3 game hours; the engine retries
    MET_CAT_MINUTES = 3 * 1440,  -- city cats the Zoi met within 3 game days can be adopted
    REFS_KEY = "pawhome.refs",
    WELCOME = "PawHome_WelcomeCat",
    SEND_AWAY = "PawHome_SendAway",
    CARE = { Object_Void_Cat_Dev = "feed", Object_Void_Cat_Tickle = "play" },
}

function ModKit.new(platform, opts)
    opts = opts or {}
    local a = {
        caps = { spawn = opts.spawn == true, moveStray = false, buffs = false, animate = false },
        platform = platform,
        session = opts.session or tostring(math.random(100000, 999999)),
        ready = false,
        cache = {},
        listeners = {},
        assembler = Wire.assembler(),
        nextMsg = 0,
        sinceHello = math.huge,
        refs = {},          -- placeholder ref -> entity id
        pending = {},       -- list of { ref, at, household, queued }
        leaving = {},       -- cat entity ids to send away once the Zoi is home
        nextPending = 1,
        cats = {},          -- entity id -> { home = bool, site = id }
        met = {},           -- entity id -> game minute the possessed Zoi last cared for it
        careLog = {},       -- entity id -> list of { kind, zoi, at } not yet taken by the engine
        rpc = nil,          -- function(method, args) -> result table
    }

    local function log(line)
        if platform.log then pcall(platform.log, "[PawHome] " .. line) end
    end

    local function target()
        return platform.possessed()
    end

    local function sendLong(kind, data)
        local eid = target()
        if eid == nil then return false end
        a.nextMsg = a.nextMsg + 1
        for _, part in ipairs(Wire.split(a.session, tostring(a.nextMsg), data)) do
            platform.send(eid, Wire.channel(kind), part)
        end
        return true
    end

    -- ------------------------------------------------------------ adapter contract

    function a.now()
        local d, h, m = platform.time()
        return d * 1440 + h * 60 + m
    end

    function a.slotId() return a.ready and a.session or nil end

    function a.saveGet(key) return a.cache[key] end

    function a.saveSet(key, value)
        a.cache[key] = value
        sendLong("save", Wire.toJson({ key = key, value = value }))
    end

    function a.subscribe(event, fn)
        if event == "slot_changed" then a.listeners[#a.listeners + 1] = fn end
    end

    function a.locale() return a.localeName or "en" end

    function a.notify(householdId, kind, text)
        local eid = target()
        if eid == nil then return end
        platform.send(eid, Wire.channel("toast"), tostring(text))
    end

    function a.householdMembers(hid) return platform.householdMembers(hid) or {} end
    function a.funds(hid) return platform.funds(hid) or 0 end
    function a.charge(hid, amount) return platform.charge(hid, amount) == true end
    function a.homeObjects(hid, watched)
        if not platform.homeObjects then return {} end
        return platform.homeObjects(watched) or {}
    end

    local function persistRefs()
        a.saveSet(ModKit.REFS_KEY, Serialize.encode(a.refs))
    end

    local function resolve(ref)
        if type(ref) == "number" then return ref end
        return a.refs[ref]
    end

    function a.spawnPet(householdId, spec)
        if not a.caps.spawn then return nil end
        local ref = "pending:" .. a.session .. ":" .. a.nextPending
        a.nextPending = a.nextPending + 1
        a.pending[#a.pending + 1] = { ref = ref, at = a.now(), household = householdId, queued = false }
        log("summon waiting for the Zoi to be home: " .. ref)
        a.serviceQueue()
        return ref
    end

    function a.entityExists(ref)
        local eid = resolve(ref)
        if eid ~= nil then return a.cats[eid] ~= nil end
        for _, p in ipairs(a.pending) do
            -- waiting for the Zoi to come home counts as present; after the summon was
            -- started, give it a few game hours before the engine may try again
            if p.ref == ref then return not p.queued or a.now() - p.at < ModKit.PENDING_MINUTES end
        end
        return false
    end

    function a.despawnPet(ref)
        local eid = resolve(ref)
        for i = #a.pending, 1, -1 do
            if a.pending[i].ref == ref then table.remove(a.pending, i) end
        end
        if type(ref) == "string" and a.refs[ref] then
            a.refs[ref] = nil
            persistRefs()
        end
        if eid == nil or a.cats[eid] == nil then return end
        a.leaving[#a.leaving + 1] = eid
        a.serviceQueue()
    end

    -- Starts the summon / goodbye interactions that wait for the Zoi to be at home.
    function a.serviceQueue()
        local zoi = target()
        if zoi == nil or not platform.atHome(zoi) then return end
        for _, p in ipairs(a.pending) do
            if not p.queued and platform.enqueue(zoi, zoi, ModKit.WELCOME) then
                p.queued, p.at = true, a.now()
                log("summon started " .. p.ref)
            end
        end
        for i = #a.leaving, 1, -1 do
            local eid = a.leaving[i]
            if a.cats[eid] == nil or platform.enqueue(zoi, eid, ModKit.SEND_AWAY) then
                table.remove(a.leaving, i)
            end
        end
    end

    -- City cats the player's Zoi has fed or played with recently.
    function a.listStrays(householdId)
        local out, now = {}, a.now()
        local owned = {}
        for _, eid in pairs(a.refs) do owned[eid] = true end
        for eid, at in pairs(a.met) do
            local cat = a.cats[eid]
            if cat and not cat.home and not owned[eid] and now - at < ModKit.MET_CAT_MINUTES then
                out[#out + 1] = { id = "cat" .. eid, ref = eid, stage = "adult", appearance = eid }
            end
        end
        table.sort(out, function(x, y) return x.ref < y.ref end)
        return out
    end

    -- ------------------------------------------------------------ events from the game

    -- B2 binding tick (any binding, real seconds). Says hello every few seconds until the UI
    -- answers, then once a minute so a UI that was reloaded can find this session again.
    function a.tick(dt)
        a.sinceQueue = (a.sinceQueue or 0) + (dt or 0)
        if a.sinceQueue >= ModKit.HELLO_EVERY_SECONDS then
            a.sinceQueue = 0
            if a.ready and (#a.pending > 0 or #a.leaving > 0) then a.serviceQueue() end
        end
        a.sinceHello = a.sinceHello + (dt or 0)
        local every = a.ready and ModKit.HELLO_WHEN_READY_SECONDS or ModKit.HELLO_EVERY_SECONDS
        if a.sinceHello >= every then
            local eid = target()
            if eid ~= nil then
                platform.send(eid, Wire.channel("hello"), a.session)
                a.sinceHello = 0
            end
        end
    end

    local function onState(data)
        if a.ready then
            -- A UI that was reloaded during the session (mod remount) starts with an empty
            -- wf.state: the game restores it only when a save is loaded. Keep our data and
            -- give the UI a full copy instead of taking its (empty) one.
            local count = 0
            for key, value in pairs(a.cache) do
                sendLong("save", Wire.toJson({ key = key, value = value }))
                count = count + 1
            end
            log("UI reconnected; sent it " .. count .. " keys")
            return
        end
        local t, err = Wire.fromJson(data ~= "" and data or "{}")
        if type(t) ~= "table" then
            log("state from UI is unreadable: " .. tostring(err))
            t = {}
        end
        a.cache = {}
        for k, v in pairs(t) do
            if type(v) == "string" then a.cache[k] = v end
        end
        local refs = a.cache[ModKit.REFS_KEY] and Serialize.decode(a.cache[ModKit.REFS_KEY])
        a.refs = type(refs) == "table" and refs or {}
        a.ready = true
        log("state received (" .. #data .. " bytes)")
        a.scanHomeCats()
        for _, fn in ipairs(a.listeners) do pcall(fn) end
    end

    local function onRpc(data)
        local req = Wire.fromJson(data)
        if type(req) ~= "table" then return end
        local result
        if not a.ready then
            result = { error = "not_ready" }
        elseif a.rpc then
            local ok, r = pcall(a.rpc, req.method, req.args or {})
            result = ok and r or { error = tostring(r) }
        else
            result = { error = "not_ready" }
        end
        sendLong("rpc_result", Wire.toJson({ id = req.id, result = result }))
    end

    -- B2 Zoi binding on_lua_message(self, owner, channel, payload).
    function a.onMessage(channel, payload)
        local kind = Wire.kind(channel)
        if kind ~= "state" and kind ~= "rpc" then return end
        local session, _, data = a.assembler.add(payload)
        if data == nil then return end
        if session ~= a.session then return end      -- an answer to an earlier game session
        if kind == "state" then onState(data) else onRpc(data) end
    end

    -- ObjectTemplate binding on a cat: on_begin. info = { home = bool, site = id }.
    function a.onCatBegin(eid, info)
        info = info or {}
        a.cats[eid] = { home = info.home == true, site = info.site }
        if not info.home then return end
        for _, ref in pairs(a.refs) do if ref == eid then return end end
        local p = table.remove(a.pending, 1)
        if p then
            a.refs[p.ref] = eid
            log("summoned cat " .. tostring(eid) .. " is " .. p.ref)
            persistRefs()
        end
    end

    function a.onCatEnd(eid) a.cats[eid] = nil end

    -- Summoned cats are not reported by the cat binding, so after our welcome interaction
    -- the home lot is searched for cats we do not know yet.
    function a.scanHomeCats()
        if not platform.homeCats then return end
        local ok, list = pcall(platform.homeCats)
        if not ok or type(list) ~= "table" then return end
        for _, eid in ipairs(list) do
            if a.cats[eid] == nil or not a.cats[eid].home then a.onCatBegin(eid, { home = true }) end
        end
    end

    -- interaction.finished event: summoned cats, city cats the player met, and care given.
    function a.onInteractionFinished(ev)
        if ev and ev.interaction_bag_id == ModKit.WELCOME then
            a.scanHomeCats()
            return
        end
        local kind = ev and ModKit.CARE[ev.interaction_bag_id]
        if not kind then return end
        local eid = ev.target_entity_id
        if ev.entity_id == target() then a.met[eid] = a.now() end
        local list = a.careLog[eid] or {}
        list[#list + 1] = { kind = kind, zoi = ev.entity_id, at = a.now() }
        a.careLog[eid] = list
    end

    -- Care events for one of our pets since the last call (the engine applies them).
    function a.takeCare(ref)
        local eid = resolve(ref)
        if eid == nil then return {} end
        local list = a.careLog[eid] or {}
        a.careLog[eid] = nil
        return list
    end

    return a
end

return ModKit
