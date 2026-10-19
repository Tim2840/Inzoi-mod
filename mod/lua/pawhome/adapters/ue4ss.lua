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
-- inZOI v0.11.0 (build 20261013.16166) T1 smoke, 2026-10-19: PawHome loaded, banner and
-- build fingerprint logged, first save written (no previous save existed). Reading an
-- existing save and the .bak rotation have NOT run in-game yet (see docs/ue4ss-adapter.md).
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
--   slot         function -> save-slot id string, or nil while no save is loaded.
--                Default (no function): always "debug".
--   locale       "zh-TW" | "en". Default "zh-TW".
--   print        function(text). Default: the global print (UE4SS routes it to UE4SS.log).
--   debugFunds   number or nil. When set, funds/charge use an in-memory wallet so
--                adoption can be exercised before the real money API is found.
--   backups      number of save generations kept as .bak1 .. .bakN. Default 3.
--   caps         table of capability flags to enable. Ignored in safe mode.
--   safeMode     true forces every cap off (unknown game build, see main.lua).
function Ue4ss.new(opts)
    assert(type(opts) == "table" and type(opts.pathPrefix) == "string", "ue4ss adapter: pathPrefix is required")
    local out = opts.print or print
    local a = {
        caps = { spawn = false, moveStray = false, buffs = false, animate = false },
        wallet = opts.debugFunds,
        safeMode = opts.safeMode == true,
    }
    -- caps may only be turned on with in-game evidence for this build (see docs);
    -- safe mode keeps them all off no matter what was requested.
    if opts.caps and not a.safeMode then
        for k in pairs(a.caps) do a.caps[k] = opts.caps[k] == true end
    end

    -- Without opts.slot every save goes to the constant slot "debug". With opts.slot,
    -- nil means "no save is loaded / not known right now" (e.g. a loading screen):
    -- reads return nothing and writes are refused, so we never fall back to another
    -- slot's file.
    local function currentSlot()
        if not opts.slot then return "debug" end
        return opts.slot()
    end

    local function path(key)
        local slot = currentSlot()
        if slot == nil then return nil end
        return opts.pathPrefix .. sanitize(slot) .. "." .. sanitize(key) .. ".sav"
    end

    -- Savegame slot the player is in (contract: core/api.lua, added in a240f2f).
    -- UNVERIFIED: the real slot id is not found yet (V3); the entry point passes no
    -- slot function, so this is the constant "debug". subscribe() is not implemented:
    -- no game event for "save loaded" is known, and the app polls slotId() anyway.
    function a.slotId()
        local slot = currentSlot()
        return slot ~= nil and tostring(slot) or nil
    end

    -- UNVERIFIED for the real clock: the in-game time source is still unknown.
    -- Candidate from the v0.10.0 main-menu scan: Class /Script/BlueClient.B1TimeManager
    -- (needs an in-save probe, V3). Until then the entry point may pass a debug clock.
    function a.now()
        if not opts.clock then return nil end
        return opts.clock()
    end

    -- First write (io.open + rename into place): VERIFIED on v0.10.0 (ZoiPets) and
    -- v0.11.0 (PawHome T1). Reading an existing save, the .bak1 fallback read and the
    -- .bakN rotation (os.rename / os.remove): UNVERIFIED in-game.
    -- Slot partitioning: UNVERIFIED, the save-slot id is not known yet (V3), so the
    -- default slot is the constant "debug".
    local backups = opts.backups or 3

    function a.saveGet(key)
        local p = path(key)
        if p == nil then return nil end -- no save loaded
        local data = readFile(p)
        if data == nil then
            -- the last write may have been interrupted between the renames
            data = readFile(p .. ".bak1")
        end
        return data
    end

    -- Writes a temp file, rotates .bak1 .. .bakN (newest first), then swaps.
    -- os.rename cannot overwrite on Windows, hence the remove/rename dance.
    -- Recovering an older generation is manual: rename .bakK back to the main file.
    function a.saveSet(key, value)
        local p = path(key)
        if p == nil then error("no savegame slot is loaded; refusing to write " .. tostring(key)) end
        local tmp = p .. ".tmp"
        local f, err = io.open(tmp, "wb")
        if not f then error("cannot open " .. tmp .. ": " .. tostring(err)) end
        f:write(value)
        f:close()
        os.remove(p .. ".bak" .. backups)
        for i = backups - 1, 1, -1 do
            os.rename(p .. ".bak" .. i, p .. ".bak" .. (i + 1)) -- missing generations fail harmlessly
        end
        os.rename(p, p .. ".bak1")
        local ok, rerr = os.rename(tmp, p)
        if not ok then
            os.rename(p .. ".bak1", p)
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

