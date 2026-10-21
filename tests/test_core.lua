local T = require("framework")
local Serialize = require("pawhome.core.serialize")
local Rng = require("pawhome.core.rng")
local I18n = require("pawhome.core.i18n")
local Util = require("pawhome.core.util")
local Storage = require("pawhome.core.storage")
local Api = require("pawhome.core.api")
local Mock = require("pawhome.adapters.mock")
local traitData = require("pawhome.data.traits")
local actions = require("pawhome.data.actions")
local needs = require("pawhome.data.needs")
local stages = require("pawhome.data.stages")
local habits = require("pawhome.data.habits")
local moods = require("pawhome.data.moods")

T.test("serialize: round trip keeps nested data", function()
    local v = {
        a = 1, b = 2.5, c = "he said \"hi\"\nnext line", d = true, e = { 1, 2, 3, { x = "y" } },
        ["weird key"] = "z", [7] = "seven", name = "麻糬",
    }
    local back = assert(Serialize.decode(Serialize.encode(v)))
    T.eq(back.a, 1); T.near(back.b, 2.5, 1e-9); T.eq(back.c, v.c); T.eq(back.d, true)
    T.eq(back.e[4].x, "y"); T.eq(back["weird key"], "z"); T.eq(back[7], "seven"); T.eq(back.name, "麻糬")
end)

T.test("serialize: keywords as keys survive", function()
    local back = assert(Serialize.decode(Serialize.encode({ ["end"] = 1, ["for"] = 2 })))
    T.eq(back["end"], 1); T.eq(back["for"], 2)
end)

T.test("serialize: a tampered save cannot run code", function()
    T.falsy(Serialize.decode('os.execute("echo hacked")'))
    T.falsy(Serialize.decode('{a = os.getenv("HOME")}'))
    T.falsy(Serialize.decode('(function() while true do end end)'))
    T.falsy(Serialize.decode(''))
end)

T.test("rng: same seed gives the same sequence and state can be restored", function()
    local a, b = Rng.new(99), Rng.new(99)
    for _ = 1, 50 do T.eq(a:next(), b:next()) end
    local state = a:getState()
    local x = a:next()
    a:setState(state)
    T.eq(a:next(), x)
end)

T.test("rng: int stays in range and covers it", function()
    local r, seen = Rng.new(5), {}
    for _ = 1, 2000 do
        local n = r:int(1, 6)
        T.truthy(n >= 1 and n <= 6)
        seen[n] = true
    end
    for i = 1, 6 do T.truthy(seen[i], "never rolled " .. i) end
end)

T.test("rng: weighted respects weights", function()
    local r, counts = Rng.new(7), { a = 0, b = 0 }
    for _ = 1, 4000 do
        local k = r:weighted({ "a", "b" }, function(x) return x == "a" and 9 or 1 end)
        counts[k] = counts[k] + 1
    end
    T.gt(counts.a, counts.b * 5)
end)

T.test("util: character length counts Chinese characters once", function()
    T.eq(Util.charLength("麻糬"), 2)
    T.eq(Util.charLength("Mochi"), 5)
end)

T.test("i18n: English and Traditional Chinese have exactly the same keys", function()
    local en, zh = I18n.keys("en"), I18n.keys("zh-TW")
    local seen = {}
    for _, k in ipairs(en) do seen[k] = true end
    for _, k in ipairs(zh) do T.truthy(seen[k], "zh-TW has extra key " .. k); seen[k] = nil end
    for k in pairs(seen) do error("zh-TW is missing key " .. k) end
end)

