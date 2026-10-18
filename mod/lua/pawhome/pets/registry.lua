-- The list of pets in the savegame.
local Util = require("pawhome.core.util")
local Needs = require("pawhome.pets.needs")
local Aging = require("pawhome.pets.aging")
local habits = require("pawhome.data.habits")
local Traits = require("pawhome.pets.traits")

local R = {}

-- spec: name, household, stage, traits, revealed(table id->true), entity, appearance
function R.create(ctx, spec)
    local id = ctx.state.nextPetId
    ctx.state.nextPetId = id + 1

    local pet = {
        id = id,
        name = spec.name,
        species = "cat",
        household = spec.household,
        stage = spec.stage or "kitten",
        ageMinutes = 0,
        lifeMul = ctx.rng:range(0.85, 1.15),
        traits = spec.traits,
        revealed = spec.revealed or {},
        needs = Needs.initial(ctx),
        bond = {},
        habits = {},
        neglect = 0,
        status = "home",          -- home | away | lost | dead
        entity = spec.entity,
        appearance = spec.appearance,
        cooldowns = {},
        notified = {},
        flags = {},
        adoptedAt = ctx.now,
    }
    pet.ageMinutes = Aging.stageStart(ctx, pet, pet.stage)

    local mischief = Traits.scalar(pet, "mischief")
    for _, hid in ipairs(habits.order) do
        pet.habits[hid] = Util.clamp(habits[hid].start * mischief, 0.05, 0.9)
    end

    ctx.state.pets[#ctx.state.pets + 1] = pet
    return pet
end

function R.get(ctx, id)
    for _, pet in ipairs(ctx.state.pets) do
        if pet.id == id then return pet end
    end
    return nil
end

-- Pets that still belong to the household (at home or away).
function R.list(ctx, householdId)
    local out = {}
    for _, pet in ipairs(ctx.state.pets) do
        local belongs = householdId == nil or pet.household == householdId
        if belongs and (pet.status == "home" or pet.status == "away") then
            out[#out + 1] = pet
        end
    end
    return out
end

function R.home(ctx, householdId)
    local out = {}
    for _, pet in ipairs(R.list(ctx, householdId)) do
        if pet.status == "home" then out[#out + 1] = pet end
    end
    return out
end

function R.count(ctx, householdId)
    return #R.list(ctx, householdId)
end

return R
