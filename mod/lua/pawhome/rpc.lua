-- The UI's method calls, answered by the engine. Same method names and result shape as
-- the desktop preview (tools/preview_glue.lua), so mod/ui/app.js works in both places.
-- `who` tells which household and Zoi the player is controlling right now.
local Api = require("pawhome.core.api")
local Util = require("pawhome.core.util")
local I18n = require("pawhome.core.i18n")

local Rpc = {}

local function snapshot(app, who, extra)
    local r = extra or {}
    local now = Api.now() or 0
    r.view = app:view(who.household, who.zoi)
    r.money = Api.funds(who.household)
    r.clock = now
    r.day = math.floor(now / Util.MINUTES_PER_DAY)
    r.time = string.format("%02d:%02d", math.floor(Util.hourOfDay(now)), math.floor(now % 60))
    return r
end

local handlers = {}

function handlers.view(app, who) return snapshot(app, who) end
function handlers.placeLitterBox(app, who) return snapshot(app, who, { result = app:placeLitterBox(who.household) }) end

function handlers.perform(app, who, a)
    return snapshot(app, who, { result = app:perform(a.petId, who.zoi, a.action) })
end

function handlers.offers(app, who, a)
    return snapshot(app, who, { offers = app:offers(who.household, a.refresh == true) })
end

function handlers.strays(app, who)
    local out = {}
    for i, s in ipairs(app:strays(who.household)) do
        local stage = s.stage or "adult"
        out[i] = { id = s.id, stage = stage, stageLabel = I18n.t("stages." .. stage) }
    end
    return snapshot(app, who, { strays = out, coats = app:coats() })
end

function handlers.adoptOffer(app, who, a)
    return snapshot(app, who, { result = app:adoptOffer(who.household, who.zoi, a.offerId, a.name, a.coat) })
end

function handlers.adoptStray(app, who, a)
    return snapshot(app, who, { result = app:adoptStray(who.household, who.zoi, a.strayId, a.name, a.coat) })
end

function handlers.restoreBackup(app, who)
    return snapshot(app, who, { result = app:restoreBackup() })
end

function handlers.vet(app, who, a)
    return snapshot(app, who, { result = app:vet(who.household, who.zoi, a.petId) })
end

function handlers.redeem(app, who, a)
    return snapshot(app, who, { result = app:redeem(who.household, who.zoi, a.petId) })
end

function handlers.rename(app, who, a)
    local ok, err = app:rename(a.petId, a.name)
    return snapshot(app, who, { result = { ok = ok, message = err } })
end

function handlers.setSetting(app, who, a)
    local ok, err = app:setSetting(a.key, a.value)
    return snapshot(app, who, { result = { ok = ok, message = err } })
end

-- Returns a result table; never raises.
function Rpc.handle(app, who, method, args)
    local h = handlers[method]
    if not h then return { error = "unknown method " .. tostring(method) } end
    if not app then return { error = "not_ready" } end
    if not who or who.household == nil then return { error = "no_household" } end
    local ok, result = pcall(h, app, who, args or {})
    if not ok then return { error = tostring(result) } end
    return result
end

return Rpc
