-- Trait lookups and generation. A pet stores trait ids; behaviour lives in data/traits.lua.
local data = require("pawhome.data.traits")
local Util = require("pawhome.core.util")

local T = {}

function T.has(pet, id)
    return Util.contains(pet.traits, id)
end

-- Product of a scalar field (bondGain, runaway, ...) over the pet's traits.
function T.scalar(pet, field)
    local v = 1
    for _, id in ipairs(pet.traits) do
        local def = data[id]
        if def and def[field] then v = v * def[field] end
    end
    return v
end

-- Product of a keyed field (decay[hunger], actionGain[feed], ...).
function T.keyed(pet, field, key)
    local v = 1
    for _, id in ipairs(pet.traits) do
        local def = data[id]
        if def and def[field] and def[field][key] then v = v * def[field][key] end
    end
    return v
end

function T.allIds()
    return Util.sortedKeys(data)
end

local function conflicts(a, b)
    local da, db = data[a], data[b]
    return (da and Util.contains(da.conflicts or {}, b)) or (db and Util.contains(db.conflicts or {}, a))
end

-- 1-3 traits (like The Sims 4's up-to-three), never a conflicting pair.
function T.generate(ctx, count)
    local rng = ctx.rng
    count = count or rng:weighted({ 1, 2, 3 }, function(n) return n == 1 and 25 or (n == 2 and 45 or 30) end)
    local chosen = {}
    local pool = T.allIds()
    while #chosen < count do
        local candidates = {}
        for _, id in ipairs(pool) do
            local ok = not Util.contains(chosen, id)
            if ok then
                for _, c in ipairs(chosen) do
                    if conflicts(id, c) then ok = false break end
                end
            end
            if ok then candidates[#candidates + 1] = id end
        end
        if #candidates == 0 then break end
        chosen[#chosen + 1] = rng:weighted(candidates, function(id) return data[id].weight or 1 end)
    end
    return chosen
end

function T.unrevealed(pet)
    local out = {}
    for _, id in ipairs(pet.traits) do
        if not pet.revealed[id] then out[#out + 1] = id end
    end
    return out
end

-- Reveals one hidden trait; returns its id or nil.
function T.revealOne(ctx, pet)
    local hidden = T.unrevealed(pet)
    if #hidden == 0 then return nil end
    local id = hidden[ctx.rng:int(1, #hidden)]
    pet.revealed[id] = true
    return id
end

return T
