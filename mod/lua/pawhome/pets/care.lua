-- Player care interactions (feed, play, cuddle, groom, litter, praise, scold, get-to-know).
local actions = require("pawhome.data.actions")
local Api = require("pawhome.core.api")
local Registry = require("pawhome.pets.registry")
local Needs = require("pawhome.pets.needs")
local Bond = require("pawhome.pets.bond")
local Traits = require("pawhome.pets.traits")
local Training = require("pawhome.pets.training")
local Util = require("pawhome.core.util")

local C = {}

local function fail(ctx, reason, params)
    return { ok = false, reason = reason, message = ctx.t("fail." .. reason, params) }
end

local function onCooldown(ctx, pet, actionId)
    local until_ = pet.cooldowns[actionId]
    return until_ ~= nil and ctx.now < until_
end

function C.perform(ctx, petId, zoiId, actionId)
    local pet = Registry.get(ctx, petId)
    if not pet or (pet.status ~= "home" and pet.status ~= "impounded") then return fail(ctx, "no_pet") end
    if pet.status ~= "home" then return fail(ctx, "not_home", { name = pet.name }) end
    local def = actions[actionId]
    if not def or type(def) ~= "table" or actionId == "order" then return fail(ctx, "unknown_action") end
    if onCooldown(ctx, pet, actionId) then return fail(ctx, "cooldown", { name = pet.name }) end

    if def.requiresBelow then
        for need, limit in pairs(def.requiresBelow) do
            if pet.needs[need] >= limit then return fail(ctx, "not_hungry", { name = pet.name }) end
        end
    end
    if def.requiresAbove then
        for need, limit in pairs(def.requiresAbove) do
            if pet.needs[need] < limit then return fail(ctx, "too_tired", { name = pet.name }) end
        end
    end

    local result = { ok = true, petId = pet.id, action = actionId, extra = {} }
    local actionName = ctx.t("actions." .. actionId .. ".name")
    result.message = ctx.t("msg.action_done", { name = pet.name, action = actionName })

    -- get to know: nothing left to learn costs nothing
    if def.reveal then
        if #Traits.unrevealed(pet) == 0 then
            result.message = ctx.t("msg.nothing_to_learn", { name = pet.name })
            result.extra.nothingToLearn = true
            return result
        end
    end

    -- needs (household scope = everyone at home shares the litter box)
    local targets = { pet }
    if def.scope == "household" then targets = Registry.home(ctx, pet.household) end
    for _, target in ipairs(targets) do
        if def.needs then
            Needs.apply(target, def.needs, function() return Traits.keyed(target, "actionGain", actionId) end)
        end
        target.cooldowns[actionId] = ctx.now + def.cooldown
    end

    if def.bond and def.bond ~= 0 then Bond.add(pet, zoiId, def.bond) end
    Training.addXp(ctx, pet, zoiId, def.xp or 0)

    if def.reveal then
        local chance = Util.clamp((0.35 + Bond.get(pet, zoiId) / 150) * Traits.scalar(pet, "reveal"), 0.15, 0.95)
        if ctx.rng:chance(chance) then
            local id = Traits.revealOne(ctx, pet)
            result.extra.revealed = id
            result.message = ctx.t("msg.trait_revealed", { name = pet.name, trait = ctx.t("traits." .. id .. ".name") })
        end
    end

    if def.shape == -1 then
        local landed = Training.scold(ctx, pet, zoiId)
        result.extra.shaped = landed
        if not landed and Traits.scalar(pet, "scoldResist") < 0.5 then
            result.message = ctx.t("msg.ignores_scold", { name = pet.name })
        end
    elseif def.shape == 1 then
        Training.praise(ctx, pet, zoiId)
    end

    if def.zoiFunPenalty then Api.addBuff(zoiId, "pawhome_chore", 60) end
    if def.animation then Api.playAnimation(pet.entity, def.animation) end

    result.bond = Bond.get(pet, zoiId)
    result.bondLevel = Bond.level(result.bond)
    return result
end

return C
