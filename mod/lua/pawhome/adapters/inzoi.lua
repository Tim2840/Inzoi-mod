-- Glue to the real game. EVERYTHING here is a placeholder until Phase 0 (see
-- docs/phase0-probe.md) tells us what the Lua API exposes. Each function names the
-- probe question that fills it in. Until then caps are all false, so the mod
-- runs as a "virtual pet" (plan C): no spawning, no moving, no animations.
--
-- Run Adapter.discover() once inside the ModKit Lua environment and paste the output
-- into docs/phase0-results.md - it lists the B2 modules that load, their functions
-- and Override_ hooks, and every global.
local Adapter = {}

Adapter.caps = { spawn = false, moveStray = false, buffs = false, animate = false }

-- P7: game clock in minutes since day 0. Replace with the real call.
function Adapter.now()
    error("TODO(P7): read the game clock")
end

-- P7: save-game key/value storage that survives save and load.
function Adapter.saveGet(key) error("TODO(P7): load " .. tostring(key)) end
function Adapter.saveSet(key, value) error("TODO(P7): store " .. tostring(key)) end

-- P8: a toast / notification for the player.
function Adapter.notify(householdId, kind, text) error("TODO(P8): show notification") end

-- P1: household members, money, and charging money.
function Adapter.householdMembers(householdId) error("TODO(P1)") end
function Adapter.funds(householdId) error("TODO(P1)") end
function Adapter.charge(householdId, amount) error("TODO(P1)") end

-- P1/P6: mood buffs on a Zoi.
function Adapter.addBuff(zoiId, buffId, minutes) error("TODO(P1)") end

-- P2: nearby stray cats the player has bonded with: list of { id, ref, stage, appearance }.
function Adapter.listStrays(householdId) error("TODO(P2)") end
-- P3: move a stray onto the household's lot (plan A). Return an entity ref.
function Adapter.bringStray(strayRef, householdId) error("TODO(P3)") end
-- P4: create a cat on the household's lot (plan B). Return an entity ref.
function Adapter.spawnPet(householdId, spec) error("TODO(P4)") end
function Adapter.entityExists(ref) error("TODO(P5)") end
function Adapter.despawnPet(ref) error("TODO(P4)") end
-- P6: play a cat animation / interaction.
function Adapter.playAnimation(ref, animationId) error("TODO(P6)") end

-- Language code the game is using, e.g. "zh-TW" / "en".
function Adapter.locale() return "en" end

-- Discovery report for Phase 0 (P1/P7): loads the documented module path and the guessed
-- ones, lists their functions and Override_ hooks, and scans the globals. Read-only.
-- See adapters/inzoi_probe.lua.
function Adapter.discover(extra)
    local Probe = require("pawhome.adapters.inzoi_probe")
    return (Probe.run({ require = require, G = _G, version = _VERSION, extra = extra }))
end

return Adapter
