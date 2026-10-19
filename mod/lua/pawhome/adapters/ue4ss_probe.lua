-- M1-3b spawn experiment tooling (debug only). Spawns an actor class next to the
-- player, records the evidence the workflow asks for (b1 spawn result, b2 controller,
-- b3 movement samples, b4 removal) in the log, and removes it again.
--
-- ALL OF THIS IS UNVERIFIED IN inZOI. The call shapes come from the mods bundled with
-- UE4SS v3.0.1 (8f7b2ca3): BPModLoaderMod uses `World:SpawnActor(Class, {}, {})` and
-- `Actor:IsValid()`, ConsoleCommandsMod uses `LoadAsset(path)`, several mods use
-- `StaticFindObject(path)`, and shared/UEHelpers provides GetPlayerController/GetWorld.
-- None of them has been called by us inside a save yet. Every engine call is
-- pcall-wrapped; a failure becomes a log line, never an error.
--
-- `ue` is injected so tests can run without the game:
--   ue.StaticFindObject(path), ue.LoadAsset(path), ue.getPlayerController(),
--   ue.getWorld(), ue.LoopAsync(ms, fn)
local Probe = {}
Probe.__index = Probe

local function try(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil, a
end

local function valid(obj)
    if obj == nil then return false end
    return try(function() return obj:IsValid() end) == true
end

local function fullName(obj)
    if obj == nil then return "nil" end
    return try(function() return obj:GetFullName() end) or "?"
end

local function vec(v)
    if v == nil then return nil end
    local x = try(function() return v.X end)
    local y = try(function() return v.Y end)
    local z = try(function() return v.Z end)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    return { X = x, Y = y, Z = z }
end

-- Two kinds of actor are tracked, and only one of them may ever be destroyed:
--   self.actor    spawned by us (spawn); sample / despawn / the "still alive" warning apply
--   self.observed an existing game actor found with FindFirstOf (observe); it is only
--                 read - despawn never touches it
-- Optional injected pieces: ue.FindFirstOf(name), ue.dumpObject(obj, label) (writes a
-- property/function dump), ue.autoPossess (spawn calls SpawnDefaultController when the
-- spawned pawn has no controller).
function Probe.new(ue, log)
    return setmetatable({ ue = ue, log = log, actor = nil, observed = nil, sampling = false }, Probe)
end

-- Returns the UClass for a full object path such as
-- "/Game/Characters/Pets/Operator/OP001/Mesh/BP_Pet_Customize_01.BP_Pet_Customize_01_C".
function Probe:findClass(path)
    local cls = try(self.ue.StaticFindObject, path)
    if valid(cls) then return cls end
    -- not in memory yet: ask the engine to load the asset, then look again
    try(self.ue.LoadAsset, (path:gsub("%.[^./]+$", "")))
    cls = try(self.ue.StaticFindObject, path)
    if valid(cls) then return cls end
    return nil
end

function Probe:playerLocation()
    local pc = try(self.ue.getPlayerController)
    if not valid(pc) then return nil, "no player controller" end
    local pawn = try(function() return pc.Pawn end)
    if not valid(pawn) then return nil, "no pawn" end
    local loc = vec(try(function() return pawn:K2_GetActorLocation() end))
    if not loc then return nil, "no location" end
    return loc
end

-- b1 + b2. Returns the actor or nil.
function Probe:spawn(classPath, offset)
    offset = offset or 150
    if valid(self.actor) then
        self.log("spawn: an actor is already spawned (" .. fullName(self.actor) .. "); remove it first")
        return nil
    end
    local cls = self:findClass(classPath)
    if not cls then
        self.log("spawn " .. classPath .. ": failed (class not found)")
        return nil
    end
    local at, why = self:playerLocation()
    if not at then
        self.log("spawn " .. classPath .. ": failed (" .. why .. ")")
        return nil
    end
    local world = try(self.ue.getWorld)
    if not valid(world) then
        self.log("spawn " .. classPath .. ": failed (no world)")
        return nil
    end
    local location = { X = at.X + offset, Y = at.Y, Z = at.Z }
    local actor, err = try(function() return world:SpawnActor(cls, location, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
    if not valid(actor) then
        self.log("spawn " .. classPath .. ": failed (" .. tostring(err or "SpawnActor returned an invalid actor") .. ")")
        return nil
    end
    self.actor = actor
    self.log("spawn " .. classPath .. ": " .. fullName(actor))
    local controller = self:describeController(actor)
    if controller == nil and self.ue.autoPossess then self:possess() end
    return actor
end

-- b2: what drives the actor. A Pawn has Controller / AIControllerClass; other actors
-- simply log nil, which is itself evidence. When there is a controller, also log its
-- BrainComponent and, if `dump` is true and a dumper was injected, write its full
-- property/function dump. Returns the controller or nil.
function Probe:describeController(actor, dump)
    local controller = try(function() return actor.Controller end)
    local has = valid(controller)
    self.log("controller: " .. (has and fullName(controller) or "nil"))
    local aiClass = try(function() return actor.AIControllerClass end)
    self.log("AIControllerClass: " .. (valid(aiClass) and fullName(aiClass) or "nil"))
    if has then
        local brain = try(function() return controller.BrainComponent end)
        self.log("BrainComponent: " .. (valid(brain) and fullName(brain) or "nil"))
        if dump and self.ue.dumpObject then
            try(self.ue.dumpObject, controller, "controller of " .. fullName(actor))
            self.log("controller dump written")
        end
    end
    return has and controller or nil
end

-- Optional: give a spawned Pawn a controller. By Unreal convention a pawn whose class
-- default is AutoPossessAI = PlacedInWorld gets none when spawned at runtime, so a nil
-- controller after spawn is not evidence that the game has no AI for that class.
-- UNVERIFIED in inZOI: Pawn:SpawnDefaultController() is listed in the Void_Cat1_C dump
-- but has never been called.
function Probe:possess()
    local actor = self.actor
    if not valid(actor) then self.log("possess: no spawned actor") return false end
    if valid(try(function() return actor.Controller end)) then
        self.log("possess: the actor already has a controller")
        return false
    end
    local _, err = try(function() actor:SpawnDefaultController() end)
    if err then
        self.log("possess: SpawnDefaultController failed (" .. tostring(err) .. ")")
        return false
    end
    self.log("possess: SpawnDefaultController called")
    self:describeController(actor)
    return true
end

-- b0: observe an existing game actor without spawning or changing anything. Returns it or nil.
function Probe:observe(className)
    if not self.ue.FindFirstOf then self.log("observe: FindFirstOf is not available") return nil end
    local actor = try(self.ue.FindFirstOf, className)
    if not valid(actor) then
        self.log("observe " .. className .. ": no instance loaded")
        return nil
    end
    self.observed = actor
    self.log("observe " .. className .. ": " .. fullName(actor) .. " (existing game actor, will not be removed)")
    self:describeController(actor, true)
    return actor
end

-- b3: sample the actor's position every intervalSec for totalSec and log the path length.
function Probe:sample(totalSec, intervalSec, onDone)
    totalSec, intervalSec = totalSec or 60, intervalSec or 5
    if self.sampling then self.log("sample: a sampling run is already active") return false end
    -- a spawned actor takes precedence over an observed one
    local actor = valid(self.actor) and self.actor or self.observed
    if not valid(actor) then self.log("sample: no spawned or observed actor") return false end
    local spawned = actor == self.actor
    local samples, distance, last, elapsed = 0, 0, nil, 0
    self.sampling = true
    self.ue.LoopAsync(intervalSec * 1000, function()
        if not valid(actor) then
            self.log("sample: actor is gone after " .. elapsed .. " s")
            self.sampling = false
            return true -- stop the loop
        end
        local p = vec(try(function() return actor:K2_GetActorLocation() end))
        if p then
            if last then
                distance = distance + math.sqrt((p.X - last.X) ^ 2 + (p.Y - last.Y) ^ 2 + (p.Z - last.Z) ^ 2)
            end
            last = p
            samples = samples + 1
            self.log(("pos t=%d x=%.1f y=%.1f z=%.1f"):format(elapsed, p.X, p.Y, p.Z))
        else
            self.log(("pos t=%d unreadable"):format(elapsed))
        end
        elapsed = elapsed + intervalSec
        if elapsed > totalSec then
            self.log(("movement: %d samples, total distance %.1f units -> %s"):format(
                samples, distance, distance > 100 and "MOVED" or "STATIONARY"))
            self.sampling = false
            if onDone then onDone(distance, samples) end
            -- The actor is NOT removed automatically: the operator removes it with a second
            -- Shift+F6, and b4 then watches 5 minutes of stability AFTER the removal (see
            -- docs/qa/smoke-checklist.md). If the player saves or leaves the world while it
            -- is still alive, it might be serialized into the game's own save, so say so loudly.
            -- (an observed game actor is not ours to remove, so no warning for it)
            if spawned and valid(actor) then Probe.warnStillAlive(self) end
            return true
        end
        return false
    end)
    return true
end

function Probe.warnStillAlive(self)
    self.log("WARNING: actor still alive - press Shift+F6 to remove it BEFORE saving or leaving the world")
end

-- b4
function Probe:despawn()
    local actor = self.actor
    if not valid(actor) then
        -- the game may already have destroyed it; forget the stale reference
        self.actor = nil
        self.log("remove: nothing spawned (or the actor is already gone); an observed game actor is never removed")
        return false
    end
    local name = fullName(actor)
    local _, err = try(function() actor:K2_DestroyActor() end)
    self.actor = nil
    if err then
        self.log("remove " .. name .. ": failed (" .. tostring(err) .. ")")
        return false
    end
    self.log("removed " .. name)
    return true
end

return Probe
