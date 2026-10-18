-- Getting a pet: the animal shelter (daily offers, traits visible up front, like the
-- Sims 4 phone adoption) and adopting a stray cat (traits hidden until you get to know it).
local Api = require("pawhome.core.api")
local Registry = require("pawhome.pets.registry")
local Traits = require("pawhome.pets.traits")
local Bond = require("pawhome.pets.bond")
local Util = require("pawhome.core.util")
local names = require("pawhome.data.names")

local A = {}

local function fail(ctx, reason, params)
    return { ok = false, reason = reason, message = ctx.t("fail." .. reason, params) }
end

-- avoid: optional set of names already taken (name -> true)
function A.suggestName(ctx, avoid)
    local list = names[ctx.locale] or names["en"]
    local free = {}
    for _, n in ipairs(list) do
        if not (avoid and avoid[n]) then free[#free + 1] = n end
    end
    if #free == 0 then free = list end
    return ctx.rng:pick(free)
end

function A.cleanName(ctx, name)
    name = Util.trim(name)
    if name == "" then return A.suggestName(ctx) end
    local len = Util.charLength(name)
    if len < 1 or len > 24 then return nil end
    return name
end

local function newOffer(ctx, taken)
    local id = ctx.state.nextOfferId or 1
    ctx.state.nextOfferId = id + 1
    local stage = ctx.rng:weighted({ "kitten", "adult", "elder" }, function(s)
        return s == "elder" and 10 or 45
    end)
    return {
        id = id,
        name = A.suggestName(ctx, taken),
        stage = stage,
        traits = Traits.generate(ctx),
        appearanceSeed = ctx.rng:int(1, 999999),
        fee = ctx.cfg.shelterFee,
    }
end

-- Offers rotate once per game day per household.
function A.offers(ctx, householdId, forceNew)
    local key = tostring(householdId)
    local day = math.floor(ctx.now / Util.MINUTES_PER_DAY)
    local entry = ctx.state.offers[key]
    if forceNew or not entry or entry.day ~= day or #entry.list == 0 then
        entry = { day = day, list = {} }
        local taken = {}
        for _, pet in ipairs(Registry.list(ctx, householdId)) do taken[pet.name] = true end
        for _ = 1, ctx.cfg.shelterOfferCount do
            local offer = newOffer(ctx, taken)
            taken[offer.name] = true
            entry.list[#entry.list + 1] = offer
        end
        ctx.state.offers[key] = entry
    end
    return entry.list
end

local function limitReached(ctx, householdId)
    return Registry.count(ctx, householdId) >= ctx.cfg.maxPetsPerHousehold
end

local function finish(ctx, pet, zoiId, startBond)
    Bond.add(pet, zoiId, startBond)
    ctx.emit(pet, "adopted")
    return { ok = true, petId = pet.id, message = ctx.t("msg.adopted", { name = pet.name }) }
end

function A.adoptOffer(ctx, householdId, zoiId, offerId, name)
    if limitReached(ctx, householdId) then return fail(ctx, "max_pets", { limit = ctx.cfg.maxPetsPerHousehold }) end
    local entry = ctx.state.offers[tostring(householdId)]
    local offer, index
    for i, o in ipairs(entry and entry.list or {}) do
        if o.id == offerId then offer, index = o, i end
    end
    if not offer then return fail(ctx, "no_offer") end
    local petName = A.cleanName(ctx, name or offer.name)
    if not petName then return fail(ctx, "bad_name") end
    if Api.funds(householdId) < offer.fee then return fail(ctx, "no_funds", { fee = offer.fee }) end

    local entity
    if Api.caps().spawn then
        entity = Api.spawnPet(householdId, { appearanceSeed = offer.appearanceSeed, stage = offer.stage })
        if entity == nil then return fail(ctx, "spawn_failed") end
    end
    if not Api.charge(householdId, offer.fee) then
        Api.despawnPet(entity)
        return fail(ctx, "no_funds", { fee = offer.fee })
    end

    local revealed = {}
    for _, id in ipairs(offer.traits) do revealed[id] = true end
    local pet = Registry.create(ctx, {
        name = petName, household = householdId, stage = offer.stage, traits = offer.traits,
        revealed = revealed, entity = entity, appearance = offer.appearanceSeed,
    })
    table.remove(entry.list, index)
    return finish(ctx, pet, zoiId, 25)
end

function A.adoptStray(ctx, householdId, zoiId, strayId, name)
    if limitReached(ctx, householdId) then return fail(ctx, "max_pets", { limit = ctx.cfg.maxPetsPerHousehold }) end
    local stray
    for _, s in ipairs(Api.listStrays(householdId)) do
        if s.id == strayId then stray = s end
    end
    if not stray then return fail(ctx, "no_stray") end
    local petName = A.cleanName(ctx, name)
    if not petName then return fail(ctx, "bad_name") end
    local fee = ctx.cfg.strayFee
    if Api.funds(householdId) < fee then return fail(ctx, "no_funds", { fee = fee }) end

    local entity
    local caps = Api.caps()
    if caps.moveStray then
        entity = Api.bringStray(stray.ref, householdId)
    elseif caps.spawn then
        entity = Api.spawnPet(householdId, { appearance = stray.appearance, stage = stray.stage })
    end
    if (caps.moveStray or caps.spawn) and entity == nil then return fail(ctx, "spawn_failed") end
    if not Api.charge(householdId, fee) then
        Api.despawnPet(entity)
        return fail(ctx, "no_funds", { fee = fee })
    end

    local pet = Registry.create(ctx, {
        name = petName, household = householdId, stage = stray.stage or "adult",
        traits = Traits.generate(ctx), revealed = {}, entity = entity, appearance = stray.appearance,
    })
    return finish(ctx, pet, zoiId, 10)
end

function A.rename(ctx, petId, name)
    local pet = Registry.get(ctx, petId)
    if not pet then return fail(ctx, "no_pet") end
    local clean = A.cleanName(ctx, name)
    if not clean or Util.trim(name) == "" then return fail(ctx, "bad_name") end
    pet.name = clean
    return { ok = true, message = ctx.t("msg.renamed", { name = clean }) }
end

return A
