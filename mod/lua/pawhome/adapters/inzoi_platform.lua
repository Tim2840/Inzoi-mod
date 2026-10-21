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

    -- Verified 2026-10-21: FB2EntityManager:GetAllEntities(type) returns a TArray with Num(),
    -- indexed from 1, whose items are the game objects (FB2GameObject / FB2Character).
    local function eachEntity(entityType, fn)
        local em = inzoi.getB2Manager("FB2EntityManager")
        local list = em:GetAllEntities(entityType)
        for i = 1, list:Num() do
            local item = list[i]
            if item ~= nil and fn(item) then return item end
        end
        return nil
    end

    -- The character object of a Zoi. Bindings do not always report existing Zois, so the
    -- entity manager is searched when needed and the answer cached.
    function p.character(eid)
        local c = p.zois[eid]
        if c then
            local alive = pcall(function() return c:GetEntityId() end)
            if alive then return c end
            p.zois[eid] = nil
        end
        c = eachEntity(inzoi.EB2EntityType.Character, function(item)
            local ok, id = pcall(function() return value(item:GetEntityId()) end)
            return ok and id == eid
        end)
        if c then p.zois[eid] = c end
        return c
    end

    -- Summoned cats on the household's lot: DEV_Void_Cat objects whose site is the home site.
    -- (Runtime-summoned cats never reach the ObjectTemplate binding, seen 2026-10-21.)
    function p.homeCats()
        local home, out = p.homeSite(), {}
        if not home then return out end
        eachEntity(inzoi.EB2EntityType.GameObject, function(item)
            local ok, isCat, site, eid = pcall(function()
                return tostring(item:GetObjectTableId()) == "DEV_Void_Cat",
                    tostring(item:GetLocatedSiteDtId()), item:GetObjectKey().Value
            end)
            if ok and isCat and site == home then
                p.cats[eid] = item
                out[#out + 1] = eid
            end
            return false
        end)
        return out
    end

    -- Object row ids on the home lot that are in `watched` (cat furniture). Same lookup as
    -- homeCats (verified there); UNVERIFIED for build-mode furniture.
    function p.homeObjects(watched)
        local home, want, out = p.homeSite(), {}, {}
        if not home then return out end
        for _, id in ipairs(watched or {}) do want[id] = true end
        eachEntity(inzoi.EB2EntityType.GameObject, function(item)
            local ok, id, site = pcall(function()
                return tostring(item:GetObjectTableId()), tostring(item:GetLocatedSiteDtId())
            end)
            if ok and want[id] and site == home then out[#out + 1] = id end
            return false
        end)
        return out
    end

    -- UNVERIFIED: FB2Actor:GetHouseholdEntityId, FB2EntityManager:FindHousehold, Currency component.
    local function wallet(hid)
        local em = inzoi.getB2Manager("FB2EntityManager")
        -- the controlled Zoi first; objects the game has released are skipped and forgotten
        local order, me = {}, p.possessed()
        if me and p.character(me) then order[1] = me end
        for eid in pairs(p.zois) do if eid ~= me then order[#order + 1] = eid end end
        for _, eid in ipairs(order) do
            local ok, hidStruct = pcall(function() return p.zois[eid]:GetHouseholdEntityId() end)
            if not ok then
                p.zois[eid] = nil
            elseif value(hidStruct) == hid then
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

    -- TrySubtractCurrency(value) answers true but does not change the money (seen 2026-10-21),
    -- so the city's currency (FB2City.GetCurrencyId) is reduced explicitly. Only a call
    -- after which the balance really dropped counts; the working call is reported once.
    local chargeReported = false
    function p.charge(hid, amount)
        local w, owner
        local okW = pcall(function() w, owner = wallet(hid) end)
        if not okW or not w then return false end
        local function balance()
            local a, b = w:GetCurrency(owner)
            return tonumber(type(b) == "number" and b or a)
        end
        local before = balance()
        if not before or before < amount then return false end
        local reason = inzoi.EB1TransactionReason.ExpenseDefault
        local attempts = {
            { "AddCurrency(-n)", function() return w:AddCurrency(-amount, reason, owner, false, owner) end },
            { "SetCurrency(id)", function()
                local id = inzoi.FB2City.GetCurrencyId()
                return w:SetCurrency(id, before - amount, reason, owner, false, owner)
            end },
        }
        local notes = {}
        for _, a in ipairs(attempts) do
            local ok, r = pcall(a[2])
            local after = balance()
            if after and after <= before - amount then
                if not chargeReported and p.report then p.report("charge via " .. a[1] .. ": " .. before .. " -> " .. after) end
                chargeReported = true
                return true
            end
            notes[#notes + 1] = a[1] .. ": " .. tostring(ok) .. "/" .. tostring(r) .. " balance " .. tostring(after)
        end
        if p.report then p.report("charge failed: " .. table.concat(notes, "; ")) end
        return false
    end

    -- Verified: inzoi.message.send_to_client(number entity id, channel, payload) reaches the
    -- B1 Zoi/ResidenceFamily binding of that entity (2026-10-21, rounds 6-7).
    function p.send(eid, channel, payload)
        inzoi.message.send_to_client(eid, channel, payload)
    end

    -- UNVERIFIED: FB2InteractionComponent:AddInteractionQueueByParam (luals-defs).
    function p.enqueue(zoi, targetEid, bagId)
        local ok, result = pcall(function()
            local character = p.character(zoi)
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
            -- all parameters: (target, impact point, bag, play reason, insert front,
            -- multi sequence, reason text, send packet, is next interaction)
            return ic:AddInteractionQueueByParam(target, character:GetLocation(), bagId,
                inzoi.EB1InteractionPlayReason.User, false, false, "PawHome", true, false)
        end)
        local success = ok and (result == inzoi.EB1AddInteractionQueueResult.Success or result == 37)
        if p.report then p.report("enqueue " .. tostring(bagId) .. ": " .. tostring(ok) .. " result " .. tostring(result)) end
        return success
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

    -- UNVERIFIED: FB2Actor:GetLocatedSiteDtId (luals-defs). The first answer is reported.
    local homeReported = false
    function p.atHome(zoi)
        local character = p.character(zoi)
        if not character then return false end
        local ok, site = pcall(function() return tostring(character:GetLocatedSiteDtId()) end)
        local home = p.homeSite()
        if not homeReported and p.report then
            p.report("atHome: Zoi site " .. tostring(ok and site) .. ", home " .. tostring(home))
            homeReported = true
        end
        return ok and home ~= nil and site == home
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

    -- The cat's actor (B1 ObjectTemplate binding owner, BP_Void_Cat). AActor's reflected
    -- functions are callable from B1 Lua although the LuaLS files do not list them; they are
    -- looked up by name so the static analyser does not reject the file. All of these were
    -- seen working in 20261019.16318.W on 2026-10-21 (docs/research/walking-cat.md 4.2-4.14).
    local function call(obj, name, ...)
        local fn = obj[name]
        if fn == nil then error("no method " .. name) end
        return fn(obj, ...)
    end

    function p.actorId(actor)
        local id = actor:GetEntityId()
        if type(id) ~= "number" and id ~= nil then id = id.Value end
        return tonumber(id)
    end

    -- A reference taken while the actor is being set up reports a zero scale (4.3).
    function p.valid(actor)
        local ok, s = pcall(call, actor, "GetActorScale3D")
        return ok and s ~= nil and s.X > 0
    end

    function p.setScale(actor, scale)
        local v = call(actor, "GetActorScale3D")
        v.X, v.Y, v.Z = scale, scale, scale
        call(actor, "SetActorScale3D", v)
        local now = call(actor, "GetActorScale3D")
        return math.abs(now.X - scale) < 0.001
    end

    local function vat(actor)
        return call(actor, "GetComponentByClass", inzoi.UB1AnimToTexComponent)
    end

    function p.currentVat(actor)
        local anim = vat(actor).Animation
        if anim == nil then return nil end
        return tostring(call(anim, "GetName"))
    end

    -- An unknown name is ignored by the game; success means the cat now plays `name`.
    function p.playVat(actor, name)
        call(vat(actor), "PlayAnimSequence", name, 0)
        local now = p.currentVat(actor)
        return now ~= nil and now:lower() == tostring(name):lower()
    end

    return p
end

return Platform
