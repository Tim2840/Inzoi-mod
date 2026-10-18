-- Glue to the real game through UE4SS (RE-UE4SS Lua), the route the ZoiPets project
-- proved out. Implements the adapter contract documented at the top of core/api.lua.
--
-- Verification status is written next to every function:
--   VERIFIED   = observed working inside inZOI (game version + evidence named)
--   UNVERIFIED = written from UE4SS docs / reasoning only; not run in the game yet
--
-- Baseline evidence (ZoiPets, inZOI v0.10.0 build 20260915.15331, 2026-09-25):
--   UE4SS v3.0.1 Beta #0 (Git SHA 8f7b2ca3) injected, detected "EngineVersion: 5.6",
--   loaded a Lua mod via enabled.txt, print() reached UE4SS.log, LoopAsync /
--   ExecuteWithDelay / ExecuteInGameThread / RegisterKeyBind ran, io.open wrote a
--   file in the mod folder, ForEachUObject scanned 265,380 objects in 4.5 s.
-- inZOI v0.11.0 (build 20261013.16166) has NOT been re-tested: everything marked
-- VERIFIED below is "verified on v0.10.0" until someone re-runs V1/V6.
--
-- Not implemented on purpose (Api returns "unsupported" and the engine falls back to
-- the virtual-pet flow): householdMembers, addBuff, listStrays, bringStray,
-- spawnPet, entityExists, despawnPet, releaseStray, playAnimation. They need the
-- in-save probes (V2-V5) first. caps therefore stay false.
local Ue4ss = {}

local function sanitize(key)
    return (tostring(key):gsub("[^%w%-_.]", "_"))
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("a")
    f:close()
    return data
end

-- opts:
--   pathPrefix   string, required. Save files are "<pathPrefix><slot>.<key>.sav".
--                The UE4SS entry point passes "<mod folder>/pawhome_".
--   clock        function -> game minutes since day 0, or nil while unknown.
--                Default: no clock (now() returns nil, the engine idles).
--   slot         function -> save-slot id string. Default: always "debug".
--   locale       "zh-TW" | "en". Default "zh-TW".
--   print        function(text). Default: the global print (UE4SS routes it to UE4SS.log).
--   debugFunds   number or nil. When set, funds/charge use an in-memory wallet so
--                adoption can be exercised before the real money API is found.
function Ue4ss.new(opts)
    assert(type(opts) == "table" and type(opts.pathPrefix) == "string", "ue4ss adapter: pathPrefix is required")
    local out = opts.print or print
    local a = {
        caps = { spawn = false, moveStray = false, buffs = false, animate = false },
        wallet = opts.debugFunds,
    }

    local function path(key)
        local slot = opts.slot and opts.slot() or "debug"
        return opts.pathPrefix .. sanitize(slot) .. "." .. sanitize(key) .. ".sav"
    end

    -- UNVERIFIED for the real clock: the in-game time source is still unknown.
    -- Candidate from the v0.10.0 main-menu scan: Class /Script/BlueClient.B1TimeManager
    -- (needs an in-save probe, V3). Until then the entry point may pass a debug clock.
    function a.now()
        if not opts.clock then return nil end
        return opts.clock()
    end

    -- File read/write in the mod folder: VERIFIED on v0.10.0 (ZoiPets wrote
    -- zoipets_save.json through io.open from a UE4SS Lua mod).
    -- Slot partitioning: UNVERIFIED, the save-slot id is not known yet (V3), so the
    -- default slot is the constant "debug".
    function a.saveGet(key)
        local p = path(key)
        local data = readFile(p)
        if data == nil then
            -- the last write may have been interrupted between the two renames
            data = readFile(p .. ".bak")
        end
        return data
    end

    -- Writes a temp file, keeps the previous version as .bak, then swaps.
    -- os.rename cannot overwrite on Windows, hence the remove/rename dance.
    function a.saveSet(key, value)
        local p = path(key)
        local tmp, bak = p .. ".tmp", p .. ".bak"
        local f, err = io.open(tmp, "wb")
        if not f then error("cannot open " .. tmp .. ": " .. tostring(err)) end
        f:write(value)
        f:close()
        os.remove(bak)
        os.rename(p, bak) -- fails harmlessly when there is no previous save
        local ok, rerr = os.rename(tmp, p)
        if not ok then
            os.rename(bak, p)
            error("cannot replace " .. p .. ": " .. tostring(rerr))
        end
        return true
    end

    -- UNVERIFIED: the game language is not read yet; the entry point decides.
    function a.locale() return opts.locale or "zh-TW" end

    -- print() -> UE4SS.log: VERIFIED on v0.10.0.
    function a.logSink(_, line) out(line .. "\n") end

    -- Log-only stand-in. A real in-game toast is UNVERIFIED (no notification API found yet).
    function a.notify(householdId, kind, text)
        out(("[PawHome][notify][%s][%s] %s\n"):format(tostring(householdId), tostring(kind), tostring(text)))
    end

    -- Debug-only wallet. The real household money API is UNVERIFIED (not found yet).
    if opts.debugFunds ~= nil then
        function a.funds() return a.wallet end
        function a.charge(_, amount)
            if a.wallet < amount then return false end
            a.wallet = a.wallet - amount
            return true
        end
    end

    return a
