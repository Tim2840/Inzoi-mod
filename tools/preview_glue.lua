-- Lets the HTML UI drive the real Lua engine on a desktop, without the game.
-- Used only by tools/preview_server.py.
local Mock = require("pawhome.adapters.mock")
local App = require("pawhome.app")
local Util = require("pawhome.core.util")

local P = { mock = nil, app = nil, HOUSEHOLD = 1, ZOI = 101 }

function P.reset(locale, seed)
    local mock = Mock.new({
        locale = locale or "en", money = 1000,
        strays = {
            { id = "s1", ref = "stray-1", stage = "adult", appearance = 11 },
            { id = "s2", ref = "stray-2", stage = "kitten", appearance = 12 },
        },
    })
    P.mock = mock
    P.app = assert(App.new(mock, { seed = seed or 2026 }))
    P.app:tick()
end

local function snapshot(extra)
    local r = extra or {}
    r.view = P.app:view(P.HOUSEHOLD, P.ZOI)
    r.money = P.mock.money[P.HOUSEHOLD]
    r.clock = P.mock.clock
    r.day = math.floor(P.mock.clock / Util.MINUTES_PER_DAY)
    r.time = string.format("%02d:%02d", math.floor(Util.hourOfDay(P.mock.clock)), P.mock.clock % 60)
    return r
end

local handlers = {}

function handlers.view() return snapshot() end

function handlers.perform(a)
    return snapshot({ result = P.app:perform(a.petId, P.ZOI, a.action) })
end

function handlers.offers(a)
    return snapshot({ offers = P.app:offers(P.HOUSEHOLD, a.refresh == true) })
end

function handlers.strays()
    local out = {}
    for i, s in ipairs(P.app:strays(P.HOUSEHOLD)) do
        out[i] = { id = s.id, stage = s.stage or "adult" }
    end
    return snapshot({ strays = out })
end

function handlers.adoptOffer(a)
    return snapshot({ result = P.app:adoptOffer(P.HOUSEHOLD, P.ZOI, a.offerId, a.name) })
end

function handlers.redeem(a)
    return snapshot({ result = P.app:redeem(P.HOUSEHOLD, P.ZOI, a.petId) })
end

function handlers.adoptStray(a)
    return snapshot({ result = P.app:adoptStray(P.HOUSEHOLD, P.ZOI, a.strayId, a.name) })
end

function handlers.setSetting(a)
    local ok, err = P.app:setSetting(a.key, a.value)
    return snapshot({ result = { ok = ok, message = err } })
end

function handlers.advance(a)
    local notes, done, total = {}, 0, a.minutes
    while done < total do
        local dt = math.min(60, total - done)
        P.mock.clock = P.mock.clock + dt
        for _, n in ipairs(P.app:tick()) do notes[#notes + 1] = n end
        done = done + dt
    end
    return snapshot({ notifications = notes })
end

function handlers.reset(a)
    P.reset(a.locale, a.seed)
    return snapshot()
end

function P.handle(method, args)
    local h = handlers[method]
    if not h then return { error = "unknown method " .. tostring(method) } end
    return h(args or {})
end

return P
