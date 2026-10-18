-- The ONLY module that talks to the game. Everything else calls Api.* so a game
-- update (or a different probe result) means editing an adapter, not the pet logic.
--
-- An adapter is a table of functions (see adapters/mock.lua for the reference one):
--   required: now, saveGet, saveSet
--   optional: notify, householdMembers, funds, charge, addBuff, listStrays,
--             bringStray, spawnPet, entityExists, despawnPet, releaseStray,
--             playAnimation, locale, logSink
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

function Api.saveSet(key, value)
    return (call("saveSet", key, value))
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

-- A pet that ran away and never came back becomes a street cat again.
function Api.releaseStray(ref, spec)
    return (call("releaseStray", ref, spec))
end

function Api.playAnimation(ref, animationId)
    if ref == nil then return false end
    return (call("playAnimation", ref, animationId))
end

return Api
