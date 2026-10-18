-- Tests for the UE4SS entry point (mod/ue4ss/PawHome/Scripts/main.lua) with stubbed
-- UE4SS globals: it must tick once per game hour, swallow tick errors and register
-- working debug keys. The stubs only mirror call shapes the ZoiPets mod used on
-- inZOI v0.10.0 (LoopAsync(ms, fn), RegisterKeyBind(Key.X, {ModifierKey.Y}, fn),
-- ExecuteInGameThread(fn), print); they say nothing about v0.11.0.
local T = require("framework")

local MAIN = "mod/ue4ss/PawHome/Scripts/main.lua"

local function load(opts)
    opts = opts or {}
    local env = { loops = {}, keys = {}, printed = {}, clock = 0 }
    local saved = {
        LoopAsync = rawget(_G, "LoopAsync"), RegisterKeyBind = rawget(_G, "RegisterKeyBind"),
        Key = rawget(_G, "Key"), ModifierKey = rawget(_G, "ModifierKey"),
        ExecuteInGameThread = rawget(_G, "ExecuteInGameThread"), ForEachUObject = rawget(_G, "ForEachUObject"),
        PAWHOME_MOD_DIR = rawget(_G, "PAWHOME_MOD_DIR"), print = print, time = os.time,
    }
    env.dir = os.tmpname() .. "_"
    _G.PAWHOME_MOD_DIR = env.dir
    _G.LoopAsync = function(ms, fn) env.loops[#env.loops + 1] = { ms = ms, fn = fn } end
    _G.Key = { F8 = "F8", F9 = "F9", F10 = "F10" }
    _G.ModifierKey = { SHIFT = "SHIFT" }
    _G.RegisterKeyBind = function(key, mods, fn) env.keys[key .. "+" .. tostring(mods[1])] = fn end
    _G.ExecuteInGameThread = function(fn) fn() end
    _G.ForEachUObject = function(fn) fn({ GetFullName = function() return "Class /Script/BlueClient.B1TimeManager" end }) end
    _G.print = function(s) env.printed[#env.printed + 1] = s end
    local base = os.time()
    os.time = function() return base + env.clock end

    -- a fresh engine instance per load
    for name in pairs(package.loaded) do
        if name:match("^pawhome%.") then package.loaded[name] = nil end
    end
    local ok, err = pcall(dofile, MAIN)
    env.restore = function()
        for k, v in pairs(saved) do
            if k == "print" then _G.print = v elseif k == "time" then os.time = v else _G[k] = v end
        end
        for _, f in ipairs({ "pawhome_debug.pawhome.save.sav", "pawhome_discovery.txt" }) do
            os.remove(env.dir .. f); os.remove(env.dir .. f .. ".bak"); os.remove(env.dir .. f .. ".tmp")
        end
    end
    if not ok then env.restore(); error(err, 2) end
    env.Main = package.loaded["pawhome.main"]
    env.printedText = function() return table.concat(env.printed, "") end
    return env
end

T.test("ue4ss main: registers one loop and three Shift debug keys", function()
    local env = load()
    T.eq(#env.loops, 1)
    T.eq(env.loops[1].ms, 1000)
    T.truthy(env.keys["F8+SHIFT"] and env.keys["F9+SHIFT"] and env.keys["F10+SHIFT"], "debug keys")
    T.truthy(env.printedText():find("[PawHome] loaded", 1, true))
    env.restore()
end)

T.test("ue4ss main: ticks only when the game hour changes", function()
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

T.test("ue4ss main: a failing tick is logged, not raised", function()
    local env = load()
    env.Main.tick = function() error("boom") end
    T.eq(env.loops[1].fn(), false)
    T.truthy(env.printedText():find("tick error", 1, true))
    env.restore()
end)

T.test("ue4ss main: Shift+F9 adopts and Shift+F10 lists the pet", function()
    local env = load()
    env.keys["F9+SHIFT"]()
    T.truthy(env.printedText():find("adopt", 1, true))
    T.falsy(env.printedText():find("debug key error", 1, true))
    env.keys["F10+SHIFT"]()
    T.truthy(env.printedText():find("bond", 1, true), "pet line printed")
    env.restore()
end)

T.test("ue4ss main: Shift+F8 writes a discovery report", function()
    local env = load()
    env.keys["F8+SHIFT"]()
    local f = io.open(env.dir .. "pawhome_discovery.txt", "rb")
    T.truthy(f, "report written")
    local text = f:read("a"); f:close()
    T.truthy(text:find("B1TimeManager", 1, true))
    env.restore()
end)
