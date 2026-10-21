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

-- A Zoi's location is the middle of her body (capsule centre), not her feet: seen 2026-10-22,
-- Zoi at Z 158.0 standing on a floor at Z 75.3, so a cat put at the Zoi's Z floated ~83 cm up.
-- Picks the floor height under a Zoi from what the game could tell us, best first:
--   nodeFloor  FB2CharacterMovementComponent:GetCurrentNodeFloorZ (UNVERIFIED out-param shape)
--   halfHeight FB2CharacterMovementComponent.HalfHeight            (UNVERIFIED)
--   catZ       the cat's own Z before the move (it stands on a floor), if on the same storey
-- and falls back to the observed capsule half height. Returns z, how.
Platform.ZOI_HALF_HEIGHT = 83
function Platform.floorUnderZoi(zoiZ, nodeFloor, halfHeight, catZ)
    local guess = zoiZ - Platform.ZOI_HALF_HEIGHT
    local half = type(halfHeight) == "number" and halfHeight > 20 and halfHeight < 200 and halfHeight or nil
    local feet = half and (zoiZ - half) or nil
    -- The movement component's node floor is the navigation ground, which is NOT the floor the Zoi
    -- stands on when she is on a deck or an upper floor (seen 2026-10-22 at Cahaya_Residence_LocalHouse1:
    -- node floor 0.0 under a Zoi whose feet were at 68, so the called cat appeared under the deck
    -- and "vanished"). It is only trusted when it agrees with her feet.
    if type(nodeFloor) == "number" and nodeFloor <= zoiZ and nodeFloor >= zoiZ - 200 then
        if not feet or math.abs(nodeFloor - feet) <= 30 then return nodeFloor, "node floor" end
    end
    if feet then return feet, "half height" end
    if type(catZ) == "number" and math.abs(catZ - guess) < 60 then
        return catZ, "cat floor"
    end
    return guess, "default half height"
