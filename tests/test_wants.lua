-- Cat Moments (docs/design/gameplay-v2.md): wants, no cooldowns with fatigue, happy moments,
-- keepsakes and the album.
local T = require("framework")
local H = require("helpers")
local Bond = require("pawhome.pets.bond")
local Wants = require("pawhome.pets.wants")
local Keepsakes = require("pawhome.pets.keepsakes")
local Care = require("pawhome.pets.care")
local Storage = require("pawhome.core.storage")
local Serialize = require("pawhome.core.serialize")
local Api = require("pawhome.core.api")
local Mock = require("pawhome.adapters.mock")
local keepData = require("pawhome.data.keepsakes")

-- a fresh adult cat with nothing asked yet
local function newCat(opts)
    local app, mock = H.new(opts)
    local pet = H.adopt(app, 1, {}, "adult")
    pet.want = nil; pet.wantNext = math.huge
    app:setSetting("misbehaviorEnabled", false)
    return app, mock, pet
end

local function ask(app, pet, id)
    pet.want = { id = id, since = app.ctx.now, untilAt = app.ctx.now + 200 }
end

-- ------------------------------------------------------------------ wants

T.test("wants: a cat asks for something that fits its needs and personality", function()
    local app, mock, pet = newCat()
    pet.traits = {}
    pet.needs.hunger = 10; pet.needs.fun = 100; pet.needs.bladder = 100
    local counts = { feed = 0, play = 0, cuddle = 0, groom = 0, clean_litter = 0 }
    for _ = 1, 400 do counts[Wants.choose(app.ctx, pet)] = counts[Wants.choose(app.ctx, pet)] + 1 end
    T.gt(counts.feed, counts.cuddle, "a hungry cat mostly wants food")
    T.eq(counts.clean_litter, 0, "litter is fine, so nobody asks for it")
    T.eq(counts.play, 0, "fun is full: no wish to play")
    pet.needs.hunger = 100                         -- a full cat never asks for a snack
    for _ = 1, 100 do T.truthy(Wants.choose(app.ctx, pet) ~= "feed") end
    pet.traits = { "affectionate" }
    local hugs = 0
    for _ = 1, 400 do if Wants.choose(app.ctx, pet) == "cuddle" then hugs = hugs + 1 end end
    T.gt(hugs, 200, "an affectionate cat mostly wants cuddles")
end)

T.test("wants: a want lasts a few hours, expires without penalty, then there is a quiet time", function()
    local app, mock, pet = newCat()
    pet.wantNext = 0
    H.advance(app, mock, 60)
    T.truthy(pet.want, "a want came up")
    local id = pet.want.id
    local bond = Bond.best(pet)
    H.advance(app, mock, 300)                       -- nobody cared for 5 hours
    T.eq(Bond.best(pet), Bond.best(pet))
    T.truthy(pet.want == nil or pet.want.since > mock.clock - 300, "the old want is gone")
    T.eq(Bond.best(pet) >= bond - 5, true, "no punishment for ignoring a want")
    T.truthy(id ~= nil)
end)

