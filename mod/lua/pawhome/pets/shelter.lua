-- Pets that animal control took away: waiting period, redeeming for a fee, and
-- being rehomed if nobody comes.
local Api = require("pawhome.core.api")
local Registry = require("pawhome.pets.registry")
local Util = require("pawhome.core.util")
local data = require("pawhome.data.neglect")

local S = {}

local function fail(ctx, reason, params)
    return { ok = false, reason = reason, message = ctx.t("fail." .. reason, params) }
end

-- Minutes until the pet can be redeemed (0 = now).
function S.waitMinutes(ctx, pet)
    local readyAt = (pet.impoundedAt or ctx.now) + data.redeemWaitHours * 60
    return math.max(0, math.ceil(readyAt - ctx.now))
end

function S.daysLeft(ctx, pet)
    local endsAt = (pet.impoundedAt or ctx.now) + data.holdDays * Util.MINUTES_PER_DAY
    return math.max(0, math.ceil((endsAt - ctx.now) / Util.MINUTES_PER_DAY))
end

function S.info(ctx, pet)
    local wait = S.waitMinutes(ctx, pet)
    return {
        fee = ctx.cfg.redeemFee, waitMinutes = wait, waitHours = math.ceil(wait / 60),
        daysLeft = S.daysLeft(ctx, pet), ready = wait == 0,
    }
end

-- Called every simulation chunk for an impounded pet.
function S.step(ctx, pet)
    local days = (ctx.now - (pet.impoundedAt or ctx.now)) / Util.MINUTES_PER_DAY
    if days >= data.holdDays then
        pet.status = "lost"
        ctx.emit(pet, "rehomed")
        return
    end
    if S.waitMinutes(ctx, pet) == 0 and not pet.flags.redeemable then
        pet.flags.redeemable = true
        ctx.emit(pet, "redeemable")
    end
end

function S.redeem(ctx, householdId, zoiId, petId)
    local pet = Registry.get(ctx, petId)
    if not pet or pet.household ~= householdId then return fail(ctx, "no_pet") end
    if pet.status ~= "impounded" then return fail(ctx, "not_impounded", { name = pet.name }) end
    local wait = S.waitMinutes(ctx, pet)
    if wait > 0 then return fail(ctx, "redeem_wait", { name = pet.name, hours = math.ceil(wait / 60) }) end

    local fee = ctx.cfg.redeemFee
    if Api.funds(householdId) < fee then return fail(ctx, "no_funds", { fee = fee }) end

    local entity
    if Api.caps().spawn then
        entity = Api.spawnPet(householdId, { appearance = pet.appearance, stage = pet.stage })
        if entity == nil then return fail(ctx, "spawn_failed") end
    end
    if not Api.charge(householdId, fee) then
        Api.despawnPet(entity)
        return fail(ctx, "no_funds", { fee = fee })
    end

    pet.status = "home"
    pet.impoundedAt = nil
    pet.entity = entity
    pet.neglect = 0
    pet.flags.warned = nil
    pet.flags.redeemable = nil
    for id, v in pairs(data.redeemNeeds) do pet.needs[id] = v end
    -- the pet is wary: part of the bond is lost
    for k, v in pairs(pet.bond) do pet.bond[k] = v * data.redeemBondKeep end

    ctx.emit(pet, "redeemed")
    return { ok = true, petId = pet.id, message = ctx.t("msg.redeemed", { name = pet.name }) }
end

return S
