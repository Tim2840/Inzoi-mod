-- Pet Training skill of the Zoi and behaviour shaping (praise / scold).
local data = require("pawhome.data.training")
local habits = require("pawhome.data.habits")
local Traits = require("pawhome.pets.traits")
local Util = require("pawhome.core.util")

local T = {}

local function record(ctx, zoiId)
    local key = tostring(zoiId)
    ctx.state.zoi[key] = ctx.state.zoi[key] or { petTraining = 0 }
    return ctx.state.zoi[key]
end

function T.xp(ctx, zoiId)
    return record(ctx, zoiId).petTraining
end

function T.level(ctx, zoiId)
    local xp, level = T.xp(ctx, zoiId), 0
    for i, need in ipairs(data.thresholds) do
        if xp >= need then level = i end
    end
    return level
end

function T.addXp(ctx, pet, zoiId, amount)
    if amount <= 0 then return false end
    local before = T.level(ctx, zoiId)
    record(ctx, zoiId).petTraining = record(ctx, zoiId).petTraining + amount * Traits.scalar(pet, "trainingXp")
    local after = T.level(ctx, zoiId)
    if after > before then
        ctx.emit(pet, "skill_up", { level = after })
        return true
    end
    return false
end

local function step(ctx, zoiId)
    return habits.shapeStep * (1 + T.level(ctx, zoiId) * data.shapeBonusPerLevel)
end

-- Scolding only works right after the pet misbehaved; returns true when it landed.
function T.scold(ctx, pet, zoiId)
    local last = pet.lastMisbehavior
    if not last or ctx.now - last.at > 90 then return false end
    local resist = Traits.scalar(pet, "scoldResist")
    pet.habits[last.habit] = Util.clamp(pet.habits[last.habit] - step(ctx, zoiId) * resist, 0.05, 0.95)
    pet.lastMisbehavior = nil
    return resist >= 0.5
end

-- Praise nudges every bad habit down a little.
function T.praise(ctx, pet, zoiId)
    local s = step(ctx, zoiId) * 0.35
    for _, hid in ipairs(habits.order) do
        pet.habits[hid] = Util.clamp(pet.habits[hid] - s, 0.05, 0.95)
    end
end

return T
