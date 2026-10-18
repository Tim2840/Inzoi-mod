-- Savegame state: one serialized table under a single key, versioned so later
-- releases can migrate old saves instead of dropping them.
local Api = require("pawhome.core.api")
local Serialize = require("pawhome.core.serialize")
local Util = require("pawhome.core.util")
local Log = require("pawhome.core.log")
local defaults = require("pawhome.data.settings")

local Storage = { KEY = "pawhome.save", VERSION = 1 }

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

local function migrate(state)
    while state.version < Storage.VERSION do
        local step = migrations[state.version]
        if not step then return nil, "no migration from v" .. tostring(state.version) end
        state = step(state)
        state.version = state.version + 1
    end
    return state
end

function Storage.load()
    local raw = Api.saveGet(Storage.KEY)
    if raw == nil or raw == "" then return Storage.default(), "new" end
    local state, err = Serialize.decode(raw)
    if type(state) ~= "table" or type(state.version) ~= "number" then
        Log.error("save is unreadable (" .. tostring(err) .. "), starting fresh")
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
    return migrated, "loaded"
end

function Storage.save(state)
    return Api.saveSet(Storage.KEY, Serialize.encode(state))
end

return Storage