end

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
        if want.PawHome_LitterBox then want.Bustub01_v01 = true end
        if want.PawHome_LitterBag then
            want.Farm_Fertilizer01 = true
            want.E01_CatSandSpray01 = true
        end
        eachEntity(inzoi.EB2EntityType.GameObject, function(item)
            local ok, id, site = pcall(function()
                return tostring(item:GetObjectTableId()), tostring(item:GetLocatedSiteDtId())
            end)
            if ok and want[id] and site == home then
                if id == "Bustub01_v01" then
                    out[#out + 1] = "PawHome_LitterBox"
                elseif id == "Farm_Fertilizer01" or id == "E01_CatSandSpray01" then
                    out[#out + 1] = "PawHome_LitterBag"
                else
                    out[#out + 1] = id
                end
            end
            return false
        end)
        return out
    end

    -- Finds an object of `objectId` (or its base-game tub row Bustub01_v01 for PawHome_LitterBox)
    -- on the home lot, moves the B2 cat entity there, and returns x, y, z, yaw for the B1 actor.
    function p.moveCatToObject(eid, objectId)
        local home = p.homeSite()
        if not home then return nil end
        local want = { [tostring(objectId)] = true }
        if objectId == "PawHome_LitterBox" then want.Bustub01_v01 = true end
        local targetObj = eachEntity(inzoi.EB2EntityType.GameObject, function(item)
            local ok, id, site = pcall(function()
                return tostring(item:GetObjectTableId()), tostring(item:GetLocatedSiteDtId())
            end)
            return ok and want[id] and site == home
        end)
        if not targetObj then return nil end
        local okLoc, loc = pcall(function() return targetObj:GetLocation() end)
        if not okLoc or not loc then return nil end
        local okRot, rot = pcall(function() return targetObj:GetRotation() end)
        local yaw = (okRot and rot and tonumber(rot.Yaw)) or 0
        local x, y, z = tonumber(loc.X) or 0, tonumber(loc.Y) or 0, (tonumber(loc.Z) or 0) + 3
        local cat = p.cats[eid]
        if not cat then p.homeCats(); cat = p.cats[eid] end
        if cat then
            pcall(function()
                local cLoc = cat:GetLocation()
                cLoc.X, cLoc.Y, cLoc.Z = x, y, z
                local cRot = cat:GetRotation()
                cRot.Pitch, cRot.Yaw, cRot.Roll = 0, yaw, 0
                cat:SetLocationAndRotationOnlySimul(cLoc, cRot)
            end)
        end
        if p.report then
            p.report(string.format("moveCatToObject %s -> %s at (%.1f, %.1f, %.1f)", tostring(eid), tostring(objectId), x, y, z))
        end
        return x, y, z, yaw
    end

    -- Moves the B2 cat entity 90 cm in front of `zoiId` (or the possessed Zoi) and returns
    -- x, y, z, yaw for the B1 actor.
    function p.moveCatToZoi(eid, zoiId)
        local zoi = tonumber(zoiId) or p.possessed()
        if not zoi then return nil end
        local character = p.character(zoi)
        if not character then return nil end
        local okLoc, loc = pcall(function() return character:GetLocation() end)
        if not okLoc or not loc then return nil end
        local okRot, rot = pcall(function() return character:GetRotation() end)
        local zoiYaw = (okRot and rot and tonumber(rot.Yaw)) or 0
        local rad = math.rad(zoiYaw)
        local dist = 90
        local x = (tonumber(loc.X) or 0) + math.cos(rad) * dist
        local y = (tonumber(loc.Y) or 0) + math.sin(rad) * dist
        local zoiZ = tonumber(loc.Z) or 0
        local catYaw = (zoiYaw + 180) % 360
        local cat = p.cats[eid]
        if not cat then p.homeCats(); cat = p.cats[eid] end
        -- the Zoi's location is her body centre: find the floor under her feet
        local nodeFloor, halfHeight, catZ
        pcall(function()
            local mc = character:GetMovementComponent()
            local okH, h = pcall(function() return mc.HalfHeight end)
            if okH then halfHeight = tonumber(h) end
            local okF, a, b = pcall(function() return mc:GetCurrentNodeFloorZ(0) end)
            if okF then nodeFloor = (type(b) == "number" and b) or (type(a) == "number" and a) or nil end
        end)
        if cat then pcall(function() catZ = tonumber(cat:GetLocation().Z) end) end
        local z, how = Platform.floorUnderZoi(zoiZ, nodeFloor, halfHeight, catZ)
        if p.report then
            p.report(string.format("floor under zoi: %.1f via %s (zoi %.1f, node %s, half %s, cat %s)",
                z, how, zoiZ, tostring(nodeFloor), tostring(halfHeight), tostring(catZ)))
        end
        if cat then
            pcall(function()
                local cLoc = cat:GetLocation()
                cLoc.X, cLoc.Y, cLoc.Z = x, y, z
                local cRot = cat:GetRotation()
                cRot.Pitch, cRot.Yaw, cRot.Roll = 0, catYaw, 0
                cat:SetLocationAndRotationOnlySimul(cLoc, cRot)
            end)
        end
        if p.report then
            p.report(string.format("moveCatToZoi %s -> zoi %s at (%.1f, %.1f, %.1f)", tostring(eid), tostring(zoi), x, y, z))
        end
        return x, y, z, catYaw
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

    -- Gives money (a keepsake's coins). Same SetCurrency(id) path as charge, which is verified;
    -- the income reason and the positive amount are UNVERIFIED. True only when the balance rose.
    local creditReported = false
    function p.credit(hid, amount)
        local w, owner
        local okW = pcall(function() w, owner = wallet(hid) end)
        if not okW or not w then return false end
        local function balance()
            local a, b = w:GetCurrency(owner)
            return tonumber(type(b) == "number" and b or a)
        end
        local before = balance()
        if not before then return false end
        local ok, err = pcall(function()
            local id = inzoi.FB2City.GetCurrencyId()
            return w:SetCurrency(id, before + amount, inzoi.EB1TransactionReason.IncomeDefault, owner, false, owner)
        end)
        local after = balance()
        if after and after >= before + amount then
            if not creditReported and p.report then p.report("credit via SetCurrency(id): " .. before .. " -> " .. after) end
            creditReported = true
            return true
        end
        if p.report then p.report("credit failed: " .. tostring(ok) .. "/" .. tostring(err) .. " balance " .. tostring(after)) end
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

    -- True when the Zoi has nothing queued and nothing running (interaction.get_queue, Public).
    -- Verified answer shape 2026-10-22: {"queue_count":0,"is_empty":true} (no current interaction key).
    function p.zoiIdle(zoi)
        local t = cli("interaction.get_queue" .. (zoi and (" entity_id=" .. tostring(zoi)) or ""))
        if type(t) ~= "table" then return true end
        if t.is_empty == false then return false end
        for k, v in pairs(t) do
            if k ~= "queue_count" and k ~= "is_empty" and v ~= nil and v ~= false and v ~= "" then
                if tostring(k):lower():find("current") then return false end
            end
        end
        return true
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

    -- Cat actors (BP_Void_Cat_C, the owner of the B1 cat binding). Verified 20261019.16318.W,
    -- 2026-10-21 (docs/research/fixed-coat.md): GetEntityId().Value is the B2 entity id;
    -- K2_GetComponentsByClass(UE.UMeshComponent) gives the body ("StaticMesh") and fur
    -- ("StaticMeshFur") meshes, whose material 0 is a dynamic material instance with the
    -- texture parameter "Color Tex"; UE.UObject.Load loads the coat texture; setting the
    -- parameter changes the coat at once and the game does not set it back.
    function p.actorEntityId(actor)
        local id = actor:GetEntityId()
        if type(id) == "number" then return id end
        return id and tonumber(id.Value) or nil
    end

    local COAT_DIR = "/Game/Characters/Void/Void_Cat/Textures/"
    function p.applyCoat(actor, texture)
        -- asked of the game every time: a texture object kept from an earlier call may have been
        -- released by the game by now (suspected cause of coats that stopped applying; unverified)
        local tex = UE.UObject.Load(COAT_DIR .. texture .. "." .. texture)
        if tex == nil then return false, "texture " .. texture .. " not found" end
        local comps = actor:K2_GetComponentsByClass(UE.UMeshComponent)
        local set, errors = 0, {}
        for i = 1, comps:Num() do
            -- only dynamic instances take parameters; the dummy skeletal mesh has no material
            local ok, err = pcall(function()
                local mat = comps:Get(i):GetMaterial(0)
                mat:SetTextureParameterValue("Color Tex", tex)
            end)
            if ok then set = set + 1 else errors[#errors + 1] = tostring(err):sub(1, 60) end
        end
        -- the second result says why nothing was set (shown in the log)
        return set > 0, ("%d of %d mesh components took it%s"):format(set, comps:Num(),
            #errors > 0 and (": " .. table.concat(errors, " / ")) or "")
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

    function p.setLocation(actor, x, y, z)
        local v = call(actor, "K2_GetActorLocation")
        v.X, v.Y, v.Z = x, y, z
        call(actor, "K2_SetActorLocation", v, false, nil, true)
        local now = call(actor, "K2_GetActorLocation")
        return math.abs(now.X - x) < 1 and math.abs(now.Y - y) < 1
    end

    function p.setYaw(actor, yaw)
        local r = call(actor, "K2_GetActorRotation")
        r.Pitch, r.Yaw, r.Roll = 0, yaw, 0
        call(actor, "K2_SetActorRotation", r, true)
        return true
    end

    local function vat(actor)
        return call(actor, "GetComponentByClass", inzoi.UB1AnimToTexComponent)
    end

    function p.currentVat(actor)
        local anim = vat(actor).Animation
        if anim == nil then return nil end
        return tostring(call(anim, "GetName"))
    end

    -- Direct B1 play (kept for reference, no longer used for the cat's animations): UB1AnimToTexComponent
    -- :PlayAnimSequence(name, 0) changes `Animation` and shows the clip's FIRST frame, then the cat stays
    -- frozen (frames of an enlarged cat over 14 s were identical, 2026-10-22). Clips only play when the
    -- game's own PlayVATAnim action runs: see adapters/inzoi.lua "playClip" and the PawHome_Vat_* rows.
    -- An unknown name is ignored by the game; success means the cat now shows `name`.
    function p.playVat(actor, name)
        local comp = vat(actor)
        local cur = p.currentVat(actor)
        if cur ~= nil and cur:lower() == tostring(name):lower() then
            local alt = cur:lower() == "anim_voidcat_sit_idle_01"
                and "ANIM_VoidCat_Sit_Idle_02" or "ANIM_VoidCat_Sit_Idle_01"
            pcall(call, comp, "PlayAnimSequence", alt, 0)
        end
        call(comp, "PlayAnimSequence", name, 0)
        local now = p.currentVat(actor)
        return now ~= nil and now:lower() == tostring(name):lower()
    end

    return p
end

return Platform