end

---------------------------------------------------------------- discovery

-- Scans loaded UObjects and appends names related to pets to a text file. Read-only.
-- VERIFIED on v0.10.0 (main menu): this is the same scan ZoiPets ran; it found the
-- lobby cat actor BP_Pet_Customize_01_C and the /Game/Characters/Pets/ asset folder.
-- Must run on the game thread (wrap it in ExecuteInGameThread); it hitches for a
-- few seconds, so keep it behind a debug key.
local GROUPS = {
    { "animal", { "Animal", "animal", "%f[%a]Cat%f[%A]", "%f[%a]Cat%u", "%f[%a]cat%f[%A]", "Stray", "stray",
                  "%f[%a]Pet%f[%A]", "%f[%a]Pet%u", "Coexist", "coexist" } },
    { "time", { "GameTime", "WorldTime", "TimeManager", "TimeSystem", "Clock", "InGameTime", "DayNight" } },
    { "save", { "SaveGame", "SaveData", "SaveSlot", "Household", "Family" } },
    { "zoi", { "Needs", "Mood", "Emotion", "Wallet", "Money" } },
    { "computer", { "Computer", "computer", "Laptop" } },
}

local CLASS_PREFIXES = { "Class ", "BlueprintGeneratedClass ", "WidgetBlueprintGeneratedClass ",
                         "ScriptStruct ", "UserDefinedStruct ", "DataTable " }

local function isClassLike(fullName)
    for _, p in ipairs(CLASS_PREFIXES) do
        if fullName:sub(1, #p) == p then return true end
    end
    return false
end

local function matchGroup(fullName)
    for _, group in ipairs(GROUPS) do
        for _, pattern in ipairs(group[2]) do
            if fullName:find(pattern) then return group[1] end
        end
    end
    return nil
end

-- forEachObject defaults to the UE4SS global ForEachUObject (injectable for tests).
function Ue4ss.discover(reportPath, label, forEachObject)
    forEachObject = forEachObject or ForEachUObject
    local result, seen, scanned, maxPerBucket = {}, {}, 0, 400
    local started = os.clock()

    forEachObject(function(obj)
        scanned = scanned + 1
        local ok, fullName = pcall(function() return obj:GetFullName() end)
        if not ok or type(fullName) ~= "string" or seen[fullName] then return end
        local group = matchGroup(fullName)
        if not group then return end
        seen[fullName] = true
        local classLike = isClassLike(fullName)
        -- instances only when they live in a level; skips thousands of default objects
        if not classLike and not fullName:find("PersistentLevel", 1, true) then return end
        result[group] = result[group] or { classes = {}, instances = {} }
        local bucket = classLike and result[group].classes or result[group].instances
        if #bucket < maxPerBucket then bucket[#bucket + 1] = fullName end
    end)

    local f = io.open(reportPath, "a")
    if not f then return false end
    f:write(("===== %s | %s | scanned %d objects in %.1fs =====\n"):format(
        os.date("%Y-%m-%d %H:%M:%S"), label or "", scanned, os.clock() - started))
    for _, group in ipairs(GROUPS) do
        local r = result[group[1]]
        if r then
            table.sort(r.classes)
            table.sort(r.instances)
            f:write(("\n## %s - classes (%d)\n"):format(group[1], #r.classes))
            for _, name in ipairs(r.classes) do f:write("  ", name, "\n") end
            f:write(("\n## %s - level instances (%d)\n"):format(group[1], #r.instances))
            for _, name in ipairs(r.instances) do f:write("  ", name, "\n") end
        end
    end
    f:write("\n")
    f:close()
    return true, scanned
end

return Ue4ss