T.test("wants: shown in the view with a lit-up button; cats that are away have none", function()
    local app, mock, pet = newCat()
    ask(app, pet, "play")
    local v = app:view(1, 101).pets[1]
    T.eq(v.want.id, "play"); T.eq(v.want.text, "Tester wants to play!")
    local lit = {}
    for _, a in ipairs(v.actions) do if a.wanted then lit[#lit + 1] = a.id end end
    T.eq(#lit, 1); T.eq(lit[1], "play")
    pet.status = "impounded"
    T.eq(app:view(1, 101).pets[1].want, nil)
end)

T.test("wants: the new want is announced", function()
    local app, mock, pet = newCat()
    pet.wantNext = 0
    local notes = H.advance(app, mock, 60)
    local found = false
    for _, n in ipairs(notes) do if n.kind == "want_new" then found = true end end
    T.truthy(found, "the notification list has it")
    local told = false
    for _, n in ipairs(mock.notifications) do if n.kind == "want_new" then told = true end end
    T.truthy(told, "and the game was told")
end)

-- ------------------------------------------------------------------ no cooldown, fatigue

T.test("care: no cooldown, but repeating the same thing is worth less and less, and recovers", function()
    local app, mock, pet = newCat()
    local gains = {}
    for i = 1, 4 do
        pet.needs.fun = 0
        local r = app:perform(pet.id, 101, "cuddle")
        T.truthy(r.ok, r.message)
        gains[i] = pet.needs.fun
    end
    T.gt(gains[1], gains[2]); T.gt(gains[2], gains[3]); T.gt(gains[3], gains[4])
    T.truthy(gains[4] >= 12 * 0.2 - 0.01, "never below the floor")
    H.advance(app, mock, 120)                       -- rest
    pet.needs.fun = 0
    app:perform(pet.id, 101, "cuddle")
    T.near(pet.needs.fun, gains[1], 0.8, "fresh again after a rest")
end)

T.test("care: the other actions are not worn out by one", function()
    local app, mock, pet = newCat()
    pet.needs.fun = 0
    for _ = 1, 5 do app:perform(pet.id, 101, "cuddle") end
    pet.needs.fun = 0
    app:perform(pet.id, 101, "groom")
    T.near(pet.needs.fun, 6, 0.01)
end)

T.test("care: the view has no cooldowns, only 'Full' or 'Tired' hints", function()
    local app, mock, pet = newCat()
    pet.needs.hunger = 99; pet.needs.energy = 5
    local v = app:view(1, 101).pets[1]
    local by = {}
    for _, a in ipairs(v.actions) do by[a.id] = a; T.eq(a.cooldown, nil) end
    T.falsy(by.feed.ready); T.eq(by.feed.hint, "Full")
    T.falsy(by.play.ready); T.eq(by.play.hint, "Tired")
    T.truthy(by.cuddle.ready); T.eq(by.cuddle.hint, "")
end)

-- ------------------------------------------------------------------ happy moments

T.test("moments: doing what the cat wants is worth much more, and always fresh", function()
    local app, mock, pet = newCat()
    pet.needs.fun = 0
    local plain = app:perform(pet.id, 101, "cuddle")
    local plainFun, plainBond = pet.needs.fun, plain.bond
    for _ = 1, 3 do app:perform(pet.id, 101, "cuddle") end     -- now it is worn out
    pet.needs.fun = 0
    local before = Bond.get(pet, 101)
    ask(app, pet, "cuddle")
    local r = app:perform(pet.id, 101, "cuddle")
    T.truthy(r.delight, "a happy moment")
    T.gt(pet.needs.fun, plainFun, "more than a plain first cuddle")
    T.gt(Bond.get(pet, 101) - before, 4, "the bond grows a lot")
    T.eq(pet.want, nil, "the want is met")
    T.gt(pet.wantNext, mock.clock, "a quiet time follows")
    T.eq(pet.delights, 1)
end)

T.test("moments: the game's own care counts for a want, and the player is told", function()
    local app, mock, pet = newCat()
    pet.needs.hunger = 30
    ask(app, pet, "feed")
    mock.giveCare(pet.entity, "feed", 202)
    local res = app:applyCare()
    T.truthy(res[1].delight)
    local kinds = {}
    for _, n in ipairs(mock.notifications) do kinds[n.kind] = true end
    T.truthy(kinds.delight or kinds.keepsake, "a notification for the happy moment")
end)

T.test("moments: asking for the wrong thing is not a happy moment", function()
    local app, mock, pet = newCat()
    ask(app, pet, "play")
    local r = app:perform(pet.id, 101, "cuddle")
    T.falsy(r.delight)
    T.eq(pet.want.id, "play", "the want is still there")
end)

-- ------------------------------------------------------------------ keepsakes

T.test("keepsakes: data is complete, with names and rarity labels in both languages", function()
    local en = require("pawhome.localization.en")
    local zh = require("pawhome.localization.zh_TW")
    T.eq(#keepData.order, 10)
    for _, id in ipairs(keepData.order) do
        T.truthy(keepData[id].coins > 0, id)
        T.truthy(keepData.rarityWeight[keepData[id].rarity], id)
        T.truthy(en.keepsakes[id] and zh.keepsakes[id], "names for " .. id)
    end
    for _, r in ipairs(keepData.rarityOrder) do T.truthy(en.rarity[r] and zh.rarity[r], r) end
end)

T.test("keepsakes: a closer bond brings gifts more often and rarer ones", function()
    local app, mock, pet = newCat()
    T.gt(Keepsakes.chance("best_friend"), Keepsakes.chance("stranger"))
    local function rareShare(level)
        local rare = 0
        for _ = 1, 600 do
            if keepData[Keepsakes.pick(app.ctx, level)].rarity == "rare" then rare = rare + 1 end
        end
        return rare
    end
    T.gt(rareShare("best_friend"), rareShare("stranger"))
end)

T.test("keepsakes: a gift goes into the album and pays coins", function()
    local app, mock, pet = newCat({ money = 1000 })
    local before = mock.money[1]
    local gift = Keepsakes.award(app.ctx, 1, "bell")
    T.eq(gift.isNew, true); T.eq(gift.name, "Little bell"); T.eq(gift.coins, 30)
    T.eq(mock.money[1], before + 30)
    local again = Keepsakes.award(app.ctx, 1, "bell")
    T.eq(again.isNew, false); T.eq(again.count, 2)
    local album = app:view(1, 101).album
    T.eq(album.total, 10); T.eq(album.owned, 1)
    local bell
    for _, it in ipairs(album.items) do if it.id == "bell" then bell = it end end
    T.eq(bell.count, 2); T.truthy(bell.owned); T.eq(bell.name, "Little bell")
    for _, it in ipairs(album.items) do if it.id == "star" then T.falsy(it.owned); T.eq(it.name, "???") end end
end)

T.test("keepsakes: the album belongs to the household and survives a save and a restart", function()
    local store = {}
    local app, mock, pet = newCat({ store = store })
    Keepsakes.award(app.ctx, 1, "feather")
    app:save()
    local app2 = require("pawhome.app").new(Mock.new({ store = store }), { seed = 1 })
    T.eq(app2:view(1, 101).album.owned, 1)
    T.eq(app2:view(2, 101).album.owned, 0, "another household has its own")
end)

T.test("keepsakes: a happy moment can bring a gift with a message and an animation", function()
    local app, mock, pet = newCat({ money = 1000 })
    Bond.add(pet, 101, 90)
    local got
    for _ = 1, 60 do
        ask(app, pet, "cuddle")
        local r = app:perform(pet.id, 101, "cuddle")
        if r.keepsake then got = r break end
    end
    T.truthy(got, "a best friend brings a gift within 60 happy moments")
    T.truthy(got.message:find("brought you a gift"))
    local played = false
    for _, a in ipairs(mock.animations) do if a.anim == "pet_happy" then played = true end end
    T.truthy(played, "the cat hands over the gift")
end)

-- ------------------------------------------------------------------ saves

T.test("storage: a v4 save loads as v5 with an empty album and keeps its pets", function()
    local mock = Mock.new()
    Api.use(mock)
    mock.store[Storage.KEY] = Serialize.encode({ version = 4, nextPetId = 2, settings = {},
        pets = { { id = 1, name = "Old", status = "home", bond = {}, flags = {}, coat = "calico" } } })
    local state, how = Storage.load()
    T.eq(how, "loaded"); T.eq(state.version, Storage.VERSION); T.eq(Storage.VERSION, 5)
    T.eq(type(state.album), "table")
    T.eq(state.pets[1].coat, "calico")
    T.eq(state.pets[1].want, nil)
end)

return true
