-- Bond (0-100) between one Zoi and one pet. Keys are strings so saves stay stable.
local Util = require("pawhome.core.util")
local Traits = require("pawhome.pets.traits")
local stages = require("pawhome.data.stages")

local B = {}

function B.key(zoiId) return tostring(zoiId) end

function B.get(pet, zoiId)
    return pet.bond[B.key(zoiId)] or 0
end

local function stageBondGain(pet)
    for _, s in ipairs(stages) do
        if s.id == pet.stage then return s.bondGain or 1 end
    end
    return 1
end

-- Positive changes are scaled by the pet's personality and age; losses are not.
function B.add(pet, zoiId, amount)
    if amount > 0 then amount = amount * Traits.scalar(pet, "bondGain") * stageBondGain(pet) end
    local k = B.key(zoiId)
    pet.bond[k] = Util.clamp((pet.bond[k] or 0) + amount, 0, 100)
    return pet.bond[k]
end

function B.level(value)
    if value >= 75 then return "best_friend" end
    if value >= 45 then return "friend" end
    if value >= 20 then return "acquainted" end
    return "stranger"
end

function B.best(pet)
    local top = 0
    for _, v in pairs(pet.bond) do
        if v > top then top = v end
    end
    return top
end

return B
