-- Player care interactions (feed, play, cuddle, groom, litter, praise, scold, get-to-know).
-- No cooldowns (docs/design/gameplay-v2.md): doing the same thing again and again is worth less
-- ("fatigue"), and doing what the cat wants right now is a happy moment worth much more.
local actions = require("pawhome.data.actions")
local careData = require("pawhome.data.care")
local Api = require("pawhome.core.api")
local Registry = require("pawhome.pets.registry")
local Needs = require("pawhome.pets.needs")
local Bond = require("pawhome.pets.bond")
local Traits = require("pawhome.pets.traits")
local Training = require("pawhome.pets.training")
local Wants = require("pawhome.pets.wants")
local Keepsakes = require("pawhome.pets.keepsakes")
local Litter = require("pawhome.pets.litter")
local Util = require("pawhome.core.util")

local C = {}

local function fail(ctx, reason, params)
    return { ok = false, reason = reason, message = ctx.t("fail." .. reason, params) }
end

-- Why the cat would refuse this action right now (a full cat will not eat), or nil.
function C.refusal(pet, actionId)
    local def = actions[actionId]
    if type(def) ~= "table" then return nil end
    for need, limit in pairs(def.requiresBelow or {}) do
        if pet.needs[need] >= limit then return "not_hungry" end
    end
    for need, limit in pairs(def.requiresAbove or {}) do
        if pet.needs[need] < limit then return "too_tired" end
    end
    return nil
end

-- How worn out an action is: n recent uses (they wear off with time) and the gain multiplier.
function C.fatigue(ctx, pet, actionId)
    local f = careData.fatigue
    local r = pet.recent and pet.recent[actionId]
    if not r then return 0, 1 end
    local n = math.max(0, r.n - (ctx.now - r.t) / f.recoverMinutes)
    return n, math.max(f.min, 1 / (1 + f.perUse * n))
end

-- opts.fromGame: the care was given with the game's own interaction, which already
-- animated the cat; do not play ours on top (and tell the player with a notification).
function C.perform(ctx, petId, zoiId, actionId, opts)
    local fromGame = opts and opts.fromGame
    local pet = Registry.get(ctx, petId)
    if not pet or (pet.status ~= "home" and pet.status ~= "impounded") then return fail(ctx, "no_pet") end
    if pet.status ~= "home" then return fail(ctx, "not_home", { name = pet.name }) end
    local def = actions[actionId]
    if not def or type(def) ~= "table" or actionId == "order" then return fail(ctx, "unknown_action") end
    local refused = C.refusal(pet, actionId)
    if refused then return fail(ctx, refused, { name = pet.name }) end
    if def.scope == "household" and not Litter.present(ctx, pet.household) then
        return fail(ctx, "no_litter_box", { name = pet.name })
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

    local n, mul = C.fatigue(ctx, pet, actionId)
    local D = careData.delight
    local delight = Wants.fulfil(ctx, pet, actionId)
    if delight then mul = 1 end                       -- a want that was asked for is never worn out
    local gain = mul * (delight and D.needMul or 1)

    -- needs (household scope = everyone at home shares the litter box)
    local targets = { pet }
    if def.scope == "household" then targets = Registry.home(ctx, pet.household) end
    for _, target in ipairs(targets) do
        if def.needs then
            Needs.apply(target, def.needs, function() return Traits.keyed(target, "actionGain", actionId) * gain end)
        end
    end
    pet.recent = pet.recent or {}
    pet.recent[actionId] = { n = n + 1, t = ctx.now }

    local bond = def.bond or 0
    if bond > 0 then bond = bond * mul end
    if delight then bond = bond * D.bondMul + D.bondFlat end
    if bond ~= 0 then Bond.add(pet, zoiId, bond) end
    Training.addXp(ctx, pet, zoiId, (def.xp or 0) * (delight and D.xpMul or mul))

    if def.reveal or (def.peek and #Traits.unrevealed(pet) > 0) then
        local chance = Util.clamp((0.35 + Bond.get(pet, zoiId) / 150) * Traits.scalar(pet, "reveal"), 0.15, 0.95)
        if def.peek then chance = chance * def.peek end
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

    local animation = def.animation
    if delight then
        result.delight = true
        local gift = Keepsakes.roll(ctx, pet, Bond.level(Bond.get(pet, zoiId)))
        if gift then
            result.keepsake = gift
            result.message = ctx.t("msg.keepsake", { name = pet.name, item = gift.name })
            animation = "pet_happy"                   -- the cat hands over its gift
            if fromGame then ctx.emit(pet, "keepsake", { item = gift.name }) end
        else
            result.message = ctx.t("msg.delight", { name = pet.name })
            if fromGame then ctx.emit(pet, "delight") end
        end
    end
    if animation and not (fromGame and not (result.keepsake)) then Api.playAnimation(pet.entity, animation) end

    result.bond = Bond.get(pet, zoiId)
    result.bondLevel = Bond.level(result.bond)
    return result
end

return C
