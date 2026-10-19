-- UE4SS entry point for Paw Home. Installed as:
--   <inZOI>\BlueClient\Binaries\Win64\ue4ss\Mods\PawHome\Scripts\main.lua
-- with the engine copied next to it as Scripts\pawhome\ (see scripts\install-ue4ss.ps1).
--
-- Everything game-specific lives in pawhome/adapters/ue4ss.lua; this file only wires
-- it up, drives the hourly tick and registers debug keys.
-- UE4SS globals used here (print, LoopAsync, ExecuteInGameThread, RegisterKeyBind,
-- Key, ModifierKey) were VERIFIED to load on inZOI v0.10.0 via the ZoiPets mod;
-- the Shift+F-key bindings themselves have NOT been pressed in-game yet, and
-- FindFirstOf (Shift+F7), the spawn probe (Shift+F6: StaticFindObject, LoadAsset,
-- World:SpawnActor, K2_GetActorLocation, K2_DestroyActor) and our ClientRestart hook
-- callback (auto-explore) have never run in inZOI.

local MOD_VERSION = "0.1.0-dev"
-- Debug mode is OFF unless pawhome_debug.txt exists in the mod folder (same mechanism
-- as the kill switch). Off = no clock (the engine idles), no wallet, no debug keys.
-- Until the real game clock is found (probe V3) the debug clock runs
-- 1 real second = 1 game minute, so 1 real minute = 1 game hour. It counts from a
-- fixed epoch so it keeps going up across restarts (real time while the game was
-- closed also counts; the engine caps catch-up at catchupCapHours).
local DEBUG_MINUTES_PER_SECOND = 1
local DEBUG_EPOCH = 1767225600 -- 2026-01-01 00:00:00 UTC
local DEBUG_FUNDS = 1000
-- Household / Zoi ids are unknown until the in-save probes; constants for now.
local HOUSEHOLD, ZOI = 1, 1
-- Caps to enable on a verified build. All off: nothing has in-game evidence yet.
local REQUESTED_CAPS = {}
-- Classes Shift+F7 dumps (first instance found). Only the lobby cat is known so far;
-- B1TimeManager is the game-clock candidate from the v0.10.0 main-menu scan (V3).
local DUMP_CLASSES = { "BP_Pet_Customize_01_C", "B1TimeManager" }
-- M1-3b: class Shift+F6 spawns. Override with the first line of pawhome_spawn_class.txt
-- (e.g. a stray-cat class found by M1-3a) without editing code.
local DEFAULT_SPAWN_CLASS = "/Game/Characters/Pets/Operator/OP001/Mesh/BP_Pet_Customize_01.BP_Pet_Customize_01_C"
-- M1-3a: with pawhome_autoexplore.txt present, run discovery + dumps this long after
-- each PlayerController restart (map load), at most AUTO_EXPLORE_MAX times per session.
local AUTO_EXPLORE_DELAY_MS = 60000
local AUTO_EXPLORE_MAX = 3
local MAX_ACTOR_DUMPS = 3

local scriptsDir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or "./"
package.path = scriptsDir .. "?.lua;" .. package.path
-- tests/test_ue4ss_main.lua sets PAWHOME_MOD_DIR / PAWHOME_EXE to temp paths
local modDir = rawget(_G, "PAWHOME_MOD_DIR") or scriptsDir:gsub("Scripts[\\/]$", "")
local exePath = rawget(_G, "PAWHOME_EXE") or (modDir .. "..\\..\\..\\inZOI-Win64-Shipping.exe")

local function log(msg) print("[PawHome] " .. msg .. "\n") end

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() end
    return f ~= nil
end

-- Kill switch: create pawhome_disabled.txt in the mod folder to stop the mod
-- without uninstalling it (no loop, no keys, saves untouched).
if exists(modDir .. "pawhome_disabled.txt") then
    log("disabled by kill switch (pawhome_disabled.txt); nothing started")
    return
end

local DEBUG = exists(modDir .. "pawhome_debug.txt")

local Ue4ss = require("pawhome.adapters.ue4ss")
local Main = require("pawhome.main")

-- Safe mode: caps stay off unless this exact build is listed as verified.
local fingerprint = Ue4ss.buildFingerprint(exePath)
local knownBuild = Ue4ss.isKnownBuild(fingerprint, modDir .. "pawhome_verified_builds.txt")

local adapter = Ue4ss.new({
    pathPrefix = modDir .. "pawhome_",
    clock = DEBUG and function() return (os.time() - DEBUG_EPOCH) * DEBUG_MINUTES_PER_SECOND end or nil,
    debugFunds = DEBUG and DEBUG_FUNDS or nil,
    caps = REQUESTED_CAPS,
    safeMode = not knownBuild,
})

