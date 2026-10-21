-- Fixed coats (docs/research/fixed-coat.md): chosen at adoption, kept in the save, sent to
-- the game thread, applied to every cat actor of ours, migrated for old saves.
local T = require("framework")
local H = require("helpers")
local Mock = require("pawhome.adapters.mock")
local Api = require("pawhome.core.api")
local Storage = require("pawhome.core.storage")
local Serialize = require("pawhome.core.serialize")
local Coats = require("pawhome.pets.coats")
local CoatKeeper = require("pawhome.adapters.inzoi_coats")
local coatData = require("pawhome.data.coats")

local function textureOf(id) return coatData[id].texture end

-- ------------------------------------------------------------------ data

T.test("coats: every coat has a texture, a weight and a name in both languages", function()
    local en = require("pawhome.localization.en")
    local zh = require("pawhome.localization.zh_TW")
    T.eq(#coatData.order, 4)
    for _, id in ipairs(coatData.order) do
        T.truthy(Coats.valid(id), id)
        T.truthy(type(coatData[id].texture) == "string" and coatData[id].texture:match("^[%w_]+$"), id)
        T.gt(coatData[id].weight, 0)
        T.truthy(en.coats[id] and zh.coats[id], "names for " .. id)
    end
    T.falsy(Coats.valid("order")); T.falsy(Coats.valid("purple")); T.falsy(Coats.valid(nil))
end)

-- ------------------------------------------------------------------ adoption

T.test("coats: shelter offers come with a coat and the list to choose from", function()
    local app = H.new({ seed = 11 })
    local seen = {}
    for _ = 1, 30 do
        for _, o in ipairs(app:offers(1, true)) do
            T.truthy(Coats.valid(o.coat), "offer coat")
            T.truthy(o.coatLabel ~= "" and o.coatLabel ~= o.coat, "localised label")
            T.eq(#o.coats, 4)
            seen[o.coat] = true
        end
    end
    for _, id in ipairs(coatData.order) do T.truthy(seen[id], "offers use every coat, missing " .. id) end
end)

T.test("coats: adopting keeps the offer's coat unless the player picks another", function()
    local app, mock = H.new({ money = 1000 })
    local offers = app:offers(1)
    T.truthy(app:adoptOffer(1, 101, offers[1].id, "Mochi").ok)
    local first = app.ctx.state.pets[1]
    T.eq(first.coat, offers[1].coat)
    T.eq(mock.entities[first.entity].spec.coat, first.coat, "the game is told the coat when the cat is placed")

    local pick = offers[2].coat == "calico" and "tuxedo" or "calico"
    T.truthy(app:adoptOffer(1, 101, offers[2].id, "Bean", pick).ok)
    T.eq(app.ctx.state.pets[2].coat, pick)
    T.eq(app:view(1, 101).pets[2].coat, pick)
    T.eq(app:view(1, 101).pets[2].coatLabel, require("pawhome.localization.en").coats[pick])
end)

T.test("coats: an unknown coat is refused before any money is taken", function()
    local app, mock = H.new({ money = 1000 })
    local offers = app:offers(1)
    local r = app:adoptOffer(1, 101, offers[1].id, "Mochi", "purple")
    T.falsy(r.ok); T.eq(r.reason, "bad_coat"); T.eq(mock.money[1], 1000)
    T.eq(#app.ctx.state.pets, 0)
    T.truthy(r.message ~= "" and not r.message:find("fail.bad_coat", 1, true), "localised message")
end)

T.test("coats: an adopted stray gets the coat the player chose, or a random one", function()
    local strays = { { id = "s1", ref = "streetcat", stage = "adult" }, { id = "s2", ref = "other", stage = "adult" } }
    local app = H.new({ strays = strays, caps = { spawn = true } })
    T.truthy(app:adoptStray(1, 101, "s1", "Tiger", "orange_tabby").ok)
    T.eq(app.ctx.state.pets[1].coat, "orange_tabby")
    T.truthy(app:adoptStray(1, 101, "s2", "Smoke").ok)
    T.truthy(Coats.valid(app.ctx.state.pets[2].coat))
    T.eq(app:adoptStray(1, 101, "s1", "Again", "purple").reason, "bad_coat")
end)

T.test("coats: the game is told the coats of the pets at home, and only those", function()
    local app, mock = H.new({ money = 5000 })
    local offers = app:offers(1)
    T.truthy(app:adoptOffer(1, 101, offers[1].id, "Mochi", "calico").ok)
    T.truthy(app:adoptOffer(1, 101, offers[2].id, "Bean", "tuxedo").ok)
    local list = mock.coatList
    T.eq(#list, 2)
    local byRef = {}
    for _, c in ipairs(list) do byRef[c.ref] = c end
    local mochi, bean = app.ctx.state.pets[1], app.ctx.state.pets[2]
    T.eq(byRef[mochi.entity].texture, textureOf("calico"))
    T.eq(byRef[bean.entity].coat, "tuxedo")
    -- a pet taken to the shelter no longer has a cat in the world
    bean.status = "impounded"
    H.advance(app, mock, 60)
    T.eq(#mock.coatList, 1)
    T.eq(mock.coatList[1].ref, mochi.entity)
end)

T.test("coats: a cat placed again (e.g. after it went missing) keeps its coat", function()
    local app, mock = H.new()
    local pet = H.adopt(app, 1)
    local coat = pet.coat
    mock.entities[pet.entity] = nil          -- the game lost the cat
    H.advance(app, mock, 6 * 60)
    T.truthy(pet.entity ~= nil and mock.entities[pet.entity] ~= nil, "placed again")
    T.eq(mock.entities[pet.entity].spec.coat, coat)
    T.eq(pet.coat, coat)
end)

-- ------------------------------------------------------------------ old saves

T.test("coats: a v3 save gets a coat for every pet and shelter offer", function()
    local mock = Mock.new()
    Api.use(mock)
    mock.store[Storage.KEY] = Serialize.encode({ version = 3, nextPetId = 6, settings = {},
        pets = {
            { id = 1, name = "A", status = "home", bond = {}, flags = {} },
            { id = 2, name = "B", status = "home", bond = {}, flags = {} },
            { id = 5, name = "E", status = "impounded", bond = {}, flags = {} },
        },
        offers = { ["1"] = { day = 0, list = { { id = 7, name = "O", stage = "adult", traits = {}, fee = 150 } } } },
    })
    local state, how = Storage.load()
    T.eq(how, "loaded"); T.eq(state.version, Storage.VERSION)
    T.eq(state.pets[1].coat, "orange_tabby")
    T.eq(state.pets[2].coat, "brown_tabby")
    T.eq(state.pets[3].coat, "orange_tabby", "handed out in turn by pet id")
    T.truthy(Coats.valid(state.offers["1"].list[1].coat))
end)

T.test("coats: a pet that already has a coat keeps it through the migration", function()
    local mock = Mock.new()
    Api.use(mock)
    mock.store[Storage.KEY] = Serialize.encode({ version = 3, nextPetId = 2, settings = {},
        pets = { { id = 1, name = "A", status = "home", coat = "tuxedo", bond = {}, flags = {} } } })
    T.eq(Storage.load().pets[1].coat, "tuxedo")
end)

-- ------------------------------------------------------------------ game thread (B1)

local function fakeB1(cfg)
    local p = { cfg = cfg or {}, applied = {}, fail = {} }
    function p.actorEntityId(actor) return actor.eid end
    function p.applyCoat(actor, texture)
        if p.fail[actor.eid] then error("no material") end
        p.applied[#p.applied + 1] = actor.eid .. "=" .. texture
        actor.texture = texture
        return true
    end
    function p.cfgSave(s, k, v) p.cfg[s .. "/" .. k] = v return true end
    function p.cfgLoad(s, k) return p.cfg[s .. "/" .. k] end
    return p
end

T.test("coats (B1): the list is parsed and anything odd in it is skipped", function()
    local map = CoatKeeper.parse("109546=Void_Cat_001_D;12=Void_Cat_001_003_D;bad;=x;7=;8=a b")
    T.eq(map[109546], "Void_Cat_001_D"); T.eq(map[12], "Void_Cat_001_003_D")
    T.eq(map[7], nil)
    T.eq(next(CoatKeeper.parse("")), nil); T.eq(next(CoatKeeper.parse(nil)), nil)
end)

T.test("coats (B1): a cat actor gets its coat when it appears and when the list arrives", function()
    local p = fakeB1()
    local keeper = CoatKeeper.new(p)
    local ours, city = { eid = 109546 }, { eid = 89129 }
    keeper.onActor(ours); keeper.onActor(city)
    T.eq(#p.applied, 0, "nothing known yet")
    keeper.setList("109546=Void_Cat_001_002_D")
    T.eq(ours.texture, "Void_Cat_001_002_D")
    T.eq(city.texture, nil, "city cats keep the game's coat")
    keeper.setList("109546=Void_Cat_001_002_D")
    T.eq(#p.applied, 1, "not set twice")
    -- the game created the actor again (load, coming back into view): set it again
    keeper.onActorEnd(ours)
    local again = { eid = 109546 }
    keeper.onActor(again)
    T.eq(again.texture, "Void_Cat_001_002_D")
end)

T.test("coats (B1): right after a load the last list is used until B2 sends the new one", function()
    local cfg = {}
    local first = CoatKeeper.new(fakeB1(cfg))
    first.setList("5=Void_Cat_001_003_D")
    local p = fakeB1(cfg)                       -- the next game session
    local keeper = CoatKeeper.new(p)
    local cat = { eid = 5 }
    keeper.onActor(cat)
    T.eq(cat.texture, "Void_Cat_001_003_D", "coloured from the cached list at once")
end)

T.test("coats (B1): a cat whose material cannot be set does not break the others", function()
    local p = fakeB1()
    p.fail[1] = true
    local keeper = CoatKeeper.new(p)
    local a, b = { eid = 1 }, { eid = 2 }
    keeper.onActor(a); keeper.onActor(b)
    keeper.setList("1=Void_Cat_001_D;2=Void_Cat_001_D")
    T.eq(b.texture, "Void_Cat_001_D")
    T.eq(a.texture, nil)
end)
