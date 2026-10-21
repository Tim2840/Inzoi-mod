-- The ONLY module that talks to the game. Everything else calls Api.* so a game
-- update (or a different probe result) means editing an adapter, not the pet logic.
--
-- An adapter is a table of functions (see adapters/mock.lua for the reference one):
--   required: now, saveGet, saveSet
--   optional: notify, householdMembers, funds, charge, addBuff, listStrays,
--             bringStray, spawnPet, entityExists, despawnPet,
--             playAnimation, setCoats, locale, logSink,
--             slotId, subscribe   (see below: the savegame slot the player is in),
--             saveGetBackup       (older generations of a save, see below)
--   caps: { spawn = bool, moveStray = bool, animate = bool, buffs = bool }
local Log = require("pawhome.core.log")

local Api = { adapter = nil }

local REQUIRED = { "now", "saveGet", "saveSet" }

function Api.use(adapter)
    for _, name in ipairs(REQUIRED) do
        if type(adapter[name]) ~= "function" then
            return false, "adapter is missing required function: " .. name
        end
    end
    Api.adapter = adapter
    if adapter.logSink then Log.setSink(adapter.logSink) end
    return true
end

function Api.caps()
    return (Api.adapter and Api.adapter.caps) or {}
end

-- Calls an adapter function and never lets a game-side error escape.
local function call(name, ...)
    local fn = Api.adapter and Api.adapter[name]
    if not fn then return false, "unsupported" end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        Log.error("adapter." .. name .. " failed: " .. tostring(a))
        return false, tostring(a)
    end
    return true, a, b
end

function Api.now()
    local ok, v = call("now")
    return ok and tonumber(v) or nil
end

function Api.saveGet(key)
    local ok, v = call("saveGet", key)
    return ok and v or nil
end

-- Optional. saveGetBackup(key, n): the n-th older generation of a save (1 = the one right
-- before the current), or nil. The mod uses it only when the current save cannot be read.
function Api.saveGetBackup(key, n)
    local ok, v = call("saveGetBackup", key, n)
    return ok and v or nil
end

function Api.saveSet(key, value)
    return (call("saveSet", key, value))
end

-- Optional. slotId() = identifier of the savegame slot that is loaded right now.
-- An adapter that keeps one data file per slot MUST implement it, otherwise the mod cannot
-- notice that the player switched saves. Two different situations, do not mix them up:
--   * the adapter has NO slot concept  -> it does not define slotId at all (Api.hasSlots() = false)
--   * the adapter has slots but NO save is loaded right now (loading screen, main menu)
--     -> slotId() returns nil. The mod then pauses: it reads and writes nothing.
-- If slotId() raises an error the mod treats it as "no save loaded" (the safe choice).
function Api.hasSlots()
    return Api.adapter ~= nil and type(Api.adapter.slotId) == "function"
end

function Api.slotId()
    local ok, v = call("slotId")
    if ok and v ~= nil then return tostring(v) end
    return nil
end

-- Optional. subscribe(event, fn): the game side calls fn() when `event` happens.
-- Events defined so far: "slot_changed". The mod also polls slotId() on every call, so
-- subscribing is only an optimisation (react at once instead of at the next tick).
function Api.subscribe(event, fn)
    return (call("subscribe", event, fn))
end

function Api.locale()
    local ok, v = call("locale")
    return ok and v or "en"
end

function Api.notify(householdId, kind, text)
    local ok = call("notify", householdId, kind, text)
    return ok
end

function Api.householdMembers(householdId)
    local ok, v = call("householdMembers", householdId)
    return ok and v or {}
end

function Api.funds(householdId)
    local ok, v = call("funds", householdId)
    return ok and tonumber(v) or 0
end

-- Returns true when the money was taken.
function Api.charge(householdId, amount)
    if amount <= 0 then return true end
    local ok, v = call("charge", householdId, amount)
    return ok and v == true
end

function Api.addBuff(zoiId, buffId, durationMinutes)
    return (call("addBuff", zoiId, buffId, durationMinutes))
end

function Api.listStrays(householdId)
    local ok, v = call("listStrays", householdId)
    return ok and v or {}
end

-- Move a street cat into the household's lot (plan A). Returns entity ref or nil.
function Api.bringStray(strayRef, householdId)
    local ok, ref = call("bringStray", strayRef, householdId)
    return ok and ref or nil
end

-- Create a cat on the household's lot (plan B). Returns entity ref or nil.
function Api.spawnPet(householdId, spec)
    local ok, ref = call("spawnPet", householdId, spec)
    return ok and ref or nil
end

function Api.entityExists(ref)
    if ref == nil then return false end
    local ok, v = call("entityExists", ref)
    return ok and v == true
end

function Api.despawnPet(ref)
    if ref == nil then return false end
    return (call("despawnPet", ref))
end

-- A copy of this household's mod data kept outside the savegame, offered when the savegame
-- has none (e.g. it was saved while the UI mod was off): { day = n, cache = { key = value } }.
function Api.backup()
    local ok, v = call("backup")
    return ok and type(v) == "table" and v or nil
end

-- Puts the backup's data in place of the current (empty) data. True when done.
function Api.restoreBackup()
    local ok, v = call("restoreBackup")
    return ok and v == true
end

-- Object row ids found on the household's lot, limited to `watched` (a list of row ids).
function Api.homeObjects(householdId, watched)
    local ok, v = call("homeObjects", householdId, watched)
    return ok and type(v) == "table" and v or {}
end

-- Care the player gave the pet in the game itself (e.g. the game's own feed/play
-- interactions on the cat), since the last call: { { kind = actionId, zoi = zoiId }, ... }.
function Api.takeCare(ref)
    if ref == nil then return {} end
    local ok, v = call("takeCare", ref)
    return ok and type(v) == "table" and v or {}
end

-- Optional. The coat each pet at home should show: { { ref, coat, texture }, ... } (the whole
-- list every time; pets missing from it are left to the game). Adapters that cannot change
-- the look simply do not implement it.
function Api.setCoats(list)
    return (call("setCoats", list or {}))
end

function Api.playAnimation(ref, animationId)
    if ref == nil then return false end
    return (call("playAnimation", ref, animationId))
end

return Api
