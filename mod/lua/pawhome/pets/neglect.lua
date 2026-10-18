-- Neglect and animal control. Counterpart of The Sims 4 animal control taking away a
-- neglected pet: soft penalty -> warning visit -> the pet is taken to the shelter
-- (see pets/shelter.lua for redeeming it).
local Needs = require("pawhome.pets.needs")
local Bond = require("pawhome.pets.bond")
local Traits = require("pawhome.pets.traits")
local Api = require("pawhome.core.api")
local Util = require("pawhome.core.util")
local data = require("pawhome.data.neglect")

local N = {}

-- Minutes of continuous neglect before this pet is taken. Wandering personalities
-- get picked up sooner, a well-loved pet gets more time.
function N.impoundMinutes(pet)
    local base = data.impoundHours * 60 / Traits.scalar(pet, "strayRisk")
    return base * (1 + Bond.best(pet) / 100)
end

local function dropBond(pet, amount)
    for k, v in pairs(pet.bond) do
        pet.bond[k] = Util.clamp(v - amount, 0, 100)
    end
end

function N.step(ctx, pet, minutes)
    if Needs.isCritical(pet) then
        pet.neglect = pet.neglect + minutes
    else
        pet.neglect = math.max(0, pet.neglect - minutes * 1.5)
    end

    local limit = N.impoundMinutes(pet)
    local warn = limit * data.warnFraction

    -- soft penalty: the pet slowly stops trusting you
    if pet.neglect >= limit * data.softFraction then
        dropBond(pet, data.softBondLossPerHour * minutes / 60)
    end

    if pet.neglect >= warn and not pet.flags.warned then
        pet.flags.warned = true
        ctx.emit(pet, "neglect_warning")
    elseif pet.neglect < warn * 0.5 then
        pet.flags.warned = nil
    end

    if ctx.cfg.animalControl and pet.neglect >= limit then
        N.impound(ctx, pet)
    end
end

function N.impound(ctx, pet)
    pet.status = "impounded"
    pet.impoundedAt = ctx.now
    pet.neglect = 0
    pet.flags.warned = nil
    pet.flags.redeemable = nil
    Api.despawnPet(pet.entity)
    pet.entity = nil
    ctx.emit(pet, "impounded")
end

return N
