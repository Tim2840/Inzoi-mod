local T = require("framework")
local H = require("helpers")
local Shelter = require("pawhome.pets.shelter")

-- The game clock jumps back (older game save loaded / debug clock restarted).
local function goBack(app, mock, minutes)
    mock.clock = mock.clock - minutes
    return app:tick()
end

T.test("clock: an action cooldown keeps its remaining time when the clock goes back", function()
    local app, mock = H.new()
    mock.clock = 10000; app:tick()
    local pet = H.adopt(app, 1, {}, "adult")
    pet.needs.hunger = 20
    T.truthy(app:perform(pet.id, 101, "feed").ok)
    local remaining = pet.cooldowns.feed - mock.clock
    T.eq(remaining, 120)
    goBack(app, mock, 6000)
    T.eq(pet.cooldowns.feed - mock.clock, remaining, "still 120 minutes left, not 6120")
    H.advance(app, mock, 121)
    pet.needs.hunger = 20
    T.truthy(app:perform(pet.id, 101, "feed").ok, "usable again after the real remaining time")
end)

T.test("clock: the shelter wait and the rehoming countdown are not distorted", function()
    local app, mock = H.new({ money = 1000 })
    mock.clock = 20000; app:tick()
    app:setSetting("agingEnabled", false)
    local pet = H.adopt(app, 1)
    pet.status = "impounded"; pet.impoundedAt = mock.clock - 300; pet.entity = nil
    local wait, days = Shelter.waitMinutes(app.ctx, pet), Shelter.daysLeft(app.ctx, pet)
    goBack(app, mock, 15000)
    T.eq(pet.status, "impounded")
    T.eq(Shelter.waitMinutes(app.ctx, pet), wait, "wait unchanged")
    T.eq(Shelter.daysLeft(app.ctx, pet), days, "days left unchanged")
    H.advance(app, mock, 24 * 60)
    T.truthy(app:redeem(1, 101, pet.id).ok, "redeemable after the normal wait")
end)

T.test("clock: notification rate limiting and misbehaviour memory survive too", function()
    local app, mock = H.new()
    mock.clock = 9000; app:tick()
    local pet = H.adopt(app, 1, {}, "adult")
    pet.notified.hungry = mock.clock - 60
    pet.lastMisbehavior = { habit = "scratch", at = mock.clock - 10 }
    pet.adoptedAt = mock.clock - 500
    goBack(app, mock, 4000)
    T.eq(mock.clock - pet.notified.hungry, 60)
    T.eq(mock.clock - pet.lastMisbehavior.at, 10)
    T.eq(mock.clock - pet.adoptedAt, 500)
end)

T.test("clock: pets do not age or starve while the clock is going back", function()
    local app, mock = H.new()
    mock.clock = 8000; app:tick()
    app:setSetting("agingEnabled", true)
    local pet = H.adopt(app, 1, {}, "adult")
    H.setNeeds(pet, 80)
    local age, hunger = pet.ageMinutes, pet.needs.hunger
    goBack(app, mock, 3000)
    T.eq(pet.ageMinutes, age); T.eq(pet.needs.hunger, hunger)
end)

T.test("clock: a normal forward tick does not shift anything", function()
    local app, mock = H.new()
    mock.clock = 5000; app:tick()
    local pet = H.adopt(app, 1)
    pet.cooldowns.feed = mock.clock + 100
    H.advance(app, mock, 60)
    T.eq(pet.cooldowns.feed, 5000 + 100)
end)
