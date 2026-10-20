local T = require("framework")
local H = require("helpers")
local Traits = require("pawhome.pets.traits")
local Util = require("pawhome.core.util")
local Rng = require("pawhome.core.rng")
local Aging = require("pawhome.pets.aging")
local Needs = require("pawhome.pets.needs")
local Moods = require("pawhome.pets.moods")
local Training = require("pawhome.pets.training")
local App = require("pawhome.app")
local traitData = require("pawhome.data.traits")

local DAY = 1440

---------------------------------------------------------------- traits

T.test("traits: 1-3 per pet, never a conflicting pair", function()
    local app = H.new()
    local ctx = app.ctx
    local counts = { 0, 0, 0 }
    for _ = 1, 600 do
        local list = Traits.generate(ctx)
        T.truthy(#list >= 1 and #list <= 3, "got " .. #list .. " traits")
        counts[#list] = counts[#list] + 1
        for i = 1, #list do
            for j = i + 1, #list do
                local a, b = traitData[list[i]], traitData[list[j]]
                T.falsy(Util.contains(a.conflicts, list[j]), list[i] .. " + " .. list[j])
                T.falsy(Util.contains(b.conflicts, list[i]), list[j] .. " + " .. list[i])
                T.truthy(list[i] ~= list[j], "duplicate trait")
            end
        end
    end
    T.gt(counts[1], 0); T.gt(counts[2], counts[1]); T.gt(counts[3], 0)
end)

---------------------------------------------------------------- needs

T.test("needs: hunger drops about 4/hour awake for an average adult", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    H.setNeeds(pet, 100)
    H.advance(app, mock, 6 * 60) -- 08:00 -> 14:00
    T.near(pet.needs.hunger, 100 - 4.0 * 6, 0.5)
    T.near(pet.needs.fun, 100 - 2.2 * 6, 0.5)
end)

T.test("furniture: a scratcher and a tower slow fun and energy decay at home", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    mock.lot[1] = { "CatScratcher01", "CatTower01_v01", "Sofa01" }
    H.setNeeds(pet, 100)
    H.advance(app, mock, 6 * 60)
    T.near(pet.needs.fun, 100 - 2.2 * 6 * (1 - 0.35), 0.5)
    T.near(pet.needs.energy, 100 - 2.5 * 6 * (1 - 0.15), 0.5)
    T.near(pet.needs.hunger, 100 - 4.0 * 6, 0.5)                -- no furniture for food
end)

T.test("furniture: duplicates count once and the cut is capped", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    mock.lot[1] = { "CatScratcher01", "CatScratcher01", "CatTower01", "CatTower01_v01", "CatWheel01" }
    H.setNeeds(pet, 100)
    H.advance(app, mock, 6 * 60)
    T.near(pet.needs.fun, 100 - 2.2 * 6 * 0.5, 0.5)             -- 0.6 capped at 0.5
end)

T.test("furniture: listed in the view with its effects, in both languages", function()
    local app, mock = H.new()
    H.adopt(app, 1, {}, "adult")
    mock.lot[1] = { "CatWheel01" }
    local v = app:view(1, 101)
    T.eq(#v.furniture, 1); T.eq(v.furniture[1].id, "CatWheel01")
    T.eq(v.furniture[1].name, "Cat Wheel")
    T.eq(v.furniture[1].effects[1], "Fun drops 25% slower")
    T.truthy(v.ui.furniture_none ~= nil)
    mock.lot[1] = {}
    T.eq(#app:view(1, 101).furniture, 0)
end)

T.test("needs: glutton gets hungry faster than a pet with no traits", function()
    local app, mock = H.new()
    local plain = H.adopt(app, 1, {}, "adult")
    local greedy = H.adopt(app, 2, { "glutton" }, "adult")
    H.setNeeds(plain, 100); H.setNeeds(greedy, 100)
    H.advance(app, mock, 4 * 60)
    T.gt(plain.needs.hunger, greedy.needs.hunger + 4)
end)

T.test("needs: kittens burn through needs faster than adults", function()
    local app, mock = H.new()
    local kitten = H.adopt(app, 1, {}, "kitten")
    local adult = H.adopt(app, 2, {}, "adult")
    H.setNeeds(kitten, 100); H.setNeeds(adult, 100)
    H.advance(app, mock, 4 * 60)
    T.gt(adult.needs.hunger, kitten.needs.hunger)
end)

T.test("needs: energy recovers while the pet sleeps at night", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    H.setNeeds(pet, 100)
    pet.needs.energy = 10
    mock.clock = 23 * 60 -- 23:00 on day 0
    app:tick()
    H.advance(app, mock, 6 * 60)
    T.gt(pet.needs.energy, 60)
end)

T.test("needs: sleeping hours wrap around midnight and lazy cats sleep an hour longer", function()
    local pet = { traits = {} }
    T.truthy(Needs.sleeping(pet, 23 * 60 + 30))
    T.truthy(Needs.sleeping(pet, 2 * 60))
    T.falsy(Needs.sleeping(pet, 12 * 60))
    T.falsy(Needs.sleeping(pet, 7 * 60 + 30))
    local lazy = { traits = { "lazy" } }
    T.truthy(Needs.sleeping(lazy, 7 * 60 + 30))
end)

T.test("needs: an empty litter box causes an accident and resets the need", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    H.setNeeds(pet, 100)
    pet.needs.bladder = 1
    local notes = H.advance(app, mock, 60)
    local seen = false
    for _, n in ipairs(notes) do if n.kind == "accident" then seen = true end end
    T.truthy(seen, "no accident notification")
    T.gt(pet.needs.bladder, 40)
end)

T.test("needs: after a long gap only the catch-up cap is simulated", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    H.setNeeds(pet, 100)
    mock.clock = mock.clock + 100 * 60
    app:tick()
    -- 12 hours of decay at most, so hunger cannot reach the floor
    T.gt(pet.needs.hunger, 100 - 4.0 * 12 - 1)
end)

---------------------------------------------------------------- moods

T.test("moods: follow the needs", function()
    local pet = { needs = { hunger = 90, energy = 90, fun = 90, bladder = 90 } }
    T.eq(Moods.compute(pet, false), "playful")
    T.eq(Moods.compute(pet, true), "asleep")
    pet.needs.fun = 40
    T.eq(Moods.compute(pet, false), "energized")
    pet.needs.energy = 60
    pet.needs.hunger = 85; pet.needs.bladder = 85
    pet.needs.fun = 55
    T.eq(Moods.compute(pet, false), "happy")
    pet.needs.hunger = 5
    T.eq(Moods.compute(pet, false), "sad")
    pet.needs.bladder = 2
    T.eq(Moods.compute(pet, false), "angry")
    pet.needs.hunger = 85
    T.eq(Moods.compute(pet, false), "uncomfortable")
end)

---------------------------------------------------------------- care

T.test("care: feeding raises hunger, is refused when full, and has a cooldown", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    pet.needs.hunger = 30
    local r = app:perform(pet.id, 101, "feed")
    T.truthy(r.ok, r.message)
    T.near(pet.needs.hunger, 85, 0.01)
    local again = app:perform(pet.id, 101, "feed")
    T.falsy(again.ok); T.eq(again.reason, "cooldown")
    H.advance(app, mock, 130)
    pet.needs.hunger = 95
    local full = app:perform(pet.id, 101, "feed")
    T.falsy(full.ok); T.eq(full.reason, "not_hungry")
end)

T.test("care: glutton gets more out of a meal", function()
    local app = H.new()
    local plain = H.adopt(app, 1, {}, "adult")
    local greedy = H.adopt(app, 2, { "glutton" }, "adult")
    plain.needs.hunger = 10; greedy.needs.hunger = 10
    app:perform(plain.id, 101, "feed"); app:perform(greedy.id, 101, "feed")
    T.gt(greedy.needs.hunger, plain.needs.hunger)
end)

T.test("care: play is refused when the pet is exhausted", function()
    local app = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    pet.needs.energy = 5
    local r = app:perform(pet.id, 101, "play")
    T.falsy(r.ok); T.eq(r.reason, "too_tired")
end)

T.test("care: affectionate cats bond faster than aloof ones", function()
    local app = H.new()
    local a = H.adopt(app, 1, { "affectionate" }, "adult")
    local b = H.adopt(app, 2, { "aloof" }, "adult")
    a.bond = {}; b.bond = {}
    app:perform(a.id, 101, "cuddle"); app:perform(b.id, 101, "cuddle")
    T.gt(a.bond["101"], b.bond["101"] * 2)
end)

T.test("care: kittens bond faster than adults", function()
    local app = H.new()
    local k = H.adopt(app, 1, {}, "kitten")
    local ad = H.adopt(app, 2, {}, "adult")
    k.bond = {}; ad.bond = {}
    app:perform(k.id, 101, "cuddle"); app:perform(ad.id, 101, "cuddle")
    T.gt(k.bond["101"], ad.bond["101"])
end)

T.test("care: feeding and play given in the game count like the panel's buttons", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    pet.needs.hunger = 30; pet.needs.fun = 20
    local Bond = require("pawhome.pets.bond")
    local bondBefore = Bond.get(pet, 202)
    mock.giveCare(pet.entity, "feed", 202)
    mock.giveCare(pet.entity, "play", 202)
    local res = app:applyCare()
    T.eq(#res, 2)
    T.truthy(res[1].ok, res[1].message); T.truthy(res[2].ok, res[2].message)
    T.eq(res[1].source, "game")
    T.near(pet.needs.hunger, 85 - 4, 0.01)           -- play costs a little hunger
    T.truthy(pet.needs.fun > 20)
    T.truthy(Bond.get(pet, 202) > bondBefore)       -- the Zoi who gave the care bonds
    T.eq(#app:applyCare(), 0)                         -- each event counts once
    -- the same action again inside the cooldown gives nothing
    mock.giveCare(pet.entity, "feed", 202)
    local again = app:applyCare()
    T.falsy(again[1].ok); T.eq(again[1].reason, "cooldown"); T.eq(again[1].action, "feed")
end)

T.test("care: game care is ignored while no savegame is loaded", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    app.suspended = true
    mock.giveCare(pet.entity, "feed", 202)
    T.eq(#app:applyCare(), 0)
end)

T.test("care: one litter box serves every pet in the home", function()
    local app = H.new()
    local a = H.adopt(app, 1, {}, "adult")
    local b = H.adopt(app, 2, {}, "adult")
    a.needs.bladder = 10; b.needs.bladder = 10
    T.truthy(app:perform(a.id, 101, "clean_litter").ok)
    T.eq(a.needs.bladder, 100); T.eq(b.needs.bladder, 100)
    -- and the cooldown applies to the whole home
    T.falsy(app:perform(b.id, 101, "clean_litter").ok)
end)

T.test("care: getting to know a stray reveals traits one by one, then stops", function()
    local app = H.new({ strays = { { id = "s1", ref = "ref1", stage = "adult" } } })
    local r = app:adoptStray(1, 101, "s1", "Bean")
    T.truthy(r.ok, r.message)
    local pet = app.ctx.state.pets[1]
    local hidden = #Traits.unrevealed(pet)
    T.gt(hidden, 0)
    local revealedCount = 0
    for _ = 1, 40 do
        pet.cooldowns.get_to_know = nil
        local res = app:perform(pet.id, 101, "get_to_know")
        T.truthy(res.ok)
        if res.extra.revealed then revealedCount = revealedCount + 1 end
    end
    T.eq(revealedCount, hidden)
    T.eq(#Traits.unrevealed(pet), 0)
    pet.cooldowns.get_to_know = nil
    local done = app:perform(pet.id, 101, "get_to_know")
    T.truthy(done.extra.nothingToLearn)
    T.eq(pet.cooldowns.get_to_know, nil, "should not cost a cooldown")
end)

T.test("care: hidden traits are masked in the view until revealed", function()
    local app = H.new({ strays = { { id = "s1", ref = "ref1" } } })
    app:adoptStray(1, 101, "s1", "Bean")
    local view = app:view(1, 101)
    for _, t in ipairs(view.pets[1].traits) do
        T.falsy(t.known)
        T.eq(t.label, "???")
    end
end)

T.test("training: scolding works right after misbehaviour, not otherwise", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    pet.habits.scratch = 0.5
    local before = pet.habits.scratch
    app:perform(pet.id, 101, "scold")
    T.eq(pet.habits.scratch, before, "scolding without a reason must not change habits")
    pet.cooldowns.scold = nil
    pet.lastMisbehavior = { habit = "scratch", at = mock.clock }
    local r = app:perform(pet.id, 101, "scold")
    T.truthy(r.ok); T.lt(pet.habits.scratch, before)
end)

T.test("training: mischievous and spoiled cats shrug off scolding", function()
    local app, mock = H.new()
    local good = H.adopt(app, 1, {}, "adult")
    local bad = H.adopt(app, 2, { "spoiled" }, "adult")
    good.habits.scratch = 0.6; bad.habits.scratch = 0.6
    good.lastMisbehavior = { habit = "scratch", at = mock.clock }
    bad.lastMisbehavior = { habit = "scratch", at = mock.clock }
    app:perform(good.id, 101, "scold"); local r = app:perform(bad.id, 101, "scold")
    T.gt(0.6 - good.habits.scratch, (0.6 - bad.habits.scratch) * 2)
    T.truthy(r.message:find("ignores"))
end)

T.test("training: Pet Training levels up from care and announces it", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, { "clever" }, "adult")
    local sawLevelUp = false
    for _ = 1, 30 do
        pet.cooldowns = {}
        local r = app:perform(pet.id, 101, "play")
        for _, n in ipairs(r.notifications or {}) do if n.kind == "skill_up" then sawLevelUp = true end end
        pet.needs.energy = 80
    end
    T.truthy(sawLevelUp)
    T.gt(Training.level(app.ctx, 101), 0)
    T.eq(Training.level(app.ctx, 555), 0)
end)

T.test("training: higher skill shapes habits faster", function()
    local app, mock = H.new()
    local a = H.adopt(app, 1, {}, "adult")
    local b = H.adopt(app, 2, {}, "adult")
    app.ctx.state.zoi["102"] = { petTraining = 150 }
    a.habits.scratch = 0.8; b.habits.scratch = 0.8
    a.lastMisbehavior = { habit = "scratch", at = mock.clock }
    b.lastMisbehavior = { habit = "scratch", at = mock.clock }
    app:perform(a.id, 101, "scold"); app:perform(b.id, 102, "scold")
    T.gt(a.habits.scratch, b.habits.scratch)
end)

---------------------------------------------------------------- aging

T.test("aging: kitten grows to adult, then elder, then passes away", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "kitten")
    pet.lifeMul = 1.0
    pet.ageMinutes = 0
    local sequence, last = { "kitten" }, "kitten"
    for _ = 1, 30 * 24 do
        H.setNeeds(pet, 90) -- keep it healthy
        pet.neglect = 0
        H.advance(app, mock, 60)
        if pet.stage ~= last then sequence[#sequence + 1] = pet.stage; last = pet.stage end
        if pet.status == "dead" then break end
    end
    T.eq(table.concat(sequence, ">"), "kitten>adult>elder")
    T.eq(pet.status, "dead")
    -- 5 + 16 + 8 = 29 days
    T.near(pet.diedAt / DAY, 29, 1.2, "died at the wrong time")
end)

T.test("aging: the passing is announced and bonded Zoi grieve", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "elder")
    pet.bond["101"] = 60
    pet.ageMinutes = Aging.lifeEnd(app.ctx, pet) - 30
    H.setNeeds(pet, 90)
    local notes = H.advance(app, mock, 60)
    local died = false
    for _, n in ipairs(notes) do if n.kind == "died" then died = true end end
    T.truthy(died)
    local grief = false
    for _, b in ipairs(mock.buffs) do if b.buff == "pawhome_grief" and b.zoi == 101 then grief = true end end
    T.truthy(grief)
    T.eq(#app:view(1, 101).pets, 0)
end)

T.test("aging: turning aging off freezes the pet", function()
    local app, mock = H.new()
    T.truthy(app:setSetting("agingEnabled", false))
    local pet = H.adopt(app, 1, {}, "adult")
    local age = pet.ageMinutes
    for _ = 1, 10 do H.setNeeds(pet, 90); H.advance(app, mock, 24 * 60) end
    T.eq(pet.ageMinutes, age); T.eq(pet.stage, "adult"); T.eq(pet.status, "home")
end)

T.test("aging: lifeScale stretches the lifespan", function()
    local app = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    pet.lifeMul = 1
    local base = Aging.lifeEnd(app.ctx, pet)
    app:setSetting("lifeScale", 2)
    T.near(Aging.lifeEnd(app.ctx, pet), base * 2, 1e-6)
end)

---------------------------------------------------------------- neglect / animal control / shelter

local function impound(app, mock, pet)
    -- neglect the pet until animal control takes it
    for _ = 1, 6 * 24 do
        H.advance(app, mock, 60)
        if pet.status == "impounded" then return end
    end
    error("pet was never impounded")
end

T.test("neglect: soft penalty, then a warning visit, then animal control - never before", function()
    local app, mock = H.new()
    app:setSetting("agingEnabled", false)
    local pet = H.adopt(app, 1, { "free_spirit" }, "adult")
    local bondAtStart = pet.bond["101"]
    local warnedAt, impoundedAt, bondAtWarning
    for hour = 1, 6 * 24 do
        H.advance(app, mock, 60)
        if pet.flags.warned and not warnedAt then warnedAt = hour; bondAtWarning = pet.bond["101"] end
        if pet.status == "impounded" then impoundedAt = hour break end
    end
    T.truthy(warnedAt, "never warned")
    T.truthy(impoundedAt, "never taken")
    T.lt(warnedAt, impoundedAt)
    T.gt(impoundedAt, 12, "taken unreasonably fast")
    T.lt(bondAtWarning, bondAtStart, "the bond should drop while the pet is neglected")
    T.eq(pet.entity, nil, "the cat should leave the world")
    T.truthy(pet.impoundedAt ~= nil)
end)

T.test("neglect: the warning and the pick-up are announced", function()
    local app, mock = H.new()
    app:setSetting("agingEnabled", false)
    local pet = H.adopt(app, 1)
    local seen = {}
    for _ = 1, 6 * 24 do
        for _, n in ipairs(H.advance(app, mock, 60)) do seen[n.kind] = n.text end
        if pet.status == "impounded" then break end
    end
    T.truthy(seen.neglect_warning and seen.neglect_warning:find("Animal control"))
    T.truthy(seen.impounded and seen.impounded:find("shelter"))
end)

T.test("neglect: a bonded pet is tolerated much longer, wandering personalities less", function()
    local app = H.new()
    local a = H.adopt(app, 1, {}, "adult")
    local b = H.adopt(app, 1, {}, "adult")   -- adopted cats leave the shelter, so always index 1
    local c = H.adopt(app, 1, { "free_spirit" }, "adult")
    a.bond = { ["101"] = 30 }; b.bond = { ["101"] = 100 }; c.bond = { ["101"] = 30 }
    local Neglect = require("pawhome.pets.neglect")
    T.gt(Neglect.impoundMinutes(b), Neglect.impoundMinutes(a) * 1.4)
    T.lt(Neglect.impoundMinutes(c), Neglect.impoundMinutes(a))
end)

T.test("neglect: turning animal control off keeps the pet home", function()
    local app, mock = H.new()
    app:setSetting("animalControl", false)
    app:setSetting("agingEnabled", false)
    local pet = H.adopt(app, 1, {}, "adult")
    H.advance(app, mock, 10 * 24 * 60)
    T.eq(pet.status, "home")
end)

T.test("shelter: an impounded pet cannot be cared for and still uses a slot", function()
    local app, mock = H.new({ money = 10000 })
    app:setSetting("agingEnabled", false)
    app:setSetting("maxPetsPerHousehold", 1)
    local pet = H.adopt(app, 1)
    impound(app, mock, pet)
    local r = app:perform(pet.id, 101, "feed")
    T.falsy(r.ok); T.eq(r.reason, "not_home")
    local o = app:offers(1, true)
    T.eq(app:adoptOffer(1, 101, o[1].id, "Another").reason, "max_pets")
    local v = app:view(1, 101).pets[1]
    T.eq(v.status, "impounded"); T.eq(v.statusLabel, "At the animal shelter")
    T.truthy(v.redeem and v.redeem.fee == 200 and v.redeem.ready == false)
end)

T.test("shelter: redeeming needs the waiting period, then costs the fee and halves the bond", function()
    local app, mock = H.new({ money = 1000 })
    app:setSetting("agingEnabled", false)
    local pet = H.adopt(app, 1)
    pet.bond["101"] = 80
    impound(app, mock, pet)
    local bondBefore = pet.bond["101"]
    local moneyBefore = mock.money[1]

    local early = app:redeem(1, 101, pet.id)
    T.falsy(early.ok); T.eq(early.reason, "redeem_wait"); T.eq(mock.money[1], moneyBefore)

    local notes = H.advance(app, mock, 24 * 60)
    local redeemable = false
    for _, n in ipairs(notes) do if n.kind == "redeemable" then redeemable = true end end
    T.truthy(redeemable, "should announce that the pet can be redeemed")

    local r = app:redeem(1, 101, pet.id)
    T.truthy(r.ok, r.message)
    T.eq(mock.money[1], moneyBefore - 200)
    T.eq(pet.status, "home")
    T.truthy(pet.entity ~= nil and mock.entities[pet.entity] ~= nil, "the cat should be back in the world")
    T.near(pet.bond["101"], bondBefore * 0.5, 0.01)
    T.eq(pet.neglect, 0); T.eq(pet.flags.warned, nil)
    T.gt(pet.needs.hunger, 50)
    T.eq(r.notifications[1].kind, "redeemed")
    T.falsy(app:redeem(1, 101, pet.id).ok, "cannot redeem a pet that is already home")
end)

T.test("shelter: redeeming fails cleanly without money or when the world refuses", function()
    local app, mock = H.new({ money = 1000 })
    app:setSetting("agingEnabled", false)
    local pet = H.adopt(app, 1)
    impound(app, mock, pet)
    H.advance(app, mock, 24 * 60)

    mock.money[1] = 50
    local poor = app:redeem(1, 101, pet.id)
    T.falsy(poor.ok); T.eq(poor.reason, "no_funds"); T.eq(mock.money[1], 50); T.eq(pet.status, "impounded")

    mock.money[1] = 1000
    mock.failSpawn = true
    local stuck = app:redeem(1, 101, pet.id)
    T.falsy(stuck.ok); T.eq(stuck.reason, "spawn_failed"); T.eq(mock.money[1], 1000); T.eq(pet.status, "impounded")

    mock.failSpawn = false
    T.eq(app:redeem(2, 101, pet.id).reason, "no_pet", "another household cannot redeem it")
    T.truthy(app:redeem(1, 101, pet.id).ok)
end)

T.test("shelter: nobody redeems it in time and the pet is rehomed, freeing the slot", function()
    local app, mock = H.new()
    app:setSetting("agingEnabled", false)
    app:setSetting("maxPetsPerHousehold", 1)
    local pet = H.adopt(app, 1)
    impound(app, mock, pet)
    local rehomed = false
    for _, n in ipairs(H.advance(app, mock, 11 * 24 * 60)) do
        if n.kind == "rehomed" then rehomed = true end
    end
    T.truthy(rehomed)
    T.eq(pet.status, "lost")
    T.eq(#app:view(1, 101).pets, 0)
    local o = app:offers(1, true)
    T.truthy(app:adoptOffer(1, 101, o[1].id, "Fresh Start").ok, "the slot should be free again")
end)

T.test("shelter: the view is localised for Chinese", function()
    local app, mock = H.new({ locale = "zh-TW" })
    app:setSetting("agingEnabled", false)
    local pet = H.adopt(app, 1)
    impound(app, mock, pet)
    local v = app:view(1, 101)
    T.eq(v.pets[1].statusLabel, "在動物收容所")
    T.eq(v.ui.redeem, "領回")
end)

---------------------------------------------------------------- adoption

T.test("adoption: shelter shows three offers with traits, rotates daily", function()
    local app, mock = H.new()
    local offers = app:offers(1)
    T.eq(#offers, 3)
    for _, o in ipairs(offers) do
        T.truthy(#o.traits >= 1); T.truthy(o.name ~= ""); T.eq(o.fee, 150)
        T.truthy(o.traits[1].label ~= o.traits[1].id, "labels should be localised")
    end
    local again = app:offers(1)
    T.eq(again[1].id, offers[1].id, "same day should keep the same offers")
    mock.clock = mock.clock + DAY
    local tomorrow = app:offers(1)
    T.truthy(tomorrow[1].id ~= offers[1].id)
end)

T.test("adoption: shelter never offers two cats with the same name, nor your cat's name", function()
    local app = H.new({ seed = 3 })
    for _ = 1, 40 do
        local offers = app:offers(1, true)
        local seen = {}
        for _, o in ipairs(offers) do
            T.falsy(seen[o.name], "duplicate offer name " .. o.name)
            seen[o.name] = true
        end
    end
end)

T.test("adoption: fee is charged, all traits are visible, pet appears in the world", function()
    local app, mock = H.new({ money = 500 })
    local offers = app:offers(1)
    local r = app:adoptOffer(1, 101, offers[1].id, "  Mochi ")
    T.truthy(r.ok, r.message)
    T.eq(mock.money[1], 350)
    local pet = app.ctx.state.pets[1]
    T.eq(pet.name, "Mochi")
    for _, id in ipairs(pet.traits) do T.truthy(pet.revealed[id]) end
    T.truthy(pet.entity ~= nil); T.truthy(mock.entities[pet.entity] ~= nil)
    T.eq(pet.bond["101"] > 0, true)
    T.eq(#app:offers(1), 2, "the adopted cat leaves the shelter")
    T.eq(r.notifications[1].kind, "adopted")
end)

T.test("adoption: not enough money, bad names and full households are refused", function()
    local app, mock = H.new({ money = 100 })
    local offers = app:offers(1)
    local poor = app:adoptOffer(1, 101, offers[1].id, "Mochi")
    T.falsy(poor.ok); T.eq(poor.reason, "no_funds"); T.eq(mock.money[1], 100)
    mock.money[1] = 10000
    local long = app:adoptOffer(1, 101, offers[1].id, string.rep("a", 25))
    T.falsy(long.ok); T.eq(long.reason, "bad_name"); T.eq(mock.money[1], 10000)
    T.eq(app:adoptOffer(1, 101, 99999, "Ghost").reason, "no_offer")
    for i = 1, 4 do
        local o = app:offers(1, true)
        T.truthy(app:adoptOffer(1, 101, o[1].id, "Cat" .. i).ok)
    end
    local o = app:offers(1, true)
    local full = app:adoptOffer(1, 101, o[1].id, "Extra")
    T.falsy(full.ok); T.eq(full.reason, "max_pets")
end)

T.test("adoption: a failed spawn costs nothing", function()
    local app, mock = H.new({ money = 500 })
    mock.failSpawn = true
    local o = app:offers(1)
    local r = app:adoptOffer(1, 101, o[1].id, "Mochi")
    T.falsy(r.ok); T.eq(r.reason, "spawn_failed"); T.eq(mock.money[1], 500)
    T.eq(#app.ctx.state.pets, 0)
end)

T.test("adoption: works as a virtual pet when the game cannot spawn cats (plan C)", function()
    local app, mock = H.new({ caps = {} })
    local o = app:offers(1)
    local r = app:adoptOffer(1, 101, o[1].id, "Mochi")
    T.truthy(r.ok, r.message)
    local pet = app.ctx.state.pets[1]
    T.eq(pet.entity, nil)
    H.advance(app, mock, 24 * 60)
    T.eq(pet.status ~= "dead", true)
    local fed = app:perform(pet.id, 101, "feed")
    T.truthy(fed.ok, fed.message)
end)

T.test("adoption: stray cats - moved when allowed, spawned otherwise, hidden traits", function()
    local strays = { { id = "s1", ref = "streetcat", stage = "kitten" } }
    local app, mock = H.new({ strays = strays })
    local r = app:adoptStray(1, 101, "s1", "")
    T.truthy(r.ok, r.message)
    local pet = app.ctx.state.pets[1]
    T.eq(pet.stage, "kitten")
    T.eq(mock.entities[pet.entity].from, "streetcat")
    T.truthy(pet.name ~= "", "an empty name should get a default one")
    T.eq(next(pet.revealed), nil)
    T.eq(app:adoptStray(1, 101, "nope", "X").reason, "no_stray")

    local app2, mock2 = H.new({ strays = strays, caps = { spawn = true } })
    T.truthy(app2:adoptStray(1, 101, "s1", "Bean").ok)
    T.truthy(mock2.entities[app2.ctx.state.pets[1].entity].spec ~= nil)
end)

T.test("adoption: Chinese names are accepted and counted in characters", function()
    local app = H.new({ locale = "zh-TW" })
    local o = app:offers(1)
    T.truthy(app:adoptOffer(1, 101, o[1].id, "麻糬").ok)
    T.eq(app.ctx.state.pets[1].name, "麻糬")
    T.truthy(app:rename(app.ctx.state.pets[1].id, "年糕").ok)
    T.eq(app.ctx.state.pets[1].name, "年糕")
    T.falsy(app:rename(app.ctx.state.pets[1].id, "").ok)
end)

---------------------------------------------------------------- persistence / world sync

T.test("persistence: pets survive save and load with needs, bond, traits and rng", function()
    local app, mock = H.new({ seed = 77 })
    local pet = H.adopt(app, 1, { "playful", "clever" }, "adult")
    app:perform(pet.id, 101, "cuddle")
    H.advance(app, mock, 5 * 60)
    app:save()

    local reloaded = assert(App.new(mock))
    local back = reloaded.ctx.state.pets[1]
    T.eq(back.name, pet.name); T.eq(back.traits[1], "playful"); T.eq(back.traits[2], "clever")
    T.near(back.needs.hunger, pet.needs.hunger, 1e-6)
    T.near(back.bond["101"], pet.bond["101"], 1e-6)
    T.eq(reloaded.ctx.rng:getState(), app.ctx.rng:getState())
    T.eq(#reloaded:view(1, 101).pets, 1)
end)

T.test("world sync: a vanished cat is put back", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    mock.entities[pet.entity] = nil
    H.advance(app, mock, 60)
    T.truthy(pet.entity ~= nil and mock.entities[pet.entity] ~= nil)
end)

T.test("world sync: happy bonded Zoi get a mood buff, strangers do not", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    H.setNeeds(pet, 85)
    pet.bond["101"] = 60
    pet.bond["102"] = 0
    mock.clock = 12 * 60
    app:tick()
    H.advance(app, mock, 60)
    local got = {}
    for _, b in ipairs(mock.buffs) do got[b.zoi] = true end
    T.truthy(got[101]); T.falsy(got[102])
end)

T.test("notifications: routine alerts are rate limited, important ones are not", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    pet.needs.hunger = 20
    app:setSetting("agingEnabled", false)
    local hungry = 0
    for _, n in ipairs(H.advance(app, mock, 5 * 60)) do if n.kind == "hungry" then hungry = hungry + 1 end end
    T.eq(hungry, 1, "should only nag once in 5 hours")
    local more = 0
    for _, n in ipairs(H.advance(app, mock, 3 * 60)) do if n.kind == "hungry" then more = more + 1 end end
    T.eq(more, 1, "and again after the cooldown")
end)

T.test("settings: validated and applied", function()
    local app = H.new()
    T.falsy(app:setSetting("nope", 1))
    T.falsy(app:setSetting("lifeScale", "long"))
    T.truthy(app:setSetting("lifeScale", 100)); T.eq(app.ctx.cfg.lifeScale, 4)
    T.falsy(app:setSetting("language", "fr"))
    T.truthy(app:setSetting("language", "zh-TW"))
    T.eq(app:view(1, 101).title, "毛孩之家")
    T.truthy(app:setSetting("language", "auto"))
    T.eq(app:view(1, 101).title, "Paw Home")
end)

T.test("view: everything the UI needs is localised and complete", function()
    local app = H.new({ locale = "zh-TW" })
    local pet = H.adopt(app, 1, { "playful" }, "adult")
    local v = app:view(1, 101).pets[1]
    T.eq(#v.needs, 4); T.eq(#v.actions, 8)
    T.eq(v.stageLabel, "成貓")
    T.eq(v.traits[1].label, "愛玩")
    for _, n in ipairs(v.needs) do T.truthy(n.value >= 0 and n.value <= 100) end
    for _, a in ipairs(v.actions) do T.truthy(a.label ~= "" and a.label ~= a.id) end
end)

---------------------------------------------------------------- whole-game simulation

local function careBot(app, mock, pet)
    local h = Util.hourOfDay(mock.clock)
    if h < 8 or h > 22 then return end
    if pet.needs.hunger < 55 then app:perform(pet.id, 101, "feed") end
    if pet.needs.fun < 55 then app:perform(pet.id, 101, "play") end
    if pet.needs.bladder < 55 then app:perform(pet.id, 101, "clean_litter") end
    if pet.needs.fun < 75 then app:perform(pet.id, 101, "cuddle") end
    if pet.illness then app:vet(1, 101, pet.id) end
end

T.test("simulation: 30 days of normal care keeps a cat healthy and happy", function()
    for _, seed in ipairs({ 1, 2, 3 }) do
        local app, mock = H.new({ seed = seed })
        app:setSetting("agingEnabled", false)
        local pet = H.adopt(app, 1)
        local happyHours, total, impounded = 0, 0, 0
        for _ = 1, 30 * 24 do
            H.advance(app, mock, 60)
            careBot(app, mock, pet)
            total = total + 1
            local m = Moods.compute(pet, Needs.sleeping(pet, mock.clock))
            if m == "happy" or m == "playful" or m == "energized" or m == "content" or m == "asleep" then happyHours = happyHours + 1 end
            if pet.status == "impounded" then impounded = impounded + 1 end
        end
        T.eq(pet.status, "home", "seed " .. seed)
        T.eq(impounded, 0)
        T.gt(happyHours / total, 0.8, "cat was unhappy too often (seed " .. seed .. ")")
        T.gt(pet.bond["101"], 40, "bond should grow with care")
    end
end)

T.test("simulation: 30 days of total neglect gets the cat taken to the shelter", function()
    for _, seed in ipairs({ 1, 2, 3 }) do
        local app, mock = H.new({ seed = seed })
        app:setSetting("agingEnabled", false)
        local pet = H.adopt(app, 1)
        local leftAt
        for hour = 1, 30 * 24 do
            H.advance(app, mock, 60)
            if pet.status ~= "home" and not leftAt then leftAt = hour end
        end
        T.truthy(leftAt, "neglected cat never left (seed " .. seed .. ")")
        T.gt(leftAt, 24)
    end
end)


T.test("settings: one pet per household by default; the settings page allows at most 4", function()
    local Mock = require("pawhome.adapters.mock")
    local App = require("pawhome.app")
    local mock = Mock.new({ money = 100000 })
    local app = assert(App.new(mock, { seed = 7 }))
    app:tick()
    T.eq(app.ctx.cfg.maxPetsPerHousehold, 1, "shipped default (PO decision 2026-10-20)")
    local offers = app:offers(1)
    T.truthy(app:adoptOffer(1, 101, offers[1].id, "First").ok)
    local second = app:adoptOffer(1, 101, app:offers(1)[1].id, "Second")
    T.eq(second.reason, "max_pets", "a second pet is refused by default")
    T.truthy(app:setSetting("maxPetsPerHousehold", 8))
    T.eq(app.ctx.cfg.maxPetsPerHousehold, 4, "clamped to the maximum of 4")
    T.truthy(app:adoptOffer(1, 101, app:offers(1)[1].id, "Second").ok, "allowed once raised")
end)

---------------------------------------------------------------- illness and the vet

-- Starves the pet (hunger stays at 0) until it falls ill, at most `hours`.
local function starveUntilIll(app, mock, pet, hours)
    for _ = 1, hours do
        pet.needs.hunger = 0
        H.advance(app, mock, 60)
        if pet.illness then return true end
    end
    return false
end

T.test("illness: a starving cat falls ill, is told about, and feels unwell", function()
    local app, mock = H.new({ seed = 7 })
    app:setSetting("animalControl", false)
    local pet = H.adopt(app, 1, {}, "adult")
    T.truthy(starveUntilIll(app, mock, pet, 24 * 10), "should fall ill within ten days of starving")
    T.eq(pet.illness.id, "upset_tummy")
    T.eq(Moods.compute(pet, false), "sick")
    local v = app:view(1, 101).pets[1]
    T.eq(v.illness.name, "Upset Tummy"); T.eq(v.illness.vetFee, 120); T.falsy(v.illness.vetOnly)
end)

T.test("illness: makes the listed needs drop faster", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    pet.illness = { id = "cold", since = mock.clock, goodHours = 0 }
    H.setNeeds(pet, 100)
    H.advance(app, mock, 6 * 60)
    T.near(pet.needs.energy, 100 - 2.5 * 6 * 1.5, 0.5)
    T.near(pet.needs.hunger, 100 - 4.0 * 6, 0.5)
end)

T.test("illness: good care cures a cold in time, fleas need the vet", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    pet.illness = { id = "cold", since = mock.clock, goodHours = 0 }
    for _ = 1, 70 do H.setNeeds(pet, 90); H.advance(app, mock, 60) end
    T.eq(pet.illness, nil, "recovered after 60 good hours")
    pet.illness = { id = "fleas", since = mock.clock, goodHours = 0 }
    for _ = 1, 24 * 5 do H.setNeeds(pet, 90); H.advance(app, mock, 60) end
    T.eq(pet.illness.id, "fleas")
    T.truthy(app:view(1, 101).pets[1].illness.vetOnly)
end)

T.test("illness: the vet cures for a fee and refuses healthy pets or empty wallets", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1, {}, "adult")
    local before = mock.money[1]
    local r = app:vet(1, 101, pet.id)
    T.falsy(r.ok); T.eq(r.reason, "not_sick")
    pet.illness = { id = "fleas", since = mock.clock, goodHours = 0 }
    mock.money[1] = 50
    r = app:vet(1, 101, pet.id)
    T.falsy(r.ok); T.eq(r.reason, "no_funds"); T.eq(pet.illness.id, "fleas")
    mock.money[1] = before
    r = app:vet(1, 101, pet.id)
    T.truthy(r.ok, r.message); T.eq(pet.illness, nil); T.eq(mock.money[1], before - 120)
end)

T.test("illness: switched off in settings, nobody falls ill", function()
    local app, mock = H.new({ seed = 7 })
    app:setSetting("animalControl", false)
    T.truthy(app:setSetting("illnessEnabled", false))
    local pet = H.adopt(app, 1, {}, "adult")
    T.falsy(starveUntilIll(app, mock, pet, 24 * 10))
end)

return true
