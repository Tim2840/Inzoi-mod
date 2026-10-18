-- Neglect, running away and coming back. Counterpart of The Sims 4 animal control
-- taking away a neglected pet, but gentler: the pet leaves and may return.
local Needs = require("pawhome.pets.needs")
local Bond = require("pawhome.pets.bond")
local Traits = require("pawhome.pets.traits")
local Api = require("pawhome.core.api")
local Util = require("pawhome.core.util")

local N = {}

local RUNAWAY_HOURS = 48      -- continuous neglect (for an average pet) before leaving
local WARNING_FRACTION = 0.4
local MIN_AWAY_DAYS = 2
local MAX_AWAY_DAYS = 7

function N.runawayMinutes(pet)
    local base = RUNAWAY_HOURS * 60 / Traits.scalar(pet, "runaway")
    return base * (1 + Bond.best(pet) / 100)
end

function N.step(ctx, pet, minutes)
    if Needs.isCritical(pet) then
        pet.neglect = pet.neglect + minutes
    else
        pet.neglect = math.max(0, pet.neglect - minutes * 1.5)
    end

    local limit = N.runawayMinutes(pet)
    local warn = limit * WARNING_FRACTION
    if pet.neglect >= warn and not pet.flags.warned then
        pet.flags.warned = true
        ctx.emit(pet, "neglect_warning")
    elseif pet.neglect < warn * 0.5 then
        pet.flags.warned = nil
    end

    if ctx.cfg.neglectRunaway and pet.neglect >= limit then
        N.runAway(ctx, pet)
    end
end

function N.runAway(ctx, pet)
    pet.status = "away"
    pet.awaySince = ctx.now
    pet.neglect = 0
    pet.flags.warned = nil
    Api.despawnPet(pet.entity)
    pet.entity = nil
    ctx.emit(pet, "ran_away")
end

-- Called while the pet is away. Returns nothing; changes pet.status.
function N.stepAway(ctx, pet, minutes)
    local days = (ctx.now - (pet.awaySince or ctx.now)) / Util.MINUTES_PER_DAY
    if days >= MAX_AWAY_DAYS then
        pet.status = "lost"
        Api.releaseStray(nil, { name = pet.name, appearance = pet.appearance, traits = pet.traits })
        ctx.emit(pet, "lost_for_good")
        return
    end
    if days < MIN_AWAY_DAYS then return end

    local perDay = Util.clamp(0.1 + Bond.best(pet) / 200, 0.1, 0.55)
    local p = 1 - (1 - perDay) ^ (minutes / Util.MINUTES_PER_DAY)
    if ctx.rng:chance(p) then N.comeBack(ctx, pet) end
end

function N.comeBack(ctx, pet)
    pet.status = "home"
    pet.awaySince = nil
    pet.neglect = 0
    pet.needs.hunger, pet.needs.bladder, pet.needs.fun, pet.needs.energy = 40, 55, 30, 50
    if Api.caps().spawn then
        pet.entity = Api.spawnPet(pet.household, { appearance = pet.appearance, stage = pet.stage })
    end
    ctx.emit(pet, "came_back")
end

return N
