-- Tests for adapters/ue4ss.lua that do not need the game: file storage, slots,
-- the debug wallet, the virtual-pet flow with all caps off, and the discovery scan
-- driven by a fake object list.
local T = require("framework")
local Ue4ss = require("pawhome.adapters.ue4ss")
local App = require("pawhome.app")

local created = {}
local function prefix()
    local p = os.tmpname() .. "_"
    created[#created + 1] = p
    return p
end

local function cleanup(p)
    for _, slot in ipairs({ "debug", "slotA", "slotB" }) do
        for _, key in ipairs({ "pawhome.save", "k", "a_b_c" }) do
            local f = p .. slot .. "." .. key .. ".sav"
            os.remove(f); os.remove(f .. ".bak"); os.remove(f .. ".tmp")
        end
    end
end

local function silent() end

T.test("ue4ss: saveGet is nil before anything is saved", function()
    local a = Ue4ss.new({ pathPrefix = prefix(), print = silent })
    T.eq(a.saveGet("k"), nil)
end)

T.test("ue4ss: save round-trip keeps the previous version as .bak", function()
    local p = prefix()
    local a = Ue4ss.new({ pathPrefix = p, print = silent })
    a.saveSet("k", "first")
    a.saveSet("k", "second")
    T.eq(a.saveGet("k"), "second")
    local f = assert(io.open(p .. "debug.k.sav.bak", "rb"))
    T.eq(f:read("a"), "first")
    f:close()
    cleanup(p)
end)

T.test("ue4ss: falls back to .bak when the main file is missing", function()
    local p = prefix()
    local a = Ue4ss.new({ pathPrefix = p, print = silent })
    a.saveSet("k", "old")
    a.saveSet("k", "new")
    os.remove(p .. "debug.k.sav") -- simulate a crash between the two renames
    T.eq(a.saveGet("k"), "old")
    cleanup(p)
end)

T.test("ue4ss: save slots are kept apart and keys are sanitized", function()
    local p = prefix()
    local slot = "slotA"
    local a = Ue4ss.new({ pathPrefix = p, print = silent, slot = function() return slot end })
    a.saveSet("a/b:c", "in A")
    slot = "slotB"
    T.eq(a.saveGet("a/b:c"), nil)
    a.saveSet("a/b:c", "in B")
    slot = "slotA"
    T.eq(a.saveGet("a/b:c"), "in A")
    T.truthy(io.open(p .. "slotA.a_b_c.sav", "rb"), "sanitized file name")
    cleanup(p)
end)

T.test("ue4ss: without a clock the engine starts and idles", function()
    local p = prefix()
    local app = assert(App.new(Ue4ss.new({ pathPrefix = p, print = silent }), { seed = 7 }))
    T.eq(#app:tick(), 0)
    cleanup(p)
end)

T.test("ue4ss: virtual-pet adoption with the debug wallet, survives a restart", function()
    local p = prefix()
    local minutes = 8 * 60
    local function newAdapter()
        return Ue4ss.new({ pathPrefix = p, print = silent, debugFunds = 1000, clock = function() return minutes end })
    end
    local a = newAdapter()
    local app = assert(App.new(a, { seed = 7 }))
    app:tick()
    local offers = app:offers(1)
    T.gt(#offers, 0, "shelter has offers")
    local r = app:adoptOffer(1, 1, offers[1].id, "Mochi")
    T.truthy(r.ok, r.message)
    T.eq(a.wallet, 1000 - offers[1].fee, "fee charged")
    minutes = minutes + 120
    app:tick()

    local app2 = assert(App.new(newAdapter(), { seed = 7 }))
    T.eq(#app2.ctx.state.pets, 1, "pet restored from file")
    T.eq(app2.ctx.state.pets[1].name, "Mochi")
    cleanup(p)
end)

T.test("ue4ss: adoption is refused when no money source exists", function()
    local p = prefix()
    local app = assert(App.new(Ue4ss.new({ pathPrefix = p, print = silent, clock = function() return 480 end }), { seed = 7 }))
    local offers = app:offers(1)
    local r = app:adoptOffer(1, 1, offers[1].id, "Mochi")
    T.falsy(r.ok)
    T.eq(r.reason, "no_funds")
    cleanup(p)
end)

T.test("ue4ss: log sink and notify go to the injected printer", function()
    local lines = {}
    local a = Ue4ss.new({ pathPrefix = prefix(), print = function(s) lines[#lines + 1] = s end })
    a.logSink("info", "[PawHome][info] hello")
    a.notify(1, "hungry", "Mochi is hungry")
    T.eq(#lines, 2)
    T.truthy(lines[2]:find("Mochi is hungry", 1, true))
end)

T.test("ue4ss: discovery groups classes and level instances only", function()
    local objects = {
        "BlueprintGeneratedClass /Game/Characters/Pets/Operator/OP001/Mesh/BP_Pet_Customize_01.BP_Pet_Customize_01_C",
        "BP_Pet_Customize_01_C /Game/Map/LobbyLevel2.LobbyLevel2:PersistentLevel.BP_Pet_Customize_01_62",
        "BP_Pet_Customize_01_C /Game/Characters/Pets/Default__BP_Pet_Customize_01_C", -- not in a level
        "Class /Script/BlueClient.B1TimeManager",
        "Class /Script/Engine.Category", -- must not match "cat"
    }
    local function forEach(fn)
        for _, name in ipairs(objects) do fn({ GetFullName = function() return name end }) end
    end
    local report = prefix() .. "discovery.txt"
    local ok, scanned = Ue4ss.discover(report, "test", forEach)
    T.truthy(ok)
    T.eq(scanned, #objects)
    local f = assert(io.open(report, "rb"))
    local text = f:read("a")
    f:close()
    os.remove(report)
    T.truthy(text:find("## animal - classes (1)", 1, true), "one animal class")
    T.truthy(text:find("## animal - level instances (1)", 1, true), "only the level instance")
    T.truthy(text:find("B1TimeManager", 1, true), "time group")
    T.falsy(text:find("Engine.Category", 1, true), "Category is not a cat")
end)

for _, p in ipairs(created) do os.remove(p:sub(1, -2)) end -- os.tmpname may create the base file
