-- Public face of the mod: builds the simulation context, exposes the calls the UI
-- and the game adapter use, and turns pet data into plain view tables for the UI.
local Api = require("pawhome.core.api")
local Storage = require("pawhome.core.storage")
local I18n = require("pawhome.core.i18n")
local Log = require("pawhome.core.log")
local Rng = require("pawhome.core.rng")
local Util = require("pawhome.core.util")
local Registry = require("pawhome.pets.registry")
local Engine = require("pawhome.pets.engine")
local Care = require("pawhome.pets.care")
local Adoption = require("pawhome.pets.adoption")
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
    Log.info("started (" .. how .. "), " .. #state.pets .. " pets")
    local slotAware = Api.hasSlots()
    local slot = slotAware and Api.slotId() or nil
    local app = setmetatable({
        ctx = ctx, slotAware = slotAware, slot = slot, seed = opts and opts.seed,
        -- a slot-aware adapter with no save loaded (loading screen / main menu): stay paused
        suspended = slotAware and slot == nil,
    }, App)
    if app.suspended then Log.info("no savegame is loaded yet; the mod is paused") end
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
    local state, how = Storage.load()
    if not state then
        -- e.g. the new slot was written by a newer version: touch nothing until the slot changes again
        Log.error("cannot load the new slot (" .. tostring(how) .. "); the mod is paused for it")
        self.suspended = true
        return true
    end
    local ctx = self.ctx
    ctx.state, ctx.cfg = state, state.settings
    ctx.rng = Rng.new(state.rng or self.seed)   -- never carry the previous save's random state over
    ctx.events = {}
    applyLocale(ctx)
    self.suspended = false
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
    local notes = Engine.flush(self.ctx)
    result.notifications = notes
    self:save()
    return result
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

local function finishAdoption(self, result)
    result.notifications = Engine.flush(self.ctx)
    self:save()
    return result
end

function App:adoptOffer(householdId, zoiId, offerId, name)
    self:sync()
    if self.suspended then return self:noSave() end
    return finishAdoption(self, Adoption.adoptOffer(self.ctx, householdId, zoiId, offerId, name))
end

function App:adoptStray(householdId, zoiId, strayId, name)
    self:sync()
    if self.suspended then return self:noSave() end
    return finishAdoption(self, Adoption.adoptStray(self.ctx, householdId, zoiId, strayId, name))
end

function App:redeem(householdId, zoiId, petId)
    self:sync()
    if self.suspended then return self:noSave() end
    local result = Shelter.redeem(self.ctx, householdId, zoiId, petId)
    result.notifications = Engine.flush(self.ctx)
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
    lifeScale = { 0.5, 4 }, needDecayScale = { 0.25, 2 }, maxPetsPerHousehold = { 1, 8 }, redeemFee = { 0, 5000 },
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
    for _, id in ipairs(needsData.order) do
        needs[#needs + 1] = {
            id = id, label = I18n.t("needs." .. id),
            value = math.floor(pet.needs[id] + 0.5), state = Needs.state(id, pet.needs[id]),
        }
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
    for _, id in ipairs(actions.order) do
        local cd = pet.cooldowns[id]
        local wait = (cd and cd > ctx.now) and math.ceil(cd - ctx.now) or 0
        acts[#acts + 1] = {
            id = id, label = I18n.t("actions." .. id .. ".name"),
            desc = I18n.t("actions." .. id .. ".desc"),
            ready = pet.status == "home" and wait == 0, cooldown = wait,
        }
    end
    return {
        id = pet.id, name = pet.name, status = pet.status,
        statusLabel = pet.status == "impounded" and I18n.t("ui.impounded") or "",
        redeem = pet.status == "impounded" and Shelter.info(ctx, pet) or nil,
        stage = pet.stage, stageLabel = I18n.t("stages." .. pet.stage),
        ageDays = Aging.ageDays(pet), ageLabel = I18n.t("ui.age", { days = Aging.ageDays(pet) }),
        mood = mood, moodLabel = I18n.t("moods." .. mood),
        needs = needs, traits = traits,
        bond = math.floor(bond + 0.5), bondLevel = Bond.level(bond), bondLabel = I18n.t("bond." .. Bond.level(bond)),
        actions = acts,
    }
end

function App:view(householdId, zoiId)
    self:sync()
    local ctx = self.ctx
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
        settings = Util.copy(ctx.cfg),
    }
end

return App
