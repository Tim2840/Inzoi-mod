-- The real game calls behind adapters/inzoi.lua (B2) and adapters/inzoi_relay.lua (B1).
-- Each function says whether it was seen working in the game (version, date, evidence) or is
-- only known from the shipped LuaLS definitions (luals-defs) and still UNVERIFIED.
local Wire = require("pawhome.adapters.inzoi_wire")

local Platform = { MOD_ID = "PawHome" }

-- tools/build_modkit.py writes pawhome/modkit_config.lua with the real mod id (folder name)
do
    local ok, config = pcall(require, "pawhome.modkit_config")
    if ok and type(config) == "table" and config.MOD_ID then Platform.MOD_ID = config.MOD_ID end
end

-- inzoi.cli.execute returns ok, message, data (a JSON string). Verified 20261019.16318.W, 2026-10-20.
local function cli(line)
    local ok, success, msg, data = pcall(inzoi.cli.execute, line)
    if not ok or not success then return nil, tostring(msg or success) end
    if type(data) ~= "string" or data == "" then return {} end
    local t = Wire.fromJson(data)
    return t or {}
end

local function quote(s) return '"' .. tostring(s):gsub('"', "'") .. '"' end

-- ---------------------------------------------------------------- B2 (simulation thread)

function Platform.b2(opts)
    opts = opts or {}
    local p = { logLines = {} }
    local homeSite = nil

    -- UNVERIFIED: FB2TimeManager:GetDay/GetHour/GetMinute (luals-defs). The Time manager
    -- itself is verified (Manager binding key "Time" receives FB2TimeManager, 2026-10-20).
    function p.time()
        local tm = inzoi.getB2Manager("FB2TimeManager")
        return tm:GetDay(), tm:GetHour(), tm:GetMinute()
    end

    -- Verified: entity.get_possessed from B2 returns {"entity_id":16597} (2026-10-20).
    function p.possessed()
        local t = cli("entity.get_possessed")
        return t and tonumber(t.entity_id) or nil
    end

    -- UNVERIFIED shape: household.get_members (Public, B2Authority).
    local function members(hid)
        local line = "household.get_members" .. (hid and (" household_id=" .. tostring(hid)) or "")
        return cli(line)
    end

    function p.household()
        local t = members(nil)
        if not t then return nil end
        return tonumber(t.household_id or t.household_entity_id or t.entity_id)
    end

    function p.householdMembers(hid)
        local t = members(hid) or {}
        local out = {}
        for _, m in ipairs(t.members or {}) do
            local id = tonumber(type(m) == "table" and (m.entity_id or m.id) or m)
            if id then out[#out + 1] = id end
        end
        return out
    end

    -- Game objects handed to us by the bindings (entity id -> object). The game's entity
    -- lookups take FB1EntityId values, not numbers (FindHousehold: "arg #2 must be a valid
    -- FB1EntityId", 2026-10-21), and there is no documented way to build one, so ids are
    -- always taken from these objects.
    p.zois, p.cats = {}, {}

    local function value(id)
        if type(id) == "table" or type(id) == "userdata" then return tonumber(id.Value) end
        return tonumber(id)
    end
    p.value = value

    -- UNVERIFIED: FB2Actor:GetHouseholdEntityId, FB2EntityManager:FindHousehold, Currency component.
    local function wallet(hid)
        local em = inzoi.getB2Manager("FB2EntityManager")
        for _, character in pairs(p.zois) do
            local hidStruct = character:GetHouseholdEntityId()
            if value(hidStruct) == hid then
                local household = em:FindHousehold(hidStruct)
                return household and household:GetComponent(inzoi.EB2ComponentType.Currency), hidStruct
            end
        end
        return nil
    end

    -- Each city has its own currency (rows of the Currency table: Zen, Mew, Nyang, Ong, ...),
    -- so the default currency is used: GetCurrency(out, owner). How the out parameter comes
    -- back to Lua is not documented; the first shape that yields a number is used and
    -- reported once through p.report (UNVERIFIED until that report is seen).
    local fundsReported = false
    function p.funds(hid)
        local w, owner
        local attempts = {
            { "GetCurrency(owner)", function() local a, b = w:GetCurrency(owner); return type(b) == "number" and b or (type(a) == "number" and a or nil) end },
        }
        local okW, errW = pcall(function() w, owner = wallet(hid) end)
        if not okW or not w then
            local known = 0
            for _ in pairs(p.zois) do known = known + 1 end
            if not fundsReported and p.report then
                p.report("funds: no wallet for household " .. tostring(hid) .. " (" .. known .. " Zois known) " .. tostring(errW))
            end
            fundsReported = true
            return 0
        end
        local notes = {}
        for _, a in ipairs(attempts) do
            local ok, v = pcall(a[2])
            if ok and tonumber(v) then
                if not fundsReported and p.report then p.report("funds via " .. a[1] .. " = " .. tostring(v)) end
                fundsReported = true
                return tonumber(v)
            end
            notes[#notes + 1] = a[1] .. ": " .. tostring(v)
        end
        local okMap, map = pcall(function()
            local parts = {}
            for k, v in pairs(w:GetCurrencyMap() or {}) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
            return table.concat(parts, ",")
        end)
        notes[#notes + 1] = "map: " .. tostring(map)
        if not fundsReported and p.report then p.report("funds failed: " .. table.concat(notes, "; ")) end
        fundsReported = true
        return 0
    end

    function p.charge(hid, amount)
        local ok, done = pcall(function()
            local w = wallet(hid)
            return w and w:TrySubtractCurrency(amount)
        end)
        return ok and done == true
    end

    -- Verified: inzoi.message.send_to_client(number entity id, channel, payload) reaches the
    -- B1 Zoi/ResidenceFamily binding of that entity (2026-10-21, rounds 6-7).
    function p.send(eid, channel, payload)
        inzoi.message.send_to_client(eid, channel, payload)
    end

    -- UNVERIFIED: FB2InteractionComponent:AddInteractionQueueByParam (luals-defs).
    function p.enqueue(zoi, targetEid, bagId)
        local ok, result = pcall(function()
            local character = p.zois[zoi]
            if not character then error("no character object for " .. tostring(zoi)) end
            local target
            if targetEid == zoi then
                target = character:GetEntityId()
            else
                local cat = p.cats[targetEid]
                if not cat then error("no object for target " .. tostring(targetEid)) end
                target = cat:GetObjectKey()
            end
            local ic = character:GetComponent(inzoi.EB2ComponentType.Interaction)
            return ic:AddInteractionQueueByParam(target, character:GetLocation(), bagId,
                inzoi.EB1InteractionPlayReason.User, false)
        end)
        if p.report then p.report("enqueue " .. tostring(bagId) .. ": " .. tostring(ok) .. " " .. tostring(result)) end
        return ok
    end

    -- Home site of the controlled Zoi. Verified field: entity.get_character_info returns
    -- "home_site_id" (2026-10-21).
    function p.homeSite()
        if homeSite then return homeSite end
        local zoi = p.possessed()
        if not zoi then return nil end
        local t = cli("entity.get_character_info entity_id=" .. zoi)
        homeSite = t and t.home_site_id
        return homeSite
    end

    -- Cat identity, verified 2026-10-20: owner:GetObjectKey().Value, owner:GetLocation().
    -- UNVERIFIED: FB2Actor:GetLocatedSiteDtId (luals-defs).
    function p.catInfo(owner)
        local eid = owner:GetObjectKey().Value
        p.cats[eid] = owner
        local okSite, site = pcall(function() return tostring(owner:GetLocatedSiteDtId()) end)
        site = okSite and site or nil
        local home = site ~= nil and site == p.homeSite()
        return eid, { home = home, site = site }
    end

    -- Shipping builds write no log file. Lines are kept in memory and written from on_end,
    -- the only moment B2 may call a B1 command (uimod.cfg_save), verified 2026-10-20.
    function p.log(line)
        p.logLines[#p.logLines + 1] = line
        if #p.logLines > 200 then table.remove(p.logLines, 1) end
    end

    function p.flushLog()
        local value = Wire.escape(table.concat(p.logLines, "\n"))
        pcall(inzoi.cli.execute, "uimod.cfg_save mod_id=" .. (opts.modId or Platform.MOD_ID)
            .. " section=log key=b2 value=" .. quote(value))
    end

    return p
end

-- ---------------------------------------------------------------- B1 (game thread)

function Platform.b1(opts)
    opts = opts or {}
    local modId = opts.modId or Platform.MOD_ID
    local p = { logLines = {} }

    -- Verified: uimod.cfg_save / cfg_load from B1 Lua (2026-10-20).
    function p.cfgSave(section, key, value)
        local ok, success = pcall(inzoi.cli.execute, "uimod.cfg_save mod_id=" .. modId .. " section=" .. section
            .. " key=" .. key .. " value=" .. quote(value))
        return ok and success == true
    end

    function p.cfgLoad(section, key)
        local t = cli("uimod.cfg_load mod_id=" .. modId .. " section=" .. section .. " key=" .. key)
        return t and t.value or nil
    end

    -- Verified: inzoi.message.send_to_sim(entity id, channel, payload) reaches the B2
    -- Zoi/ResidenceFamily binding (2026-10-21, round 6).
    function p.sendToSim(eid, channel, payload)
        inzoi.message.send_to_sim(eid, channel, payload)
    end

    -- Verified: toast.show from B1 Lua (2026-10-20).
    function p.toast(text)
        pcall(inzoi.cli.execute, "toast.show message=" .. quote(text) .. " lifetime=6")
    end

    function p.log(line)
        p.logLines[#p.logLines + 1] = line
        if #p.logLines > 200 then table.remove(p.logLines, 1) end
        p.cfgSave("log", "b1", Wire.escape(table.concat(p.logLines, "\n")))
    end

    return p
end

return Platform
