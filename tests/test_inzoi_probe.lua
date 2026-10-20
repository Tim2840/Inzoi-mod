-- Tests for adapters/inzoi_probe.lua with a fake `require`. The fake modules are shaped
-- like the official docs describe (functions plus Override_ hooks); they prove the report,
-- not that the real game returns these names.
local T = require("framework")
local Probe = require("pawhome.adapters.inzoi_probe")

local function has(s, needle) return s:find(needle, 1, true) ~= nil end

local function fakeRequire(modules)
    local calls = {}
    return function(name)
        calls[#calls + 1] = name
        local m = modules[name]
        if m == nil then error("module '" .. name .. "' not found") end
        return m
    end, calls
end

T.test("inzoi_probe: lists functions, hooks and fields of a loaded module", function()
    local spawner = {
        SpawnGatherableObject = function() end,
        Override_OnDayChanged = function() end,
        SpawnersByType = {},
    }
    local req = fakeRequire({ ["Systems.B2SpawnerManager"] = spawner })
    local report, summary = Probe.run({ require = req, version = "Lua 5.4" })
    T.truthy(has(report, "## Systems.B2SpawnerManager (documented): loaded"), report)
    T.truthy(has(report, "- functions: SpawnGatherableObject"))
    T.truthy(has(report, "- Override_ hooks: Override_OnDayChanged"))
    T.truthy(has(report, "- fields: SpawnersByType:table"))
    T.eq(summary.loaded[1], "Systems.B2SpawnerManager")
end)

T.test("inzoi_probe: a module that fails to load is reported, not raised", function()
    local req = fakeRequire({})
    local report, summary = Probe.run({ require = req })
    T.truthy(has(report, "## Systems.B2SpawnerManager (documented): NOT LOADED"))
    T.truthy(has(report, "## Systems.B2AdoptionManager (guessed): NOT LOADED"))
    T.eq(#summary.loaded, 0)
    T.eq(#summary.missing, #Probe.DOCUMENTED + #Probe.GUESSED)
end)

T.test("inzoi_probe: tries documented, guessed and extra paths, in that order", function()
    local req, calls = fakeRequire({})
    Probe.run({ require = req, extra = { "Components.B2HowlingComponent" } })
    T.eq(calls[1], Probe.DOCUMENTED[1])
    T.eq(calls[2], Probe.GUESSED[1])
    T.eq(calls[#calls], "Components.B2HowlingComponent")
    T.eq(#calls, #Probe.DOCUMENTED + #Probe.GUESSED + 1)
end)

T.test("inzoi_probe: follows the __index chain of class-like modules", function()
    local base = { GetEntity = function() end }
    local derived = setmetatable({ Override_RegisterSpawner = function() end }, { __index = base })
    local req = fakeRequire({ ["Systems.B2EntityManager"] = derived })
    local report = Probe.run({ require = req })
    T.truthy(has(report, "- functions: GetEntity"), report)
    T.truthy(has(report, "- Override_ hooks: Override_RegisterSpawner"))
end)

T.test("inzoi_probe: protected metatables and function __index are noted, not followed", function()
    local locked = setmetatable({ A = function() end }, { __metatable = "locked" })
    local dynamic = setmetatable({}, { __index = function() return 1 end })
    local req = fakeRequire({ ["Systems.B2TimeManager"] = locked, ["Systems.B2TimeTaskManager"] = dynamic })
    local report = Probe.run({ require = req })
    T.truthy(has(report, "protected metatable"), report)
    T.truthy(has(report, "__index is a function"))
end)

T.test("inzoi_probe: a cyclic __index chain terminates", function()
    local a, b = {}, {}
    setmetatable(a, { __index = b })
    setmetatable(b, { __index = a })
    local req = fakeRequire({ ["Systems.B2SpawnerManager"] = a })
    local _, summary = Probe.run({ require = req })
    T.eq(summary.loaded[1], "Systems.B2SpawnerManager")
end)

T.test("inzoi_probe: non-table module results are reported", function()
    local req = fakeRequire({ ["Systems.B2SpawnerManager"] = true })
    local report = Probe.run({ require = req })
    T.truthy(has(report, "loaded, returned a boolean"), report)
end)

T.test("inzoi_probe: scans globals and collects keyword hits", function()
    local G = {
        print = print,
        inzoi = { cli = { execute = function() end }, getHousehold = function() end },
        SpawnPetActor = function() end,
    }
    local req = fakeRequire({ ["Systems.B2AdoptionManager"] = { StartAdoption = function() end } })
    local report, summary = Probe.run({ require = req, G = G })
    T.truthy(has(report, "## global inzoi"), report)
    T.truthy(has(report, "- functions: getHousehold"))
    T.truthy(has(report, "- inzoi.cli functions: execute"), report)
    T.truthy(has(report, "## _G\nSpawnPetActor, inzoi, print"), report)
    local hits = table.concat(summary.hits, ",")
    T.truthy(has(hits, "Systems.B2AdoptionManager.StartAdoption"), hits)
    T.truthy(has(hits, "_G.SpawnPetActor"), hits)
    T.truthy(has(hits, "inzoi.getHousehold"), hits)
end)

T.test("inzoi_probe: never calls the functions it finds", function()
    local called = false
    local trap = function() called = true end
    local req = fakeRequire({ ["Systems.B2SpawnerManager"] = { SpawnGatherableObject = trap, Override_OnDayChanged = trap } })
    Probe.run({ require = req, G = { inzoi = { charge = trap } } })
    T.falsy(called)
end)

T.test("inzoi adapter: discover() delegates to the probe and stays read-only", function()
    local Adapter = require("pawhome.adapters.inzoi")
    local report = Adapter.discover({ "Nope.NotAModule" })
    T.truthy(has(report, "# Paw Home ModKit probe"), report)
    T.truthy(has(report, "## Nope.NotAModule (extra): NOT LOADED"))
    T.eq(Adapter.caps.spawn, false)
end)
