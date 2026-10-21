-- Public face of the mod: builds the simulation context, exposes the calls the UI
-- and the game adapter use, and turns pet data into plain view tables for the UI.
local Api = require("pawhome.core.api")
local Storage = require("pawhome.core.storage")
local Serialize = require("pawhome.core.serialize")
local I18n = require("pawhome.core.i18n")
local Log = require("pawhome.core.log")
local Rng = require("pawhome.core.rng")
local Util = require("pawhome.core.util")
local Registry = require("pawhome.pets.registry")
local Enrichment = require("pawhome.pets.enrichment")
local Illness = require("pawhome.pets.illness")
local Wants = require("pawhome.pets.wants")
local Litter = require("pawhome.pets.litter")
local Bowl = require("pawhome.pets.bowl")
local bowlData = require("pawhome.data.bowl")
local Keepsakes = require("pawhome.pets.keepsakes")
local enrichmentData = require("pawhome.data.enrichment")
local litterData = require("pawhome.data.litter")
local Engine = require("pawhome.pets.engine")
local Care = require("pawhome.pets.care")
local Adoption = require("pawhome.pets.adoption")
local Coats = require("pawhome.pets.coats")
local Shelter = require("pawhome.pets.shelter")
local Needs = require("pawhome.pets.needs")
local Moods = require("pawhome.pets.moods")
local Bond = require("pawhome.pets.bond")
local Aging = require("pawhome.pets.aging")
local Training = require("pawhome.pets.training")
local needsData = require("pawhome.data.needs")
local actions = require("pawhome.data.actions")
local traitData = require("pawhome.data.traits")
local defaults = require("pawhome.data.settings")

local App = {}
App.__index = App

local function applyLocale(ctx)
    local lang = ctx.cfg.language
    if lang == "auto" then lang = Api.locale() end
    ctx.locale = I18n.setLocale(lang)
end

