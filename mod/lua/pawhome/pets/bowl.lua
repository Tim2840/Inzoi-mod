-- Food bowl presence and how many meals are left in it, per household.
local data = require("pawhome.data.bowl")
local Api = require("pawhome.core.api")

local B = {}

local function hkey(householdId) return tostring(householdId or 1) end

function B.present(ctx, householdId)
    ctx.bowlSeen = ctx.bowlSeen or {}
    local v = ctx.bowlSeen[householdId]
    if v == nil then
        v = #Api.homeObjects(householdId, { data.object }) > 0
        ctx.bowlSeen[householdId] = v
    end
    return v
end

function B.meals(ctx, householdId)
    local map = ctx.state and ctx.state.bowl
    local entry = map and map[hkey(householdId)]
    return type(entry) == "table" and tonumber(entry.meals) or 0
end

function B.fill(ctx, householdId)
    ctx.state.bowl = ctx.state.bowl or {}
    ctx.state.bowl[hkey(householdId)] = { meals = data.meals }
    return data.meals
end

-- One meal eaten; returns the meals left.
function B.take(ctx, householdId)
    ctx.state.bowl = ctx.state.bowl or {}
    local left = math.max(0, B.meals(ctx, householdId) - 1)
    ctx.state.bowl[hkey(householdId)] = { meals = left }
    return left
end

function B.forget(ctx) ctx.bowlSeen = {} end

return B
