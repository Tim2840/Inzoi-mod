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
            os.remove(f); os.remove(f .. ".tmp")
            for i = 1, 5 do os.remove(f .. ".bak" .. i) end
        end
    end
end

local function silent() end

T.test("ue4ss: saveGet is nil before anything is saved", function()
    local a = Ue4ss.new({ pathPrefix = prefix(), print = silent })
    T.eq(a.saveGet("k"), nil)
end)

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

T.test("ue4ss: save round-trip keeps the previous version as .bak1", function()
    local p = prefix()
    local a = Ue4ss.new({ pathPrefix = p, print = silent })
    a.saveSet("k", "first")
    a.saveSet("k", "second")
    T.eq(a.saveGet("k"), "second")
    T.eq(readAll(p .. "debug.k.sav.bak1"), "first")
    cleanup(p)
end)

T.test("ue4ss: keeps exactly N backup generations, newest first", function()
    local p = prefix()
    local a = Ue4ss.new({ pathPrefix = p, print = silent, backups = 3 })
    for i = 1, 5 do a.saveSet("k", "v" .. i) end
    T.eq(readAll(p .. "debug.k.sav"), "v5")
    T.eq(readAll(p .. "debug.k.sav.bak1"), "v4")
    T.eq(readAll(p .. "debug.k.sav.bak2"), "v3")
    T.eq(readAll(p .. "debug.k.sav.bak3"), "v2")
    T.eq(readAll(p .. "debug.k.sav.bak4"), nil, "oldest generation dropped")
    cleanup(p)
end)

T.test("ue4ss: caps stay off in safe mode and follow the request otherwise", function()
    local p = prefix()
    local want = { spawn = true, animate = true }
    local safe = Ue4ss.new({ pathPrefix = p, print = silent, caps = want, safeMode = true })
    T.falsy(safe.caps.spawn); T.falsy(safe.caps.animate)
    local open = Ue4ss.new({ pathPrefix = p, print = silent, caps = want })
    T.truthy(open.caps.spawn); T.truthy(open.caps.animate); T.falsy(open.caps.moveStray)
    local default = Ue4ss.new({ pathPrefix = p, print = silent })
    for _, v in pairs(default.caps) do T.falsy(v, "all caps default to false") end
end)

T.test("ue4ss: build fingerprint and verified-build list", function()
    local p = prefix()
    local exe, list = p .. "fake.exe", p .. "verified.txt"
    local f = assert(io.open(exe, "wb")); f:write(string.rep("x", 1234)); f:close()
    T.eq(Ue4ss.buildFingerprint(exe), "size:1234")
    T.eq(Ue4ss.buildFingerprint(p .. "missing.exe"), nil)
    T.falsy(Ue4ss.isKnownBuild("size:1234", list), "no list file")
    f = assert(io.open(list, "w")); f:write("# comment\nsize:999 old build\nsize:1234 v0.11.0 verified 2026-10-20\n"); f:close()
    T.truthy(Ue4ss.isKnownBuild("size:1234", list))
    T.falsy(Ue4ss.isKnownBuild("size:12", list), "no prefix match")
    T.falsy(Ue4ss.isKnownBuild(nil, list))
    os.remove(exe); os.remove(list)
end)

T.test("ue4ss: dumpObject walks the class chain and survives missing APIs", function()
    local function fname(s) return { ToString = function() return s end } end
    local function prop(name, kind) return { GetFName = function() return fname(name) end,
        GetClass = function() return { GetFName = function() return fname(kind) end } end } end
    local base = {
        GetFullName = function() return "Class /Script/Engine.Actor" end,
        ForEachProperty = function(_, cb) cb(prop("bHidden", "BoolProperty")) end,
        -- no ForEachFunction: must not break the dump
        GetSuperStruct = function() return nil end,
    }
    local cls = {
        GetFullName = function() return "BlueprintGeneratedClass /Game/X.BP_Cat_C" end,
        ForEachProperty = function(_, cb) cb(prop("Speed", "FloatProperty")); cb(prop("Controller", "ObjectProperty")) end,
        ForEachFunction = function(_, cb) cb({ GetFName = function() return fname("Meow") end }) end,
        GetSuperStruct = function() return base end,
    }
    local obj = { Speed = 1.5, bHidden = false,
        Controller = { GetFullName = function() return "AIController /Game/X.AIC_1" end },
        GetFullName = function() return "BP_Cat_C /Game/Map.Map:PersistentLevel.BP_Cat_1" end,
        GetClass = function() return cls end }
    base.IsValid = function() return true end
    local report = prefix() .. "dump.txt"
    local ok = Ue4ss.dumpObject(obj, report, "test")
    T.truthy(ok)
    local text = readAll(report)
    os.remove(report)
    T.truthy(text:find("prop Speed : FloatProperty = 1.5", 1, true), "simple value")
    T.truthy(text:find("prop Controller : ObjectProperty -> AIController", 1, true), "object reference")
    T.truthy(text:find("func Meow", 1, true), "function listed")
    T.truthy(text:find("prop bHidden : BoolProperty = false", 1, true), "super class walked")
end)

T.test("ue4ss: falls back to .bak1 when the main file is missing", function()
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

T.test("ue4ss: slotId follows the slot function; nil slot never touches files", function()
    local p = prefix()
    T.eq(Ue4ss.new({ pathPrefix = p, print = silent }).slotId(), "debug", "default slot")
    local slot = "slotA"
    local a = Ue4ss.new({ pathPrefix = p, print = silent, slot = function() return slot end })
    T.eq(a.slotId(), "slotA")
    a.saveSet("k", "in A")
    slot = nil -- loading screen
    T.eq(a.slotId(), nil)
    T.eq(a.saveGet("k"), nil, "no read while no save is loaded")
    T.falsy(pcall(a.saveSet, "k", "ghost"), "write refused")
    slot = "slotA"
    T.eq(a.saveGet("k"), "in A", "slot A untouched")
    cleanup(p)
end)

T.test("ue4ss: the app follows a savegame switch through slotId (real files)", function()
    local p = prefix()
    local slot, minutes = "slotA", 480
    local a = Ue4ss.new({ pathPrefix = p, print = silent, debugFunds = 1000,
        slot = function() return slot end, clock = function() return minutes end })
    local app = assert(App.new(a, { seed = 7 }))
    app:tick()
    local offers = app:offers(1)
    T.truthy(app:adoptOffer(1, 1, offers[1].id, "Mochi").ok)

    slot = "slotB"
    minutes = minutes + 60
    app:tick()
    T.eq(#app.ctx.state.pets, 0, "slot B starts empty")

    slot = "slotA"
    minutes = minutes + 60
    app:tick()
    T.eq(#app.ctx.state.pets, 1, "slot A pet is back")
    T.eq(app.ctx.state.pets[1].name, "Mochi")
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
    -- Fixture: the first, second and fourth names were observed in-game on inZOI v0.10.0
    -- (build 20260915.15331), main menu, 2026-09-25. The third (Default__ object) and
    -- the fifth (Category) are synthetic negatives.
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
