-- The simulation loop. The adapter calls Engine.tick(ctx, now) whenever the game
-- clock moves (about once per game hour is plenty). Time is integrated in chunks
-- so a long gap (loading a save, fast-forward) behaves the same as many short ticks.
local Api = require("pawhome.core.api")
local Registry = require("pawhome.pets.registry")
local Needs = require("pawhome.pets.needs")
local Aging = require("pawhome.pets.aging")
local Neglect = require("pawhome.pets.neglect")
local Shelter = require("pawhome.pets.shelter")
local Moods = require("pawhome.pets.moods")
local Bond = require("pawhome.pets.bond")
local Traits = require("pawhome.pets.traits")
local Util = require("pawhome.core.util")
local needsData = require("pawhome.data.needs")
local habits = require("pawhome.data.habits")
local moodData = require("pawhome.data.moods")
local stagesData = require("pawhome.data.stages")

local E = {}

local CHUNK = 60  -- minutes
-- These are always shown; everything else is rate-limited per pet.
local IMPORTANT = {
    adopted = true, grew_up = true, died = true, neglect_warning = true,
    impounded = true, redeemable = true, redeemed = true, rehomed = true, skill_up = true,
}

local function stageLabel(ctx, pet) return ctx.t("stages." .. pet.stage) end

local function die(ctx, pet)
    pet.status = "dead"
    pet.diedAt = ctx.now
    Api.despawnPet(pet.entity)
    pet.entity = nil
    ctx.emit(pet, "died")
    -- members who were close to the pet grieve
    for _, zoi in ipairs(Api.householdMembers(pet.household)) do
        if Bond.get(pet, zoi) >= 25 then Api.addBuff(zoi, "pawhome_grief", 720) end
    end
end

local function misbehave(ctx, pet, sleeping, minutes)
    if sleeping or not ctx.cfg.misbehaviorEnabled then return end
    local boredom = 1 + (100 - pet.needs.fun) / 100
    local kitten = pet.stage == "kitten" and 1.3 or 1
    for _, hid in ipairs(habits.order) do
        local p = habits[hid].chancePerHour * pet.habits[hid] * Traits.scalar(pet, "mischief")
            * boredom * kitten * (minutes / 60)
        if ctx.rng:chance(p) then
            pet.lastMisbehavior = { habit = hid, at = ctx.now }
            pet.needs.fun = Util.clamp(pet.needs.fun + habits[hid].funBoost, 0, 100)
            ctx.emit(pet, "misbehave_" .. hid)
            return
        end
    end
end

local function needAlerts(ctx, pet, sleeping)
    if sleeping then return end
    if pet.needs.hunger < needsData.hunger.low then ctx.emit(pet, "hungry") end
    if pet.needs.bladder < needsData.bladder.low then ctx.emit(pet, "litter") end
    if pet.needs.fun < needsData.fun.low then ctx.emit(pet, "bored") end
end

local function simulateChunk(ctx, pet, minutes)
    if pet.status == "impounded" then
        Shelter.step(ctx, pet)
        return
    end
    if pet.status ~= "home" then return end

    local sleeping = Needs.sleeping(pet, ctx.now)
    if Needs.step(ctx, pet, minutes, sleeping) then ctx.emit(pet, "accident") end

    local aged = Aging.step(ctx, pet, minutes)
    if aged == "died" then die(ctx, pet) return end
    if aged == "grew_up" then ctx.emit(pet, "grew_up", { stage = stageLabel(ctx, pet) }) end

    Neglect.step(ctx, pet, minutes)
    if pet.status ~= "home" then return end

    misbehave(ctx, pet, sleeping, minutes)
    needAlerts(ctx, pet, sleeping)
end

-- Keep the in-game cat in sync with the saved pet (plan A/B only).
local function ensurePresent(ctx, pet)
    if pet.status ~= "home" or not Api.caps().spawn then return end
    if pet.entity ~= nil and Api.entityExists(pet.entity) then return end
    pet.entity = Api.spawnPet(pet.household, { appearance = pet.appearance, stage = pet.stage })
end

-- Pets that are in a good or bad mood affect the Zoi who are bonded with them.
local function moodBuffs(ctx, pet)
    if pet.status ~= "home" or not Api.caps().buffs then return end
    local mood = Moods.compute(pet, Needs.sleeping(pet, ctx.now))
    local def = moodData[mood]
    if not def or not def.buff then return end
    local last = pet.notified["buff_" .. mood] or -math.huge
    if ctx.now - last < def.minutes / 2 then return end
    pet.notified["buff_" .. mood] = ctx.now
    for _, zoi in ipairs(Api.householdMembers(pet.household)) do
        if Bond.get(pet, zoi) >= def.minBond then Api.addBuff(zoi, def.buff, def.minutes) end
    end
end

-- Turns queued events into player-visible notifications.
function E.flush(ctx)
    local out = {}
    for _, ev in ipairs(ctx.events) do
        local pet = ev.pet
        local last = pet.notified[ev.kind]
        local limited = not IMPORTANT[ev.kind]
            and last ~= nil and ctx.now - last < ctx.cfg.notificationCooldownHours * 60
        if not limited then
            pet.notified[ev.kind] = ctx.now
            local params = { name = pet.name }
            for k, v in pairs(ev.params or {}) do params[k] = v end
            local text = ctx.t("msg." .. ev.kind, params)
            Api.notify(pet.household, ev.kind, text)
            out[#out + 1] = { petId = pet.id, kind = ev.kind, text = text }
        end
    end
    ctx.events = {}
    return out
end

function E.tick(ctx, now)
    ctx.now = now
    local last = ctx.state.lastTick
    ctx.state.lastTick = now
    if last == nil or now <= last then
        return {}
    end
    local remaining = math.min(now - last, ctx.cfg.catchupCapHours * 60)

    -- play the interval forward in chunks; the clock ctx.now follows
    local start = now - remaining
    local t = start
    while remaining > 0 do
        local dt = math.min(CHUNK, remaining)
        t = t + dt
        ctx.now = t
        for _, pet in ipairs(ctx.state.pets) do simulateChunk(ctx, pet, dt) end
        remaining = remaining - dt
    end
    ctx.now = now

    for _, pet in ipairs(ctx.state.pets) do
        ensurePresent(ctx, pet)
        moodBuffs(ctx, pet)
    end
    return E.flush(ctx)
end

E.stageLabel = stageLabel
E.stages = stagesData

return E
