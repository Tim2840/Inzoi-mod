-- Tests for the UE4SS entry point (mod/ue4ss/PawHome/Scripts/main.lua) with stubbed
-- UE4SS globals: it must tick once per game hour, swallow tick errors and register
-- working debug keys. The stubs only mirror call shapes the ZoiPets mod used on
-- inZOI v0.10.0 (LoopAsync(ms, fn), RegisterKeyBind(Key.X, {ModifierKey.Y}, fn),
-- ExecuteInGameThread(fn), print); they say nothing about v0.11.0.
local T = require("framework")

local MAIN = "mod/ue4ss/PawHome/Scripts/main.lua"

local active = {} -- environments loaded by the current test, restored by test()

local function load(opts)
    opts = opts or {}
    local env = { loops = {}, keys = {}, printed = {}, clock = opts.clock or 0 }
    local saved = {
        LoopAsync = rawget(_G, "LoopAsync"), RegisterKeyBind = rawget(_G, "RegisterKeyBind"),
        Key = rawget(_G, "Key"), ModifierKey = rawget(_G, "ModifierKey"),
        ExecuteInGameThread = rawget(_G, "ExecuteInGameThread"), ForEachUObject = rawget(_G, "ForEachUObject"),
        PAWHOME_MOD_DIR = rawget(_G, "PAWHOME_MOD_DIR"), PAWHOME_EXE = rawget(_G, "PAWHOME_EXE"),
        FindFirstOf = rawget(_G, "FindFirstOf"), print = print, time = os.time,
    }
    env.dir = opts.dir or (os.tmpname() .. "_")
    _G.PAWHOME_MOD_DIR = env.dir
    _G.PAWHOME_EXE = env.dir .. "fake.exe"
    local exe = assert(io.open(_G.PAWHOME_EXE, "wb")); exe:write(string.rep("x", 4321)); exe:close()
    if opts.verified then
        local f = assert(io.open(env.dir .. "pawhome_verified_builds.txt", "w")); f:write("size:4321 test\n"); f:close()
    end
    if opts.killed then
        local f = assert(io.open(env.dir .. "pawhome_disabled.txt", "w")); f:close()
    end
    if not opts.noDebug then -- debug mode is opt-in through this file
        local f = assert(io.open(env.dir .. "pawhome_debug.txt", "w")); f:close()
    end
    _G.FindFirstOf = opts.findFirstOf or function() return nil end
    _G.LoopAsync = function(ms, fn) env.loops[#env.loops + 1] = { ms = ms, fn = fn } end
    _G.Key = { F7 = "F7", F8 = "F8", F9 = "F9", F10 = "F10" }
    _G.ModifierKey = { SHIFT = "SHIFT" }
    _G.RegisterKeyBind = function(key, mods, fn) env.keys[key .. "+" .. tostring(mods[1])] = fn end
    _G.ExecuteInGameThread = function(fn) fn() end
    _G.ForEachUObject = function(fn) fn({ GetFullName = function() return "Class /Script/BlueClient.B1TimeManager" end }) end
    _G.print = function(s) env.printed[#env.printed + 1] = s end
    -- the debug clock counts from 2026-01-01 UTC; start exactly on a game-hour boundary
    local base = 1767225600 + 3600 * 1000
    os.time = function() return base + env.clock end

    -- a fresh engine instance per load
    for name in pairs(package.loaded) do
        if name:match("^pawhome%.") then package.loaded[name] = nil end
    end
    local ok, err = pcall(dofile, MAIN)
    active[#active + 1] = env
    env.restore = function()
        if env.restored then return end
        env.restored = true
        for k, v in pairs(saved) do
            if k == "print" then _G.print = v elseif k == "time" then os.time = v else _G[k] = v end
        end
        for _, f in ipairs({ "pawhome_debug.pawhome.save.sav", "pawhome_discovery.txt", "pawhome_dump.txt",
                             "pawhome_disabled.txt", "pawhome_debug.txt", "pawhome_verified_builds.txt", "fake.exe" }) do
            os.remove(env.dir .. f); os.remove(env.dir .. f .. ".tmp")
            for i = 1, 3 do os.remove(env.dir .. f .. ".bak" .. i) end
        end
    end
    if not ok then env.restore(); error(err, 2) end
    env.Main = package.loaded["pawhome.main"]
    env.printedText = function() return table.concat(env.printed, "") end
    return env
end

-- Wraps T.test so stubbed globals (print, os.time, UE4SS functions) are restored even
-- when an assertion fails; otherwise a failure would swallow the runner's summary.
local function test(name, fn)
    T.test(name, function()
        local ok, err = pcall(fn)
        for i = #active, 1, -1 do active[i].restore() end -- newest first
        active = {}
        if not ok then error(err, 0) end
    end)
end

test("ue4ss main: registers one loop and four Shift debug keys", function()
    local env = load()
    T.eq(#env.loops, 1)
    T.eq(env.loops[1].ms, 1000)
    T.truthy(env.keys["F7+SHIFT"] and env.keys["F8+SHIFT"] and env.keys["F9+SHIFT"] and env.keys["F10+SHIFT"], "debug keys")
    T.truthy(env.printedText():find("[PawHome] loaded", 1, true))
    env.restore()
end)

test("ue4ss main: unknown build -> banner says SAFE MODE, caps off", function()
    local env = load()
    local text = env.printedText()
    T.truthy(text:find("build size:4321 (SAFE MODE)", 1, true), "banner names the build and mode")
    T.truthy(text:find("caps spawn=false", 1, true))
    env.restore()
end)

test("ue4ss main: listed build -> banner says verified", function()
    local env = load({ verified = true })
    T.truthy(env.printedText():find("build size:4321 (verified)", 1, true))
    env.restore()
end)

test("ue4ss main: without pawhome_debug.txt there are no keys, clock or saves", function()
    local env = load({ noDebug = true })
    T.eq(next(env.keys), nil, "no debug keys")
    T.truthy(env.printedText():find("debug=false", 1, true), "banner says debug=false")
    env.loops[1].fn()
    env.clock = 3600
    env.loops[1].fn()
    T.falsy(io.open(env.dir .. "pawhome_debug.pawhome.save.sav", "rb"), "engine idles: no clock, nothing saved")
    env.restore()
end)

test("ue4ss main: the debug clock keeps counting across restarts", function()
    local first = load()
    local second
    local ok, err = pcall(function()
        first.keys["F9+SHIFT"]() -- adopt, so the restart has something to load
        first.clock = 7200 -- play for two real hours
        first.loops[1].fn()
        local before = first.Main.app.ctx.state.lastTick
        T.truthy(before, "first run ticked and saved")
        -- "restart the game" a minute later: same mod folder, wall clock keeps going.
        -- A clock that restarts from 0 at launch would now be behind `before`.
        second = load({ dir = first.dir, clock = 7260 })
        T.eq(#second.Main.app.ctx.state.pets, 1, "saved state was loaded")
        T.truthy(second.Main.app.ctx.state.lastTick >= before, "time never goes backwards after a restart")
    end)
    if second then second.restore() end -- restores first's stubs
    first.restore()                      -- restores the real globals
    if not ok then error(err, 0) end
end)

test("ue4ss main: kill switch stops everything before it starts", function()
    local env = load({ killed = true })
    T.eq(#env.loops, 0, "no loop")
    T.eq(next(env.keys), nil, "no keys")
    T.truthy(env.printedText():find("disabled by kill switch", 1, true))
    env.restore()
end)

test("ue4ss main: Shift+F7 dumps the first instance, or says none is loaded", function()
    local none = load()
    none.keys["F7+SHIFT"]()
    T.truthy(none.printedText():find("no instance loaded", 1, true))
    none.restore()

    local cls = { GetFullName = function() return "BlueprintGeneratedClass /Game/X.BP_Pet_Customize_01_C" end,
                  ForEachProperty = function() end, ForEachFunction = function() end,
                  GetSuperStruct = function() return nil end }
    local cat = { IsValid = function() return true end, GetClass = function() return cls end,
                  GetFullName = function() return "BP_Pet_Customize_01_C /Game/Map/LobbyLevel2.LobbyLevel2:PersistentLevel.BP_Pet_Customize_01_62" end }
    local env = load({ findFirstOf = function(name) return name == "BP_Pet_Customize_01_C" and cat or nil end })
    env.keys["F7+SHIFT"]()
    local f = io.open(env.dir .. "pawhome_dump.txt", "rb")
    T.truthy(f, "dump written")
    local text = f:read("a"); f:close()
    T.truthy(text:find("BP_Pet_Customize_01_62", 1, true))
    env.restore()
end)

test("ue4ss main: ticks only when the game hour changes", function()
    local env = load()
    local ticks, real = 0, env.Main.tick
    env.Main.tick = function() ticks = ticks + 1; return real() end
    local loop = env.loops[1].fn
    T.eq(loop(), false, "loop keeps running")
    loop()
    T.eq(ticks, 1, "same hour -> one tick")
    env.clock = 59 -- debug clock: 1 s = 1 game minute
    loop()
    T.eq(ticks, 1, "minute 59 is still hour 0")
    env.clock = 60
    loop()
    T.eq(ticks, 2, "hour 1 -> tick")
    env.restore()
end)

test("ue4ss main: a failing tick is logged, not raised", function()
    local env = load()
    env.Main.tick = function() error("boom") end
    T.eq(env.loops[1].fn(), false)
    T.truthy(env.printedText():find("tick error", 1, true))
    env.restore()
end)

test("ue4ss main: Shift+F9 adopts and Shift+F10 lists the pet", function()
    local env = load()
    env.keys["F9+SHIFT"]()
    T.truthy(env.printedText():find("adopt", 1, true))
    T.falsy(env.printedText():find("debug key error", 1, true))
    env.keys["F10+SHIFT"]()
    T.truthy(env.printedText():find("bond", 1, true), "pet line printed")
    env.restore()
end)

test("ue4ss main: Shift+F8 writes a discovery report", function()
    local env = load()
    env.keys["F8+SHIFT"]()
    local f = io.open(env.dir .. "pawhome_discovery.txt", "rb")
    T.truthy(f, "report written")
    local text = f:read("a"); f:close()
    T.truthy(text:find("B1TimeManager", 1, true))
    env.restore()
end)
