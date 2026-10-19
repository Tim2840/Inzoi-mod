-- Savegame state: one serialized table under a single key, versioned so later
-- releases can migrate old saves instead of dropping them.
local Api = require("pawhome.core.api")
local Serialize = require("pawhome.core.serialize")
local Util = require("pawhome.core.util")
local Log = require("pawhome.core.log")
local defaults = require("pawhome.data.settings")

local Storage = { KEY = "pawhome.save", VERSION = 2, BACKUP_GENERATIONS = 3 }

function Storage.default()
    return {
        version = Storage.VERSION,
        nextPetId = 1,
        pets = {},
        zoi = {},            -- zoiId -> { petTraining = xp }
        offers = {},         -- householdId -> { day = n, list = {...} }
        settings = Util.copy(defaults),
        rng = nil,
        lastTick = nil,
    }
end

-- migrations[n] upgrades a version n save to n + 1.
local migrations = {}

-- v1 -> v2: "running away" became "taken to the shelter by animal control".
migrations[1] = function(state)
    local settings = state.settings or {}
    if settings.neglectRunaway ~= nil then
        settings.animalControl = settings.neglectRunaway
        settings.neglectRunaway = nil
    end
    state.settings = settings
    for _, pet in ipairs(state.pets or {}) do
        if pet.status == "away" then
            pet.status = "impounded"
            pet.impoundedAt = pet.awaySince or state.lastTick or 0
            pet.awaySince = nil
            pet.entity = nil
        end
    end
    return state
end

local function migrate(state)
    while state.version < Storage.VERSION do
        local step = migrations[state.version]
        if not step then return nil, "no migration from v" .. tostring(state.version) end
        state = step(state)
        state.version = state.version + 1
    end
    return state
end

local function parse(raw)
    local state, err = Serialize.decode(raw)
    if type(state) == "table" and type(state.version) == "number" then return state end
    return nil, err
end

function Storage.load()
    local raw = Api.saveGet(Storage.KEY)
    if raw == nil or raw == "" then return Storage.default(), "new" end
    local state, err = parse(raw)
    local how = "loaded"
    if not state then
        -- the current file is damaged: fall back to the newest older generation that reads
        for n = 1, Storage.BACKUP_GENERATIONS do
            local older = Api.saveGetBackup(Storage.KEY, n)
            local candidate = older and parse(older)
            if candidate then
                Log.warn("save is unreadable (" .. tostring(err) .. "); restored backup generation " .. n)
                state, how = candidate, "restored"
                break
            end
        end
    end
    if not state then
        Log.error("save is unreadable (" .. tostring(err) .. ") and no backup could be read, starting fresh")
        return Storage.default(), "corrupt"
    end
    if state.version > Storage.VERSION then
        Log.error("save is from a newer PawHome; refusing to overwrite it")
        return nil, "newer"
    end
    local migrated, merr = migrate(state)
    if not migrated then
        Log.error("save migration failed: " .. tostring(merr))
        return nil, "migration"
    end
    -- fill in settings added by newer releases
    migrated.settings = migrated.settings or {}
    for k, v in pairs(defaults) do
        if migrated.settings[k] == nil then migrated.settings[k] = v end
    end
    migrated.pets = migrated.pets or {}
    migrated.zoi = migrated.zoi or {}
    migrated.offers = migrated.offers or {}
    return migrated, how
end

function Storage.save(state)
    return Api.saveSet(Storage.KEY, Serialize.encode(state))
end

return Storage