function App.new(adapter, opts)
    local ok, err = Api.use(adapter)
    if not ok then return nil, err end

    local state, how = Storage.load()
    if not state then return nil, how end

    local ctx = {
        state = state,
        cfg = state.settings,
        rng = Rng.new(state.rng or (opts and opts.seed)),
        now = Api.now() or 0,
        events = {},
        t = I18n.t,
    }
    ctx.emit = function(pet, kind, params)
        ctx.events[#ctx.events + 1] = { pet = pet, kind = kind, params = params }
    end
    applyLocale(ctx)
    if ctx.cfg.debug then Log.setLevel("debug") end
    local slotAware = Api.hasSlots()
    local slot = slotAware and Api.slotId() or nil
    local app = setmetatable({
        ctx = ctx, slotAware = slotAware, slot = slot, seed = opts and opts.seed,
        -- a slot-aware adapter with no save loaded (loading screen / main menu): stay paused
        suspended = slotAware and slot == nil,
    }, App)
    if app.suspended then
        Log.info("no savegame is loaded yet; the mod is paused")
    else
        Log.info("started (" .. how .. "), " .. #state.pets .. " pets")
        Coats.publish(ctx)
    end
    -- react at once when the game says the save changed; polling in sync() is the fallback
    Api.subscribe("slot_changed", function() app:syncSlot() end)
    return app
end

-- The adapter keeps one data file per savegame slot. If the player loaded another save,
-- the state in memory belongs to the OLD slot, so it must be replaced - and must never be
-- written, because the adapter would now put it into the NEW slot. (Every public call ends
-- with a save, so nothing is lost by not saving here.)
--
-- The game runs Lua on one thread and a public call never yields, so the slot cannot change
-- between the sync at the start of a call and the save at its end.
-- Reads the savegame data again (after a slot change or a restored backup).
function App:reload()
    local state, how = Storage.load()
    if not state then
        Log.error("cannot load the slot (" .. tostring(how) .. "); the mod is paused for it")
        self.suspended = true
        return false
    end
    local ctx = self.ctx
    ctx.state, ctx.cfg = state, state.settings
    ctx.rng = Rng.new(state.rng or self.seed)   -- never carry the previous save's random state over
    ctx.events = {}
    applyLocale(ctx)
    self.suspended = false
    -- show the pets' size and mood right away, not only after the first game hour
    ctx.now = Api.now() or ctx.now
    if ctx.now then Engine.looks(ctx) end
    Coats.publish(ctx)
    return true
end

function App:syncSlot()
    if not self.slotAware then return false end
    local slot = Api.slotId()
    if slot == self.slot then return false end
    Log.info("savegame slot changed: " .. tostring(self.slot) .. " -> " .. tostring(slot))
    self.slot = slot
    if slot == nil then
        -- no save loaded (loading screen): nothing may be read or written until one is
        self.suspended = true
        return true
    end
    -- a slot written by a newer version stays paused until the slot changes again
    self:reload()
    return true
end

function App:save()
    if self.suspended or (self.slotAware and Api.slotId() ~= self.slot) then return false end
    self.ctx.state.rng = self.ctx.rng:getState()
    return Storage.save(self.ctx.state)
end

-- Call about once per game hour (or whenever the clock jumps).
function App:tick()
    self:syncSlot()
    if self.suspended then return {} end
    local now = Api.now()
    if now == nil then return {} end
    local notes = Engine.tick(self.ctx, now)
    Coats.publish(self.ctx)
    self:save()
    return notes
end

function App:sync()
    self:syncSlot()
    self.ctx.now = Api.now() or self.ctx.now
end

-- Result for calls made while no savegame is loaded.
function App:noSave()
    return { ok = false, reason = "no_save", message = I18n.t("fail.no_save"), notifications = {} }
end

function App:perform(petId, zoiId, actionId)
    self:sync()
    if self.suspended then return self:noSave() end
    local result = Care.perform(self.ctx, petId, zoiId, actionId)
    Engine.looks(self.ctx)
    local notes = Engine.flush(self.ctx)
    result.notifications = notes
    self:save()
    return result
end

-- Applies care given through the game's own interactions on our cats. Cooldowns and
-- conditions still apply: feeding a full cat again gives nothing. Returns the results.
function App:applyCare()
    self:sync()
    if self.suspended then return {} end
    local results = {}
    for _, pet in ipairs(Registry.home(self.ctx, nil)) do
        for _, ev in ipairs(Api.takeCare(pet.entity)) do
            local r = Care.perform(self.ctx, pet.id, ev.zoi, ev.kind, { fromGame = true })
            r.source = "game"
            r.action = r.action or ev.kind
            results[#results + 1] = r
        end
    end
    if #results > 0 then
        Engine.looks(self.ctx)
        Engine.flush(self.ctx)
        self:save()
    end
    return results
end

function App:offers(householdId, refresh)
    self:sync()
    if self.suspended then return {} end
    local list = Adoption.offers(self.ctx, householdId, refresh)
    local out = {}
    for _, o in ipairs(list) do
        local traits = {}
        for _, id in ipairs(o.traits) do
            traits[#traits + 1] = { id = id, label = I18n.t("traits." .. id .. ".name"), desc = I18n.t("traits." .. id .. ".desc") }
        end
        out[#out + 1] = {
            id = o.id, name = o.name, fee = o.fee, stage = o.stage,
            stageLabel = I18n.t("stages." .. o.stage), traits = traits,
            coat = o.coat, coatLabel = o.coat and I18n.t("coats." .. o.coat) or "",
            coats = Coats.choices(self.ctx),     -- the player may pick another one
        }
    end
    self:save()
    return out
end

function App:strays(householdId)
    self:sync()
    if self.suspended then return {} end
    return Api.listStrays(householdId)
end

function App:placeLitterBox(householdId)
    self:sync()
    if self.suspended then return self:noSave() end
    if not Api.placeLitterBox(householdId) then
        return { ok = false, reason = "not_home", message = I18n.t("fail.place_litter_failed"), notifications = {} }
    end
    Litter.forget(self.ctx)
    return { ok = true, message = I18n.t("msg.litter_placed"), notifications = {} }
end

-- The box's own menu: "Add cat litter". Nothing is used up; the box is full again.
function App:refillLitter(householdId, zoiId)
    self:sync()
    if self.suspended then return self:noSave() end
    Litter.forget(self.ctx)
    if not Litter.present(self.ctx, householdId) then
        return { ok = false, reason = "no_litter_box", message = I18n.t("fail.no_litter_box"), notifications = {} }
    end
    local state = Litter.boxState(self.ctx, householdId)
    if state == "clean" then
        return { ok = false, reason = "litter_full", message = I18n.t("fail.litter_full"), notifications = {} }
    end
    Litter.refill(self.ctx, householdId)
    self:autoLitter(zoiId)
    self:save()
    return { ok = true, message = I18n.t("msg.litter_refilled"), notifications = {} }
end

-- The box's own menu: "Clean litter box". A dirty box is cleaned (one use of the fill is spent).
function App:cleanLitterBox(householdId, zoiId)
    self:sync()
    if self.suspended then return self:noSave() end
    Litter.forget(self.ctx)
    if not Litter.present(self.ctx, householdId) then
        return { ok = false, reason = "no_litter_box", message = I18n.t("fail.no_litter_box"), notifications = {} }
    end
    local state = Litter.boxState(self.ctx, householdId)
    if state == "empty" then
        return { ok = false, reason = "litter_empty_box", message = I18n.t("fail.litter_box_empty"), notifications = {} }
    end
    if state ~= "dirty" then
        return { ok = false, reason = "litter_not_dirty", message = I18n.t("fail.litter_not_dirty"), notifications = {} }
    end
    local pets = Registry.home(self.ctx, householdId)
    if #pets > 0 then
        local r = Care.perform(self.ctx, pets[1].id, zoiId, "clean_litter", { fromGame = true })
        if not r.ok then return r end
    else
        Litter.clean(self.ctx, householdId)
    end
    Engine.looks(self.ctx)
    Engine.flush(self.ctx)
    self:save()
    local after = Litter.boxState(self.ctx, householdId)
    return { ok = true, message = I18n.t(after == "empty" and "msg.litter_cleaned_empty" or "msg.litter_cleaned"), notifications = {} }
end

-- The bowl's own menu: "Fill the food bowl".
function App:fillBowl(householdId)
    self:sync()
    if self.suspended then return self:noSave() end
    Bowl.forget(self.ctx)
    if not Bowl.present(self.ctx, householdId) then
        return { ok = false, reason = "no_bowl", message = I18n.t("fail.no_bowl"), notifications = {} }
    end
    if Bowl.meals(self.ctx, householdId) >= bowlData.meals then
        return { ok = false, reason = "bowl_full", message = I18n.t("fail.bowl_full"), notifications = {} }
    end
    Bowl.fill(self.ctx, householdId)
    self:save()
    return { ok = true, message = I18n.t("msg.bowl_filled", { meals = bowlData.meals }), notifications = {} }
end

-- A cat eats from the bowl: it is put in front of the bowl, eats (the game's eat clip) and is fed like
-- the game's own feeding. `petId` nil = the hungriest cat of the household at home.
function App:feedFromBowl(householdId, zoiId, petId)
    self:sync()
    if self.suspended then return self:noSave() end
    Bowl.forget(self.ctx)
    if not Bowl.present(self.ctx, householdId) then
        return { ok = false, reason = "no_bowl", message = I18n.t("fail.no_bowl"), notifications = {} }
    end
    if Bowl.meals(self.ctx, householdId) <= 0 then
        return { ok = false, reason = "bowl_empty", message = I18n.t("fail.bowl_empty"), notifications = {} }
    end
    local pet
    if petId then pet = Registry.get(self.ctx, petId) end
    if not pet then
        for _, p in ipairs(Registry.home(self.ctx, householdId)) do
            if not pet or p.needs.hunger < pet.needs.hunger then pet = p end
        end
    end
    if not pet or pet.status ~= "home" then
        return { ok = false, reason = "no_pet", message = I18n.t("fail.no_pet"), notifications = {} }
    end
    local zoi = zoiId or (Api.householdMembers(householdId)[1]) or 0
    -- the cat comes to the bowl first (Care plays its eat clip where the cat is), unless it would not eat
    if not Care.refusal(pet, "feed") then Api.movePetToObject(pet.entity, bowlData.object, bowlData.frontCm) end
    local r = Care.perform(self.ctx, pet.id, zoi, "feed")
    if not r.ok then return r end
    pet.bowlAt = self.ctx.now
    Bowl.take(self.ctx, householdId)
    Engine.looks(self.ctx)
    Engine.flush(self.ctx)
    self:save()
    r.message = I18n.t("msg.bowl_ate", { name = pet.name, meals = Bowl.meals(self.ctx, householdId) })
    return r
end

-- A hungry cat goes to a filled bowl by itself (once per autoGapMinutes).
function App:autoBowl(zoiId)
    self:sync()
    if self.suspended then return {} end
    Bowl.forget(self.ctx)
    local results = {}
    for _, pet in ipairs(Registry.home(self.ctx, nil)) do
        local due = pet.bowlAt == nil or (self.ctx.now - pet.bowlAt) >= bowlData.autoGapMinutes
        if due and pet.needs.hunger <= bowlData.autoBelow and Bowl.present(self.ctx, pet.household)
            and Bowl.meals(self.ctx, pet.household) > 0 then
            local r = self:feedFromBowl(pet.household, zoiId, pet.id)
            if r.ok then results[#results + 1] = r end
        end
    end
    return results
end

function App:useLitter(petId, zoiId)
    self:sync()
    if self.suspended then return self:noSave() end
    Litter.forget(self.ctx)
    local pet = Registry.get(self.ctx, petId)
    if not pet or (pet.status ~= "home" and pet.status ~= "impounded") then
        return { ok = false, reason = "no_pet", message = I18n.t("fail.no_pet"), notifications = {} }
    end
    if pet.status ~= "home" then
        return { ok = false, reason = "not_home", message = I18n.t("fail.not_home", { name = pet.name }), notifications = {} }
    end
    if not Litter.present(self.ctx, pet.household) then
        return { ok = false, reason = "no_litter_box", message = I18n.t("fail.no_litter_box"), notifications = {} }
    end
    local boxState = Litter.boxState(self.ctx, pet.household)
    if boxState == "empty" then
        return { ok = false, reason = "litter_empty", message = I18n.t("fail.litter_empty", { name = pet.name }), notifications = {} }
    end
    if boxState == "dirty" then
        return { ok = false, reason = "litter_dirty", message = I18n.t("fail.litter_dirty", { name = pet.name }), notifications = {} }
    end
    Api.movePetToObject(pet.entity, litterData.object)
    Api.playAnimation(pet.entity, "pet_litter")
    pet.needs.bladder = 100
    Litter.markUsed(self.ctx, pet.household)
    Engine.looks(self.ctx)
    self:save()
    return { ok = true, petId = pet.id, message = I18n.t("msg.litter_used", { name = pet.name }), notifications = {} }
end

function App:callPet(petId, zoiId)
    self:sync()
    if self.suspended then return self:noSave() end
    local pet = Registry.get(self.ctx, petId)
    if not pet or (pet.status ~= "home" and pet.status ~= "impounded") then
        return { ok = false, reason = "no_pet", message = I18n.t("fail.no_pet"), notifications = {} }
    end
    if pet.status ~= "home" then
        return { ok = false, reason = "not_home", message = I18n.t("fail.not_home", { name = pet.name }), notifications = {} }
    end
    if not Api.movePetToZoi(pet.entity, zoiId) then
        return { ok = false, reason = "call_failed", message = I18n.t("fail.call_failed", { name = pet.name }), notifications = {} }
    end
    Api.playAnimation(pet.entity, "pet_play")
    Engine.looks(self.ctx)
    self:save()
    return { ok = true, petId = pet.id, message = I18n.t("msg.pet_called", { name = pet.name }), notifications = {} }
end

function App:autoLitter(zoiId)
    self:sync()
    if self.suspended then return {} end
    Litter.forget(self.ctx)
    local results = {}
    for _, pet in ipairs(Registry.home(self.ctx, nil)) do
        if pet.needs.bladder <= needsData.bladder.low and Litter.present(self.ctx, pet.household) then
            local boxState = Litter.boxState(self.ctx, pet.household)
            if boxState == "clean" then
                local zoi = zoiId or (Api.householdMembers(pet.household)[1]) or 0
                local r = self:useLitter(pet.id, zoi)
                if r.ok then results[#results + 1] = r end
            end
        end
    end
    if #results > 0 then
        Engine.looks(self.ctx)
        Engine.flush(self.ctx)
        self:save()
    end
    return results
end

local function finishAdoption(self, result)
    result.notifications = Engine.flush(self.ctx)
    Engine.looks(self.ctx)
    Coats.publish(self.ctx)
    self:save()
    return result
end

-- coat (optional): data/coats.lua id the player picked; an offer keeps its own when omitted.
function App:adoptOffer(householdId, zoiId, offerId, name, coat)
    self:sync()
    if self.suspended then return self:noSave() end
    return finishAdoption(self, Adoption.adoptOffer(self.ctx, householdId, zoiId, offerId, name, coat))
end

function App:adoptStray(householdId, zoiId, strayId, name, coat)
    self:sync()
    if self.suspended then return self:noSave() end
    return finishAdoption(self, Adoption.adoptStray(self.ctx, householdId, zoiId, strayId, name, coat))
end

-- Coats the player can choose from at adoption: { { id, label }, ... }
function App:coats()
    return Coats.choices(self.ctx)
end

function App:redeem(householdId, zoiId, petId)
    self:sync()
    if self.suspended then return self:noSave() end
    local result = Shelter.redeem(self.ctx, householdId, zoiId, petId)
    result.notifications = Engine.flush(self.ctx)
    Engine.looks(self.ctx)
    Coats.publish(self.ctx)
    self:save()
    return result
end

function App:vet(householdId, zoiId, petId)
    self:sync()
    if self.suspended then return self:noSave() end
    local result = Illness.vet(self.ctx, householdId, petId)
    result.notifications = Engine.flush(self.ctx)
    Engine.looks(self.ctx)
    self:save()
    return result
end

function App:rename(petId, name)
    self:sync()
    if self.suspended then return self:noSave() end
    local r = Adoption.rename(self.ctx, petId, name)
    self:save()
    return r
end

local SETTING_RANGES = {
    lifeScale = { 0.5, 4 }, needDecayScale = { 0.25, 2 }, maxPetsPerHousehold = { 1, 4 }, redeemFee = { 0, 5000 },
}

function App:setSetting(key, value)
    self:sync()
    if self.suspended then return false, "no_save" end
    local cfg = self.ctx.cfg
    if defaults[key] == nil then return false, "unknown setting" end
    if type(value) ~= type(defaults[key]) then return false, "wrong type" end
    local range = SETTING_RANGES[key]
    if range then value = Util.clamp(value, range[1], range[2]) end
    if key == "language" and value ~= "auto" and value ~= "en" and value ~= "zh-TW" then
        return false, "unsupported language"
    end
    cfg[key] = value
    if key == "language" then applyLocale(self.ctx) end
    self:save()
    return true
end

---------------------------------------------------------------- view models

local function petView(ctx, pet, zoiId)
    local sleeping = pet.status == "home" and Needs.sleeping(pet, ctx.now)
    local mood = pet.status == "home" and Moods.compute(pet, sleeping) or "sad"
    local needs = {}
    local hasBox = Litter.present(ctx, pet.household)
    local hasBag = Litter.bagPresent(ctx, pet.household)
    local boxState, boxUses = Litter.boxState(ctx, pet.household)
    for _, id in ipairs(needsData.order) do
      if id ~= "bladder" or hasBox then
        needs[#needs + 1] = {
            id = id, label = I18n.t("needs." .. id),
            value = math.floor(pet.needs[id] + 0.5), state = Needs.state(id, pet.needs[id]),
        }
      end
    end
    local traits = {}
    for _, id in ipairs(pet.traits) do
        local known = pet.revealed[id] == true
        traits[#traits + 1] = {
            id = id, known = known,
            label = known and I18n.t("traits." .. id .. ".name") or I18n.t("ui.unknown_trait"),
            desc = known and I18n.t("traits." .. id .. ".desc") or "",
        }
    end
    local bond = zoiId and Bond.get(pet, zoiId) or Bond.best(pet)
    local acts = {}
    local want = Wants.view(ctx, pet)
    for _, id in ipairs(actions.order) do
        local refusal = pet.status == "home" and Care.refusal(pet, id) or nil
        acts[#acts + 1] = {
            id = id, label = I18n.t("actions." .. id .. ".name"),
            desc = I18n.t("actions." .. id .. ".desc"),
            ready = pet.status == "home" and refusal == nil,
            hint = refusal and I18n.t("hint." .. refusal) or "",       -- "Full" / "Tired" under the button
            wanted = want ~= nil and want.id == id and refusal == nil,  -- the cat is asking for this one
        }
    end
    return {
        id = pet.id, name = pet.name, status = pet.status,
        statusLabel = pet.status == "impounded" and I18n.t("ui.impounded") or "",
        redeem = pet.status == "impounded" and Shelter.info(ctx, pet) or nil,
        stage = pet.stage, stageLabel = I18n.t("stages." .. pet.stage),
        coat = pet.coat, coatLabel = pet.coat and I18n.t("coats." .. pet.coat) or "",
        ageDays = Aging.ageDays(pet), ageLabel = I18n.t("ui.age", { days = Aging.ageDays(pet) }),
        mood = mood, moodLabel = I18n.t("moods." .. mood),
        needs = needs, traits = traits,
        bond = math.floor(bond + 0.5), bondLevel = Bond.level(bond), bondLabel = I18n.t("bond." .. Bond.level(bond)),
        actions = acts,
        illness = Illness.view(ctx, pet),
        want = want,
        litterBox = hasBox,
        bowl = { present = Bowl.present(ctx, pet.household), meals = Bowl.meals(ctx, pet.household), max = bowlData.meals,
                 label = I18n.t("ui.bowl_meals", { meals = Bowl.meals(ctx, pet.household), max = bowlData.meals }) },
        litterStatus = {
            present = hasBox,
            bagPresent = hasBag,
            state = boxState,
            uses = boxUses,
            stateLabel = I18n.t("ui.litter_state_" .. boxState),
        },
    }
end

-- A backup worth offering: only while this savegame has no pets and the backup has some.
function App:backupInfo()
    if self.suspended or #self.ctx.state.pets > 0 then return nil end
    local b = Api.backup()
    local raw = b and type(b.cache) == "table" and b.cache[Storage.KEY]
    local old = raw and Serialize.decode(raw)
    if type(old) ~= "table" or type(old.pets) ~= "table" then return nil end
    local names = {}
    for _, pet in ipairs(old.pets) do
        if pet.status == "home" or pet.status == "impounded" then names[#names + 1] = tostring(pet.name) end
    end
    if #names == 0 then return nil end
    local day = tonumber(b.day) or 0
    local list = table.concat(names, ", ")
    return { day = day, names = names, text = I18n.t("ui.backup_found", { day = day, names = list }) }
end

function App:restoreBackup()
    self:sync()
    if self.suspended then return self:noSave() end
    if not self:backupInfo() or not Api.restoreBackup() then
        return { ok = false, reason = "no_backup", message = I18n.t("fail.no_backup") }
    end
    self:reload()
    return { ok = true, message = I18n.t("msg.backup_restored"), notifications = {} }
end

-- Cat furniture on the lot and what each piece does, for the panel.
local function furnitureView(householdId)
    local out = {}
    for _, id in ipairs(Enrichment.pieces(householdId)) do
        local effects = {}
        for _, need in ipairs(needsData.order) do
            local r = enrichmentData.items[id][need]
            if r then
                effects[#effects + 1] = I18n.t("furniture.effect",
                    { need = I18n.t("needs." .. need), pct = math.floor(r * 100 + 0.5) })
            end
        end
        out[#out + 1] = { id = id, name = I18n.t("furniture." .. id), effects = effects }
    end
    return out
end

function App:view(householdId, zoiId)
    self:sync()
    local ctx = self.ctx
    Litter.forget(ctx)
    local pets = {}
    if not self.suspended then
        for _, pet in ipairs(Registry.list(ctx, householdId)) do
            pets[#pets + 1] = petView(ctx, pet, zoiId)
        end
    end
    local level = (zoiId and not self.suspended) and Training.level(ctx, zoiId) or 0
    -- UI strings travel with the view so the HTML never needs its own translations
    local ui = {}
    for _, key in ipairs(I18n.keys(ctx.locale)) do
        local short = key:match("^ui%.(.+)$")
        if short then ui[short] = I18n.t(key) end
    end
    return {
        ui = ui,
        locale = ctx.locale,
        title = I18n.t("ui.title"),
        pets = pets,
        noSave = self.suspended,
        training = { level = level, label = I18n.t("ui.training", { level = level }) },
        furniture = (householdId ~= nil and not self.suspended) and furnitureView(householdId) or {},
        backup = self:backupInfo(),
        album = Keepsakes.view(ctx, householdId),
        settings = Util.copy(ctx.cfg),
    }
end

return App
