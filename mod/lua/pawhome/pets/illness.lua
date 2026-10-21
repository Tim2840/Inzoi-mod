-- Falling ill, getting better, and the vet.
local data = require("pawhome.data.illness")
local needsData = require("pawhome.data.needs")
local Api = require("pawhome.core.api")
local Registry = require("pawhome.pets.registry")
local Needs = require("pawhome.pets.needs")
local Util = require("pawhome.core.util")

local I = {}

local function fail(ctx, reason, params)
    return { ok = false, reason = reason, message = ctx.t("fail." .. reason, params) }
end

local function conditionHolds(pet, when)
    if when.always then return true end
    for need, level in pairs(when.below or {}) do
        if pet.needs[need] >= needsData[need][level] then return false end
    end
    return true
end

function I.decayMul(pet, need)
    local ill = pet.illness and data[pet.illness.id]
    return (ill and ill.decayMul[need]) or 1
end

-- One simulation step for a pet at home.
function I.step(ctx, pet, minutes)
    if not ctx.cfg.illnessEnabled then return end
    local hours = minutes / 60
    if pet.illness then
        local def = data[pet.illness.id]
        if def and def.recoverHours and Needs.average(pet) >= data.goodCareAverage then
            pet.illness.goodHours = (pet.illness.goodHours or 0) + hours
            if pet.illness.goodHours >= def.recoverHours then
                pet.illness = nil
                ctx.emit(pet, "recovered")
            end
        end
        return
    end
    local stageMul = data.stageChanceMul[pet.stage] or 1
    for _, id in ipairs(data.order) do
        local def = data[id]
        if conditionHolds(pet, def.when) then
            local p = 1 - (1 - def.chancePerHour * stageMul) ^ hours
            if ctx.rng:chance(p) then
                pet.illness = { id = id, since = ctx.now, goodHours = 0 }
                ctx.emit(pet, "fell_ill", { illness = ctx.t("illness." .. id .. ".name") })
                return
            end
        end
    end
end

-- The vet cures any illness for settings.vetFee.
function I.vet(ctx, householdId, petId)
    local pet = Registry.get(ctx, petId)
    if not pet or pet.household ~= householdId then return fail(ctx, "no_pet") end
    if pet.status ~= "home" then return fail(ctx, "not_home", { name = pet.name }) end
    if not pet.illness then return fail(ctx, "not_sick", { name = pet.name }) end
    local fee = ctx.cfg.vetFee
    if Api.funds(householdId) < fee or not Api.charge(householdId, fee) then
        return fail(ctx, "no_funds", { fee = fee })
    end
    pet.illness = nil
    for need, v in pairs(data.vetNeeds) do pet.needs[need] = Util.clamp(pet.needs[need] + v, 0, 100) end
    ctx.emit(pet, "vet_cured")
    return { ok = true, petId = pet.id, fee = fee, message = ctx.t("msg.vet_cured", { name = pet.name }) }
end

-- For the panel: nil when healthy.
function I.view(ctx, pet)
    if not pet.illness then return nil end
    local id = pet.illness.id
    return {
        id = id,
        name = ctx.t("illness." .. id .. ".name"),
        desc = ctx.t("illness." .. id .. ".desc"),
        vetOnly = data[id] and data[id].recoverHours == nil or false,
        vetFee = ctx.cfg.vetFee,
    }
end

return I
