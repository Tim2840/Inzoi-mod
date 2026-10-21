-- Litter box presence, cat litter refill pack presence, and litter box lifecycle state
-- ("empty" -> "clean" -> "dirty") per household.
local data = require("pawhome.data.litter")
local Api = require("pawhome.core.api")

local L = {}

local function hkey(householdId) return tostring(householdId or 1) end

function L.present(ctx, householdId)
    ctx.litter = ctx.litter or {}
    local v = ctx.litter[householdId]
    if v == nil then
        v = #Api.homeObjects(householdId, { data.object }) > 0
        ctx.litter[householdId] = v
    end
    return v
end

function L.bagPresent(ctx, householdId)
    ctx.litterBags = ctx.litterBags or {}
    local v = ctx.litterBags[householdId]
    if v == nil then
        v = #Api.homeObjects(householdId, { data.bag }) > 0
        ctx.litterBags[householdId] = v
    end
    return v
end

-- Returns state ("empty" | "clean" | "dirty") and remaining uses.
-- A newly placed litter box in Build Mode starts as "empty" (0 uses) until refilled.
function L.boxState(ctx, householdId)
    local map = ctx.state and ctx.state.litterBox
    local entry = map and map[hkey(householdId)]
    if type(entry) ~= "table" then return "empty", 0 end
    return entry.state or "empty", tonumber(entry.uses) or 0
end

-- Refills an empty (or partially used) litter box using a Cat Litter Refill Pack.
function L.refill(ctx, householdId)
    ctx.state.litterBox = ctx.state.litterBox or {}
    ctx.state.litterBox[hkey(householdId)] = { state = "clean", uses = data.usesPerFill }
    return "clean", data.usesPerFill
end

-- Marks the litter box as dirty after a cat uses it.
function L.markUsed(ctx, householdId)
    ctx.state.litterBox = ctx.state.litterBox or {}
    local k = hkey(householdId)
    local entry = ctx.state.litterBox[k] or { state = "clean", uses = data.usesPerFill }
    entry.state = "dirty"
    ctx.state.litterBox[k] = entry
    return entry.state, entry.uses
end

-- Cleans a dirty litter box. Decrements remaining uses; when uses reach 0, the box becomes "empty".
function L.clean(ctx, householdId)
    ctx.state.litterBox = ctx.state.litterBox or {}
    local k = hkey(householdId)
    local entry = ctx.state.litterBox[k]
    if type(entry) == "table" then
        local uses = math.max(0, (tonumber(entry.uses) or 1) - 1)
        entry.uses = uses
        entry.state = uses > 0 and "clean" or "empty"
        return entry.state, uses
    end
    return "clean", data.usesPerFill
end

function L.forget(ctx)
    ctx.litter = {}
    ctx.litterBags = {}
end

return L