---------------------------------------------------------------- build check

-- A cheap fingerprint of the game build that needs no process execution: the size
-- of the shipping exe. scripts/smoke-t1.ps1 prints it next to the FileVersion.
-- UNVERIFIED in-game (plain io.open/seek, same as the verified save I/O).
function Ue4ss.buildFingerprint(exePath)
    local f = io.open(exePath, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return size and ("size:" .. size) or nil
end

-- listPath holds one "<fingerprint> <free-form note>" per line. A build is "known"
-- only after its caps were proven in-game (M1-3b); everything else runs in safe mode.
function Ue4ss.isKnownBuild(fingerprint, listPath)
    if not fingerprint then return false end
    local f = io.open(listPath, "r")
    if not f then return false end
    for line in f:lines() do
        if line:match("^%s*([^%s#]+)") == fingerprint then f:close(); return true end
    end
    f:close()
    return false
end

---------------------------------------------------------------- object dump

-- Writes an object's class chain, properties (with simple values) and functions.
-- Read-only. UNVERIFIED in inZOI: uses UE4SS UStruct:ForEachProperty /
-- ForEachFunction / GetSuperStruct, which ZoiPets never called. Run it on the
-- game thread. Every engine call is pcall-wrapped so a missing API only drops lines.
local SIMPLE = { BoolProperty = true, ByteProperty = true, IntProperty = true, Int64Property = true,
                 FloatProperty = true, DoubleProperty = true, StrProperty = true, NameProperty = true,
                 TextProperty = true, EnumProperty = true }

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function str(v)
    if v == nil then return "nil" end
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then return tostring(v) end
    -- FName / FString / FText userdata expose ToString in UE4SS
    return try(function() return v:ToString() end) or try(function() return v:GetFullName() end) or t
end

function Ue4ss.dumpObject(obj, reportPath, label, maxLines)
    maxLines = maxLines or 3000
    local lines = {}
    local function add(s) if #lines < maxLines then lines[#lines + 1] = s end end

    add(("===== %s | %s ====="):format(os.date("%Y-%m-%d %H:%M:%S"), label or ""))
    add("object: " .. tostring(try(function() return obj:GetFullName() end)))
    local struct = try(function() return obj:GetClass() end)
    local depth = 0
    while struct and depth < 12 do
        depth = depth + 1
        add(("\n## class %s"):format(tostring(try(function() return struct:GetFullName() end))))
        try(function()
            struct:ForEachProperty(function(prop)
                local name = try(function() return prop:GetFName():ToString() end) or "?"
                local kind = try(function() return prop:GetClass():GetFName():ToString() end) or "?"
                local value = ""
                if SIMPLE[kind] then
                    value = " = " .. str(try(function() return obj[name] end))
                elseif kind == "ObjectProperty" or kind == "ClassProperty" then
                    value = " -> " .. str(try(function() return obj[name] end))
                end
                add(("  prop %s : %s%s"):format(name, kind, value))
            end)
        end)
        try(function()
            struct:ForEachFunction(function(fn)
                add("  func " .. tostring(try(function() return fn:GetFName():ToString() end)))
            end)
        end)
        local super = try(function() return struct:GetSuperStruct() end)
        if super == nil or try(function() return super:IsValid() end) == false then break end
        struct = super
    end

    local f = io.open(reportPath, "a")
    if not f then return false end
    f:write(table.concat(lines, "\n"), "\n\n")
    f:close()
    return true, #lines
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

-- An actor placed directly in a level: "<Class> /Game/Map/X.X:PersistentLevel.<Actor>"
-- with nothing after the actor name (components look like "...PersistentLevel.A.B").
local function levelActor(fullName)
    local cls, actor = fullName:match("^(%S+) .-:PersistentLevel%.([^%.]+)$")
    return cls, actor
end

-- forEachObject defaults to the UE4SS global ForEachUObject (injectable for tests).
-- Returns ok, scannedCount, animalActors where animalActors is a list of
-- { class = <class name>, name = <full name>, obj = <object> } for animal-group
-- actors placed in a level (one entry per class), used by the auto-explore dump.
function Ue4ss.discover(reportPath, label, forEachObject)
    forEachObject = forEachObject or ForEachUObject
    local result, seen, scanned, maxPerBucket = {}, {}, 0, 400
    local animalActors, actorClasses = {}, {}
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
        if group == "animal" and not classLike then
            local cls = levelActor(fullName)
            if cls and not actorClasses[cls] then
                actorClasses[cls] = true
                animalActors[#animalActors + 1] = { class = cls, name = fullName, obj = obj }
            end
        end
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
    return true, scanned, animalActors
end

return Ue4ss
