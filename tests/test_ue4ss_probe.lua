-- Tests for adapters/ue4ss_probe.lua (M1-3b spawn experiment) with a fake engine.
-- The fake mirrors only the call shapes of the mods bundled with UE4SS v3.0.1
-- (World:SpawnActor(Class, Location, Rotation), Actor:IsValid(), LoadAsset(path));
-- it proves the evidence logging, not that inZOI behaves this way.
local T = require("framework")
local Probe = require("pawhome.adapters.ue4ss_probe")

local function fakeActor(name, pos)
    local a = { alive = true, pos = pos, name = name }
    function a:IsValid() return self.alive end
    function a:GetFullName() return self.name end
    function a:K2_GetActorLocation() return { X = self.pos.X, Y = self.pos.Y, Z = self.pos.Z } end
    function a:K2_DestroyActor() self.alive = false end
    return a
end

local function fakeUe(opts)
    opts = opts or {}
    local ue = { loaded = {}, loops = {}, spawned = {} }
    local cls = { IsValid = function() return true end, GetFullName = function() return "BlueprintGeneratedClass /Game/X.BP_Cat_C" end }
    ue.StaticFindObject = function(path)
        if opts.missingClass then return nil end
        if opts.needsLoad and not ue.loaded[path:gsub("%.[^./]+$", "")] then return nil end
        return cls
    end
    ue.LoadAsset = function(pkg) ue.loaded[pkg] = true end
    local pawn = fakeActor("Pawn /Game/Map.Map:PersistentLevel.Zoi_1", { X = 100, Y = 200, Z = 0 })
    local pc = { IsValid = function() return not opts.noController end, Pawn = pawn }
    ue.getPlayerController = function() return pc end
    ue.getWorld = function()
        return {
            IsValid = function() return true end,
            SpawnActor = function(_, c, loc, rot)
                if opts.spawnFails then return { IsValid = function() return false end } end
                local a = fakeActor("BP_Cat_C /Game/Map.Map:PersistentLevel.BP_Cat_C_1", { X = loc.X, Y = loc.Y, Z = loc.Z })
                a.Controller = opts.controller
                function a:SpawnDefaultController()
                    if opts.possessFails then error("SpawnDefaultController failed") end
                    ue.possessCalls = (ue.possessCalls or 0) + 1
                    self.Controller = opts.newController
                end
                ue.spawned[#ue.spawned + 1] = { class = c, loc = loc, rot = rot, actor = a }
                return a
            end,
        }
    end
    ue.LoopAsync = function(ms, fn) ue.loops[#ue.loops + 1] = { ms = ms, fn = fn } end
    ue.autoPossess = opts.autoPossess
    ue.dumps = {}
    ue.dumpObject = function(obj, label) ue.dumps[#ue.dumps + 1] = { obj = obj, label = label } end
    ue.FindFirstOf = function(name) return opts.existing and opts.existing[name] or nil end
    return ue
end

local function collect()
    local lines = {}
    return lines, function(s) lines[#lines + 1] = s end
end

local function has(lines, needle)
    for _, l in ipairs(lines) do if l:find(needle, 1, true) then return true end end
    return false
end

T.test("probe: spawns next to the player and logs b1/b2", function()
    local ue = fakeUe({ controller = { IsValid = function() return true end, GetFullName = function() return "AIController /Game/Map.Map:PersistentLevel.AIC_Cat_1" end } })
    local lines, log = collect()
    local p = Probe.new(ue, log)
    T.truthy(p:spawn("/Game/X.BP_Cat_C"))
    T.eq(ue.spawned[1].loc.X, 250, "150 units in front of the player on X")
    T.truthy(has(lines, "spawn /Game/X.BP_Cat_C: BP_Cat_C /Game/Map.Map:PersistentLevel.BP_Cat_C_1"), "b1")
    T.truthy(has(lines, "controller: AIController"), "b2 controller")
    T.truthy(has(lines, "AIControllerClass: nil"), "b2 class missing is logged as nil")
end)

T.test("probe: loads the asset when the class is not in memory", function()
    local ue = fakeUe({ needsLoad = true })
    local p = Probe.new(ue, function() end)
    T.truthy(p:spawn("/Game/X.BP_Cat_C"))
    T.truthy(ue.loaded["/Game/X"], "LoadAsset got the package path")
end)

T.test("probe: every failure becomes a log line, not an error", function()
    for _, case in ipairs({ { missingClass = true, msg = "class not found" },
                            { noController = true, msg = "no player controller" },
                            { spawnFails = true, msg = "invalid actor" } }) do
        local lines, log = collect()
        local p = Probe.new(fakeUe(case), log)
        T.eq(p:spawn("/Game/X.BP_Cat_C"), nil)
        T.truthy(has(lines, case.msg), case.msg)
    end
end)

T.test("probe: refuses a second spawn until the first is removed", function()
    local lines, log = collect()
    local p = Probe.new(fakeUe(), log)
    p:spawn("/Game/X.BP_Cat_C")
    T.eq(p:spawn("/Game/X.BP_Cat_C"), nil)
    T.truthy(has(lines, "already spawned"))
end)

T.test("probe: b3 samples positions and classifies movement", function()
    local ue = fakeUe()
    local lines, log = collect()
    local p = Probe.new(ue, log)
    local actor = p:spawn("/Game/X.BP_Cat_C")
    local result
    p:sample(10, 5, function(d) result = d end)
    T.eq(ue.loops[1].ms, 5000)
    local fn = ue.loops[1].fn
    T.eq(fn(), false)                    -- t=0
    actor.pos = { X = actor.pos.X + 300, Y = actor.pos.Y, Z = 0 }
    T.eq(fn(), false)                    -- t=5
    T.eq(fn(), true, "stops after totalSec") -- t=10
    T.near(result, 300, 1e-6)
    T.truthy(has(lines, "pos t=0 x=250.0 y=200.0 z=0.0"))
    T.truthy(has(lines, "-> MOVED"))
end)

T.test("probe: after sampling it warns that the actor is still in the world, until removed", function()
    local ue = fakeUe()
    local lines, log = collect()
    local p = Probe.new(ue, log)
    p:spawn("/Game/X.BP_Cat_C")
    p:sample(10, 5)
    local fn = ue.loops[1].fn
    fn(); fn(); fn()
    T.truthy(has(lines, "WARNING: actor still alive - press Shift+F6 to remove it BEFORE saving or leaving the world"))
    T.truthy(p.actor, "not removed automatically (b4 needs the 5-minute stability window)")

    -- the same run when the actor is already gone: no warning
    local lines2, log2 = collect()
    local ue2 = fakeUe()
    local p2 = Probe.new(ue2, log2)
    local a2 = p2:spawn("/Game/X.BP_Cat_C")
    p2:sample(5, 5)
    local fn2 = ue2.loops[1].fn
    fn2()
    a2.alive = false
    fn2()
    T.falsy(has(lines2, "WARNING"), "no warning when there is nothing left to remove")
end)

T.test("probe: b3 reports STATIONARY and stops when the actor vanishes", function()
    local ue = fakeUe()
    local lines, log = collect()
    local p = Probe.new(ue, log)
    local actor = p:spawn("/Game/X.BP_Cat_C")
    p:sample(10, 5)
    local fn = ue.loops[1].fn
    fn(); fn(); fn()
    T.truthy(has(lines, "-> STATIONARY"))

    p.actor = actor
    p:sample(60, 5)
    actor.alive = false
    T.eq(ue.loops[2].fn(), true)
    T.truthy(has(lines, "actor is gone"))
end)

T.test("probe: b4 removes the actor and forgets stale references", function()
    local lines, log = collect()
    local p = Probe.new(fakeUe(), log)
    local actor = p:spawn("/Game/X.BP_Cat_C")
    T.truthy(p:despawn())
    T.falsy(actor.alive)
    T.truthy(has(lines, "removed BP_Cat_C"))
    T.eq(p.actor, nil)

    p:spawn("/Game/X.BP_Cat_C")
    p.actor.alive = false -- destroyed by the game
    T.falsy(p:despawn())
    T.eq(p.actor, nil, "stale reference cleared, a new spawn is possible")
end)

-- ------------------------------------------------------------------ b0: observe an existing actor

local function fakeController(name, brain)
    local c = { IsValid = function() return true end, GetFullName = function() return name end }
    if brain then c.BrainComponent = { IsValid = function() return true end, GetFullName = function() return brain end } end
    return c
end

T.test("probe b0: observe logs the controller, its brain and dumps it; spawns nothing", function()
    local ctrl = fakeController("AIController /Game/Map/X.X:PersistentLevel.AIController_1", "BehaviorTreeComponent /Game/Map/X.X:PersistentLevel.AIController_1.BTComp")
    local existing = fakeActor("Void_Cat1_C /Game/Map/X.X:PersistentLevel.Void_Cat1_C_1", { X = 0, Y = 0, Z = 0 })
    existing.Controller = ctrl
    local ue = fakeUe({ existing = { Void_Cat1_C = existing } })
    local lines, log = collect()
    local p = Probe.new(ue, log)
    T.eq(p:observe("Void_Cat1_C"), existing)
    T.truthy(has(lines, "observe Void_Cat1_C: Void_Cat1_C /Game/Map/X.X:PersistentLevel.Void_Cat1_C_1 (existing game actor, will not be removed)"))
    T.truthy(has(lines, "controller: AIController /Game/Map/X.X:PersistentLevel.AIController_1"))
    T.truthy(has(lines, "BrainComponent: BehaviorTreeComponent"))
    T.eq(#ue.dumps, 1, "controller dumped once")
    T.eq(ue.dumps[1].obj, ctrl)
    T.truthy(ue.dumps[1].label:find("controller of Void_Cat1_C", 1, true))
    T.eq(#ue.spawned, 0, "nothing spawned")
end)

T.test("probe b0: no instance, or no FindFirstOf, is a log line", function()
    local lines, log = collect()
    T.eq(Probe.new(fakeUe(), log):observe("Void_Cat1_C"), nil)
    T.truthy(has(lines, "observe Void_Cat1_C: no instance loaded"))
    local lines2, log2 = collect()
    local ue = fakeUe(); ue.FindFirstOf = nil
    T.eq(Probe.new(ue, log2):observe("Void_Cat1_C"), nil)
    T.truthy(has(lines2, "FindFirstOf is not available"))
end)

T.test("probe b0: an observed actor is sampled, never warned about and never removed", function()
    local existing = fakeActor("Void_Cat1_C /Game/Map/X.X:PersistentLevel.Void_Cat1_C_1", { X = 10, Y = 0, Z = 0 })
    local ue = fakeUe({ existing = { Void_Cat1_C = existing } })
    local lines, log = collect()
    local p = Probe.new(ue, log)
    p:observe("Void_Cat1_C")
    T.truthy(p:sample(10, 5))
    local fn = ue.loops[1].fn
    fn()
    existing.pos = { X = 400, Y = 0, Z = 0 }
    fn(); fn()
    T.truthy(has(lines, "-> MOVED"))
    T.falsy(has(lines, "WARNING"), "no 'press Shift+F6 to remove' warning for a game actor")
    T.falsy(p:despawn(), "despawn only handles spawned actors")
    T.truthy(existing.alive, "the game actor was not destroyed")
    T.truthy(has(lines, "never removed"))
end)

T.test("probe b0: a second sampling run is refused while one is active", function()
    local existing = fakeActor("Void_Cat1_C /Game/X.X:PersistentLevel.Void_Cat1_C_1", { X = 0, Y = 0, Z = 0 })
    local ue = fakeUe({ existing = { Void_Cat1_C = existing } })
    local lines, log = collect()
    local p = Probe.new(ue, log)
    p:observe("Void_Cat1_C")
    T.truthy(p:sample(60, 5))
    T.falsy(p:sample(60, 5))
    T.eq(#ue.loops, 1, "no second loop")
    T.truthy(has(lines, "a sampling run is already active"))
end)

-- ------------------------------------------------------------------ optional possess

T.test("probe possess: with autoPossess a controller-less spawned pawn gets SpawnDefaultController", function()
    local ue = fakeUe({ autoPossess = true,
        newController = fakeController("AIController /Game/Map/X.X:PersistentLevel.AIController_9") })
    local lines, log = collect()
    local p = Probe.new(ue, log)
    p:spawn("/Game/X.BP_Cat_C")
    T.eq(ue.possessCalls, 1)
    T.truthy(has(lines, "controller: nil"), "the pre-possess state is logged first")
    T.truthy(has(lines, "possess: SpawnDefaultController called"))
    T.truthy(has(lines, "controller: AIController /Game/Map/X.X:PersistentLevel.AIController_9"), "and the result")
end)

T.test("probe possess: not called without autoPossess, or when a controller exists, failure is a log line", function()
    local ue = fakeUe()
    local p = Probe.new(ue, function() end)
    p:spawn("/Game/X.BP_Cat_C")
    T.eq(ue.possessCalls, nil, "off by default")

    local ue2 = fakeUe({ autoPossess = true, controller = fakeController("AIController /X") })
    local lines2, log2 = collect()
    Probe.new(ue2, log2):spawn("/Game/X.BP_Cat_C")
    T.eq(ue2.possessCalls, nil, "already has a controller")

    local ue3 = fakeUe({ autoPossess = true, possessFails = true })
    local lines3, log3 = collect()
    T.truthy(Probe.new(ue3, log3):spawn("/Game/X.BP_Cat_C"), "the spawn itself still succeeds")
    T.truthy(has(lines3, "possess: SpawnDefaultController failed"))
end)