-- Startup banner: everything a bug report needs in one line.
local capList = {}
for _, k in ipairs({ "spawn", "moveStray", "buffs", "animate" }) do
    capList[#capList + 1] = k .. "=" .. tostring(adapter.caps[k])
end
log(("v%s | %s | build %s (%s) | caps %s | debug=%s"):format(
    MOD_VERSION, _VERSION, fingerprint or "unknown",
    knownBuild and "verified" or "SAFE MODE", table.concat(capList, ","), tostring(DEBUG)))

local app = Main.start(adapter)
if not app then
    log("failed to start, see errors above")
    return
end
log("loaded (save prefix: " .. modDir .. "pawhome_)")

-- Tick once per game hour; the engine catches up on longer gaps by itself.
local lastHour = nil
LoopAsync(1000, function()
    local ok, err = pcall(function()
        local now = adapter.now()
        if now == nil then return end
        local hour = math.floor(now / 60)
        if hour ~= lastHour then
            lastHour = hour
            for _, n in ipairs(Main.tick()) do log("note: " .. tostring(n.text or n.kind)) end
        end
    end)
    if not ok then log("tick error: " .. tostring(err)) end
    return false -- keep looping
end)

if DEBUG then
    local function safe(fn)
        return function()
            local ok, err = pcall(fn)
            if not ok then log("debug key error: " .. tostring(err)) end
        end
    end

    local dumpReport = modDir .. "pawhome_dump.txt"

    local function dumpClasses(label)
        for _, cls in ipairs(DUMP_CLASSES) do
            local obj = FindFirstOf(cls)
            local valid = obj ~= nil and obj:IsValid()
            if valid then
                local _, n = Ue4ss.dumpObject(obj, dumpReport, label .. " " .. cls)
                log(("dump %s: %s lines -> %s"):format(cls, tostring(n), dumpReport))
            else
                log("dump " .. cls .. ": no instance loaded")
            end
        end
    end

    -- Discovery scan, then dump every distinct animal actor class it found in the level
    -- (strays, if the city has any) plus DUMP_CLASSES. Runs on the game thread.
    local function explore(label)
        local report = modDir .. "pawhome_discovery.txt"
        local _, scanned, animals = Ue4ss.discover(report, label)
        log(("discovery (%s): %s objects -> %s"):format(label, tostring(scanned), report))
        for i, a in ipairs(animals or {}) do
            if i > MAX_ACTOR_DUMPS then break end
            local _, n = Ue4ss.dumpObject(a.obj, dumpReport, label .. " animal " .. a.class)
            log(("dump animal %s: %s lines"):format(a.class, tostring(n)))
        end
        dumpClasses(label)
    end

    -- Shift+F7: dump properties / functions of the first instance of DUMP_CLASSES
    RegisterKeyBind(Key.F7, { ModifierKey.SHIFT }, function()
        ExecuteInGameThread(safe(function() dumpClasses("Shift+F7") end))
    end)

    -- Shift+F8: discovery scan + animal dumps (read-only)
    RegisterKeyBind(Key.F8, { ModifierKey.SHIFT }, function()
        ExecuteInGameThread(safe(function() explore("manual (Shift+F8)") end))
    end)

    -- M1-3a auto-explore: opt-in with pawhome_autoexplore.txt. ClientRestart fires when a
    -- map is (re)loaded; registering a hook on it is VERIFIED to work in inZOI (the bundled
    -- ConsoleEnablerMod does it, see UE4SS.log), but our callback has never fired yet.
    if exists(modDir .. "pawhome_autoexplore.txt") then
        local runs = 0
        local ok, err = pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function()
            if runs >= AUTO_EXPLORE_MAX then return end
            runs = runs + 1
            local label = ("auto #%d"):format(runs)
            log(("auto-explore %s scheduled in %d s"):format(label, AUTO_EXPLORE_DELAY_MS // 1000))
            ExecuteWithDelay(AUTO_EXPLORE_DELAY_MS, function()
                ExecuteInGameThread(safe(function() explore(label) end))
            end)
        end)
        log(ok and "auto-explore armed (ClientRestart hook)" or ("auto-explore unavailable: " .. tostring(err)))
    end

    -- Shift+F6: M1-3b spawn experiment. First press spawns the class next to the player
    -- and samples its position for 60 s; second press removes it.
    local Probe = require("pawhome.adapters.ue4ss_probe")
    local okHelpers, UEHelpers = pcall(require, "UEHelpers")
    local function playerController()
        if okHelpers and UEHelpers then return UEHelpers.GetPlayerController() end
        return FindFirstOf("PlayerController")
    end
    local probe = Probe.new({
        StaticFindObject = StaticFindObject,
        LoadAsset = LoadAsset,
        getPlayerController = playerController,
        getWorld = function()
            if okHelpers and UEHelpers then return UEHelpers.GetWorld() end
            return playerController():GetWorld()
        end,
        LoopAsync = LoopAsync,
    }, log)
    local function spawnClass()
        local f = io.open(modDir .. "pawhome_spawn_class.txt", "r")
        if not f then return DEFAULT_SPAWN_CLASS end
        local line = f:read("l")
        f:close()
        line = line and line:match("^%s*(.-)%s*$")
        return (line and line ~= "") and line or DEFAULT_SPAWN_CLASS
    end
    RegisterKeyBind(Key.F6, { ModifierKey.SHIFT }, function()
        ExecuteInGameThread(safe(function()
            if probe.actor then
                probe:despawn()
            elseif probe:spawn(spawnClass()) then
                probe:sample(60, 5)
            end
        end))
    end)

    -- Shift+F9: adopt the first shelter offer (virtual pet; caps are all false)
    RegisterKeyBind(Key.F9, { ModifierKey.SHIFT }, safe(function()
        local offers = app:offers(HOUSEHOLD)
        if #offers == 0 then log("no shelter offers") return end
        local r = app:adoptOffer(HOUSEHOLD, ZOI, offers[1].id, offers[1].name)
        log(("adopt %s: %s"):format(offers[1].name, r.ok and "ok" or tostring(r.message or r.reason)))
    end))

    -- Shift+F10: print every pet's needs
    RegisterKeyBind(Key.F10, { ModifierKey.SHIFT }, safe(function()
        local view = app:view(HOUSEHOLD, ZOI)
        if #view.pets == 0 then log("no pets") return end
        for _, p in ipairs(view.pets) do
            local parts = {}
            for _, n in ipairs(p.needs) do parts[#parts + 1] = ("%s %d"):format(n.id, n.value) end
            log(("%s (%s, %s) %s | bond %d | %s"):format(
                p.name, p.stageLabel, p.moodLabel, table.concat(parts, ", "), p.bond, p.status))
        end
    end))
end
