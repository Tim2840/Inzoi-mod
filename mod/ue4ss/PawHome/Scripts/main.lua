-- UE4SS entry point for Paw Home. Installed as:
--   <inZOI>\BlueClient\Binaries\Win64\ue4ss\Mods\PawHome\Scripts\main.lua
-- with the engine copied next to it as Scripts\pawhome\ (see scripts\install-ue4ss.ps1).
--
-- Everything game-specific lives in pawhome/adapters/ue4ss.lua; this file only wires
-- it up, drives the hourly tick and registers debug keys.
-- UE4SS globals used here (print, LoopAsync, ExecuteInGameThread, RegisterKeyBind,
-- Key, ModifierKey) were VERIFIED to load on inZOI v0.10.0 via the ZoiPets mod;
-- the Shift+F-key bindings themselves have NOT been pressed in-game yet.

local DEBUG = true
-- Until the real game clock is found (probe V3) the debug clock runs
-- 1 real second = 1 game minute, so 1 real minute = 1 game hour.
local DEBUG_MINUTES_PER_SECOND = 1
local DEBUG_FUNDS = 1000
-- Household / Zoi ids are unknown until the in-save probes; constants for now.
local HOUSEHOLD, ZOI = 1, 1

local scriptsDir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or "./"
package.path = scriptsDir .. "?.lua;" .. package.path
local modDir = scriptsDir:gsub("Scripts[\\/]$", "")

local Ue4ss = require("pawhome.adapters.ue4ss")
local Main = require("pawhome.main")

local started = os.time()
local adapter = Ue4ss.new({
    pathPrefix = modDir .. "pawhome_",
    clock = DEBUG and function() return (os.time() - started) * DEBUG_MINUTES_PER_SECOND end or nil,
    debugFunds = DEBUG and DEBUG_FUNDS or nil,
})

local function log(msg) print("[PawHome] " .. msg .. "\n") end

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

    -- Shift+F8: discovery report (read-only scan of loaded objects)
    RegisterKeyBind(Key.F8, { ModifierKey.SHIFT }, function()
        ExecuteInGameThread(safe(function()
            local report = modDir .. "pawhome_discovery.txt"
            local _, scanned = Ue4ss.discover(report, "manual (Shift+F8)")
            log(("discovery: %s objects -> %s"):format(tostring(scanned), report))
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
