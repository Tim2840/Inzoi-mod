local T = require("framework")
local H = require("helpers")
local presence = require("pawhome.data.presence")

local function adoptOne(opts)
    local app, mock = H.new(opts)
    app:setSetting("agingEnabled", false)
    local pet = H.adopt(app, 1, {}, "adult")
    mock.spawnCalls = 0
    return app, mock, pet
end

local function entityCount(mock)
    local n = 0
    for _ in pairs(mock.entities) do n = n + 1 end
    return n
end

T.test("presence: a cat the game reports as present is never respawned", function()
    local app, mock, pet = adoptOne()
    H.advance(app, mock, 5 * 60)
    T.eq(mock.spawnCalls, 0)
    T.eq(pet.presence, nil)
end)

T.test("presence: a vanished cat is replaced, and only once", function()
    local app, mock, pet = adoptOne()
    local old = pet.entity
    mock.entities[old] = nil
    H.advance(app, mock, 60)
    T.eq(mock.spawnCalls, 1)
    T.truthy(pet.entity ~= nil and pet.entity ~= old and mock.entities[pet.entity] ~= nil)
    H.advance(app, mock, 5 * 60)
    T.eq(mock.spawnCalls, 1, "no more spawns once it is back")
end)

T.test("presence: a cat that is only hidden (level unloaded) is not duplicated", function()
    local app, mock, pet = adoptOne()
    local old = pet.entity
    mock.hidden[old] = true               -- exists, but the game does not report it
    H.advance(app, mock, 60)
    T.eq(mock.entities[old], nil, "the old reference must be despawned first")
    T.eq(entityCount(mock), 1, "exactly one cat in the world")
end)

T.test("presence: failed spawns back off and pause until the next game day", function()
    local app, mock, pet = adoptOne()
    mock.entities[pet.entity] = nil
    mock.failSpawn = true
    H.advance(app, mock, 10 * 60)         -- 08:00 -> 18:00, hourly ticks
    T.eq(mock.spawnCalls, presence.maxFailures, "stops after the failure limit")
    H.advance(app, mock, 5 * 60)          -- still the same game day
    T.eq(mock.spawnCalls, presence.maxFailures)
    H.advance(app, mock, 2 * 60)          -- 23:00 -> 01:00, the next game day has begun
    T.gt(mock.spawnCalls, presence.maxFailures, "tries again tomorrow")
    mock.failSpawn = false
    H.advance(app, mock, 2 * 60)
    T.truthy(pet.entity ~= nil and mock.entities[pet.entity] ~= nil, "back in the world once the game allows it")
    T.eq(pet.presence, nil, "bookkeeping cleared")
end)

T.test("presence: retries are spaced by retryMinutes even when ticks are frequent", function()
    local app, mock, pet = adoptOne()
    mock.entities[pet.entity] = nil
    mock.failSpawn = true
    H.advance(app, mock, 50, 5)           -- ten ticks within 50 minutes
    T.eq(mock.spawnCalls, 1)
end)

T.test("presence: virtual pets (no spawn capability) are left alone", function()
    local app, mock = H.new({ caps = {} })
    app:setSetting("agingEnabled", false)
    local pet = H.adopt(app, 1, {}, "adult")
    H.advance(app, mock, 24 * 60)
    T.eq(mock.spawnCalls, 0); T.eq(pet.entity, nil)
end)

T.test("presence: the retry timer survives a backwards clock", function()
    local app, mock, pet = adoptOne()
    mock.clock = 9000; app:tick()
    pet.presence = { fails = 2, lastTry = mock.clock - 10, day = math.floor(mock.clock / 1440) }
    mock.clock = mock.clock - 4000
    app:tick()
    T.eq(mock.clock - pet.presence.lastTry, 10)
end)