T.test("i18n: placeholders match between languages", function()
    local function placeholders(s)
        local out = {}
        for name in s:gmatch("{([%w_]+)}") do out[#out + 1] = name end
        table.sort(out)
        return table.concat(out, ",")
    end
    for _, key in ipairs(I18n.keys("en")) do
        I18n.setLocale("en"); local en = I18n.t(key)
        I18n.setLocale("zh-TW"); local zh = I18n.t(key)
        T.truthy(zh ~= "", key .. " is empty in zh-TW")
        T.eq(placeholders(zh), placeholders(en), "placeholders differ for " .. key)
    end
    I18n.setLocale("en")
end)

T.test("i18n: every piece of game data has a name in both languages", function()
    for _, lang in ipairs({ "en", "zh-TW" }) do
        I18n.setLocale(lang)
        for id in pairs(traitData) do
            T.truthy(I18n.has("traits." .. id .. ".name"), lang .. " trait " .. id)
            T.truthy(I18n.has("traits." .. id .. ".desc"), lang .. " trait desc " .. id)
        end
        for _, id in ipairs(actions.order) do
            T.truthy(I18n.has("actions." .. id .. ".name"), lang .. " action " .. id)
            T.truthy(I18n.has("actions." .. id .. ".desc"), lang .. " action desc " .. id)
        end
        for _, id in ipairs(needs.order) do T.truthy(I18n.has("needs." .. id), lang .. " need " .. id) end
        for _, s in ipairs(stages) do T.truthy(I18n.has("stages." .. s.id), lang .. " stage " .. s.id) end
        for _, id in ipairs(habits.order) do
            T.truthy(I18n.has("habits." .. id), lang .. " habit " .. id)
            T.truthy(I18n.has("msg.misbehave_" .. id), lang .. " misbehave " .. id)
        end
        for id in pairs(moods) do T.truthy(I18n.has("moods." .. id), lang .. " mood " .. id) end
        for _, lvl in ipairs({ "stranger", "acquainted", "friend", "best_friend" }) do
            T.truthy(I18n.has("bond." .. lvl), lang .. " bond " .. lvl)
        end
    end
    I18n.setLocale("en")
end)

T.test("i18n: locale detection and fallback", function()
    T.eq(I18n.normalize("zh_TW"), "zh-TW")
    T.eq(I18n.normalize("zh-Hant"), "zh-TW")
    T.eq(I18n.normalize("en-US"), "en")
    T.eq(I18n.normalize("ko-KR"), "en")
    I18n.setLocale("en")
    T.eq(I18n.t("does.not.exist"), "does.not.exist")
    T.eq(I18n.t("msg.adopted", { name = "Mochi" }), "Mochi has joined your household!")
    I18n.setLocale("zh-TW")
    T.eq(I18n.t("msg.adopted", { name = "麻糬" }), "麻糬 加入了你的家庭！")
    I18n.setLocale("en")
end)

T.test("trait data: conflicts are symmetric and reference real traits", function()
    for id, def in pairs(traitData) do
        for _, other in ipairs(def.conflicts or {}) do
            T.truthy(traitData[other], id .. " conflicts with unknown " .. other)
            T.truthy(Util.contains(traitData[other].conflicts or {}, id), id .. "/" .. other .. " conflict is one-sided")
        end
    end
end)

T.test("storage: new, round trip, corrupt and newer saves", function()
    local mock = Mock.new()
    Api.use(mock)
    local state, how = Storage.load()
    T.eq(how, "new")
    state.nextPetId = 9
    Storage.save(state)
    local again, how2 = Storage.load()
    T.eq(how2, "loaded"); T.eq(again.nextPetId, 9)

    mock.store[Storage.KEY] = "not a table {{{"
    local fresh, how3 = Storage.load()
    T.eq(how3, "corrupt"); T.eq(fresh.nextPetId, 1)

    mock.store[Storage.KEY] = Serialize.encode({ version = 999 })
    local none, why = Storage.load()
    T.eq(none, nil); T.eq(why, "newer")
end)

T.test("storage: settings added in newer releases are filled in", function()
    local mock = Mock.new()
    Api.use(mock)
    mock.store[Storage.KEY] = Serialize.encode({ version = 1, nextPetId = 3, pets = {}, settings = { lifeScale = 2 } })
    local state = Storage.load()
    T.eq(state.settings.lifeScale, 2)
    T.eq(state.settings.agingEnabled, true)
end)

T.test("storage: a v2 save loads as v3 with the illness settings filled in", function()
    local mock = Mock.new()
    Api.use(mock)
    mock.store[Storage.KEY] = Serialize.encode({ version = 2, nextPetId = 2, settings = { vetFee = 99 },
        pets = { { id = 1, name = "Old", status = "home", bond = {}, flags = {} } } })
    local state, how = Storage.load()
    T.eq(how, "loaded"); T.eq(state.version, 3)
    T.eq(state.settings.illnessEnabled, true)
    T.eq(state.settings.vetFee, 99, "an existing value is kept")
    T.eq(state.pets[1].illness, nil)
end)

T.test("storage: a v1 save (run-away pets) is migrated to the shelter model", function()
    local mock = Mock.new()
    Api.use(mock)
    mock.store[Storage.KEY] = Serialize.encode({
        version = 1, nextPetId = 3, lastTick = 500,
        settings = { neglectRunaway = false, lifeScale = 2 },
        pets = {
            { id = 1, name = "Gone", status = "away", awaySince = 100, entity = 7, bond = {}, flags = {} },
            { id = 2, name = "Home", status = "home", bond = {}, flags = {} },
        },
    })
    local state, how = Storage.load()
    T.eq(how, "loaded"); T.eq(state.version, Storage.VERSION)
    T.eq(state.settings.animalControl, false, "the old toggle should carry over")
    T.eq(state.settings.neglectRunaway, nil)
    T.eq(state.settings.lifeScale, 2)
    T.eq(state.settings.redeemFee, 200, "new settings get defaults")
    T.eq(state.pets[1].status, "impounded"); T.eq(state.pets[1].impoundedAt, 100)
    T.eq(state.pets[1].awaySince, nil); T.eq(state.pets[1].entity, nil)
    T.eq(state.pets[2].status, "home")
end)

T.test("storage: a damaged current save falls back to the newest readable older generation", function()
    local mock = Mock.new()
    Api.use(mock)
    for n = 5, 8 do
        local st = Storage.default(); st.nextPetId = n
        Storage.save(st)
    end                                                  -- main = 8, generations: 7, 6, 5
    T.eq(Storage.load().nextPetId, 8)
    mock.store[Storage.KEY] = "garbage {{{"
    local state, how = Storage.load()
    T.eq(how, "restored"); T.eq(state.nextPetId, 7)
    -- the newest generation is damaged too: take the next one
    mock.generations[Storage.KEY][1] = "also garbage"
    state, how = Storage.load()
    T.eq(how, "restored"); T.eq(state.nextPetId, 6)
end)

T.test("storage: damaged save and no readable backup starts fresh (and says so)", function()
    local mock = Mock.new()
    Api.use(mock)
    mock.store[Storage.KEY] = "garbage {{{"
    local state, how = Storage.load()
    T.eq(how, "corrupt"); T.eq(state.nextPetId, 1)
    for n = 1, 3 do mock.generations[Storage.KEY] = { "bad", "worse", "worst" } end
    state, how = Storage.load()
    T.eq(how, "corrupt")
end)

T.test("storage: an adapter without saveGetBackup behaves exactly as before", function()
    local mock = Mock.new()
    mock.saveGetBackup = nil
    Api.use(mock)
    mock.store[Storage.KEY] = "garbage {{{"
    local _, how = Storage.load()
    T.eq(how, "corrupt")
end)

T.test("storage: the app keeps its pets when the main save is damaged", function()
    local H = require("helpers")
    local App = require("pawhome.app")
    local app, m = H.new({ money = 5000 })
    H.adopt(app, 1)
    H.advance(app, m, 3 * 60)                            -- several saves, so older generations exist
    m.store[Storage.KEY] = "garbage {{{"
    local again = assert(App.new(m))
    T.eq(#again.ctx.state.pets, 1, "restored from a backup generation")
end)

T.test("api: a failing adapter call never escapes", function()
    local mock = Mock.new()
    mock.notify = function() error("boom") end
    Api.use(mock)
    T.eq(Api.notify(1, "x", "y"), false)
end)

T.test("api: adapter without required functions is rejected", function()
    local ok, err = Api.use({})
    T.falsy(ok); T.truthy(err:find("now"))
    Api.use(Mock.new())
end)

return true
