-- Cat furniture on the household's lot makes the needs drop more slowly.
local data = require("pawhome.data.enrichment")
local Api = require("pawhome.core.api")

local En = {}

-- Object row ids the adapter should look for on the lot.
function En.watched()
    local out = {}
    for _, id in ipairs(data.order) do out[#out + 1] = id end
    for alias in pairs(data.aliases) do out[#out + 1] = alias end
    table.sort(out)
    return out
end

-- Pieces present on the household's lot, in data order, without duplicates.
function En.pieces(householdId)
    local seen = {}
    for _, id in ipairs(Api.homeObjects(householdId, En.watched())) do
        local piece = data.aliases[id] or id
        if data.items[piece] then seen[piece] = true end
    end
    local out = {}
    for _, id in ipairs(data.order) do
        if seen[id] then out[#out + 1] = id end
    end
    return out
end

-- Decay multiplier per need for a set of pieces, e.g. { fun = 0.6, energy = 0.85 }.
function En.multipliers(pieces)
    local cut = {}
    for _, id in ipairs(pieces) do
        for need, r in pairs(data.items[id]) do cut[need] = (cut[need] or 0) + r end
    end
    local mul = {}
    for need, r in pairs(cut) do mul[need] = 1 - math.min(r, data.maxReduction) end
    return mul
end

-- Looked up once per household per engine tick (the lot does not change mid-tick).
function En.forHousehold(ctx, householdId)
    ctx.enrichment = ctx.enrichment or {}
    local e = ctx.enrichment[householdId]
    if not e then
        local pieces = En.pieces(householdId)
        e = { pieces = pieces, mul = En.multipliers(pieces) }
        ctx.enrichment[householdId] = e
    end
    return e
end

function En.decayMul(ctx, pet, need)
    if pet.status ~= "home" then return 1 end
    return En.forHousehold(ctx, pet.household).mul[need] or 1
end

return En
