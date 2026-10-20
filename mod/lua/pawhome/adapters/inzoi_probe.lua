-- Phase 0 discovery for the official ModKit route (P1/P7). Read-only: it only calls
-- `require` and reads tables, it never calls a game function. Run it once inside the
-- ModKit Lua environment and paste the report into docs/phase0-results.md.
--
-- What is known (docs/modkit-route.md, official docs read 2026-10-20): B2 types load with
-- `require('Systems.B2SpawnerManager')`, and rule hooks are fields named `Override_*`.
-- Every other module path below is a GUESS made by applying the same naming pattern;
-- the report says for each one whether it loaded. Nothing here is verified in-game.
--
-- `env` is injected so tests run without the game:
--   env.require(name)  -> module table (may raise)
--   env.G              -> the global table to scan (defaults to nothing)
--   env.version        -> _VERSION string
local Probe = {}

-- Seen on the official FB2SpawnerManager page.
Probe.DOCUMENTED = { "Systems.B2SpawnerManager" }

-- Same pattern applied to the other types docs/modkit-route.md lists. Unverified.
Probe.GUESSED = {
    "Systems.B2TimeManager",
    "Systems.B2TimeTaskManager",
    "Systems.B2AdoptionManager",
    "Systems.B2EntityManager",
    "Systems.B2PopulationSystem",
    "Systems.B2HouseholdManager",
}

-- Global names worth dumping one level deeper if they exist.
Probe.ROOTS = { "inzoi", "game", "Game", "zoi", "Zoi", "cli", "CLI", "ui", "UI" }

-- Key names containing one of these (case-insensitive) are listed again under "hits".
Probe.KEYWORDS = { "pet", "animal", "cat", "dog", "adopt", "stray", "howl", "spawn", "time", "save", "household" }

local MAX_INDEX_DEPTH = 5

local function sortedCopy(t)
    local out = {}
    for i, v in ipairs(t) do out[i] = v end
    table.sort(out)
    return out
end

-- Keys of a table plus the keys reachable through its metatable's __index chain
-- (how class-like modules usually expose methods). A protected metatable or a
-- function __index is reported, not followed.
local function collectKeys(value)
    local seen, keys, notes = {}, {}, {}
    local current, depth = value, 0
    while type(current) == "table" and depth <= MAX_INDEX_DEPTH do
        for k, v in pairs(current) do
            local name = tostring(k)
            if not seen[name] then
                seen[name] = true
                keys[#keys + 1] = { name = name, kind = type(v) }
            end
        end
        local okMt, mt = pcall(getmetatable, current)
        if not okMt or mt == nil then break end
        if type(mt) ~= "table" then
            notes[#notes + 1] = "protected metatable"
            break
        end
        local index = rawget(mt, "__index")
        if type(index) == "function" then
            notes[#notes + 1] = "__index is a function (keys not listable)"
            break
        end
        if index == current then break end
        current, depth = index, depth + 1
    end
    table.sort(keys, function(a, b) return a.name < b.name end)
    return keys, notes
end

local function matchesKeyword(name)
    local lower = name:lower()
    for _, kw in ipairs(Probe.KEYWORDS) do
        if lower:find(kw, 1, true) then return true end
    end
    return false
end

-- Splits keys into functions, Override_ hooks and fields.
local function describe(value)
    local keys, notes = collectKeys(value)
    local d = { functions = {}, hooks = {}, fields = {}, notes = notes }
    for _, k in ipairs(keys) do
        if k.name:sub(1, 9) == "Override_" then
            d.hooks[#d.hooks + 1] = k.name
        elseif k.kind == "function" then
            d.functions[#d.functions + 1] = k.name
        else
            d.fields[#d.fields + 1] = k.name .. ":" .. k.kind
        end
    end
    return d
end

local function list(names)
    if #names == 0 then return "(none)" end
    return table.concat(names, ", ")
end

-- Returns the report text and a summary { loaded = {name...}, missing = {name...}, hits = {...} }.
function Probe.run(env)
    env = env or {}
    local req = env.require or function() error("require is not available") end
    local lines, summary = {}, { loaded = {}, missing = {}, hits = {} }
    local function add(s) lines[#lines + 1] = s end
    local function noteHits(where, names)
        for _, n in ipairs(names) do
            local bare = n:match("^([^:]+)") or n
            if matchesKeyword(bare) then summary.hits[#summary.hits + 1] = where .. "." .. bare end
        end
    end

    add("# Paw Home ModKit probe")
    add("- Lua: " .. tostring(env.version))
    add("- game build / date: (fill in)")
    add("")

    local function probeModule(name, origin)
        local ok, mod = pcall(req, name)
        if not ok then
            summary.missing[#summary.missing + 1] = name
            add(("## %s (%s): NOT LOADED - %s"):format(name, origin, tostring(mod)))
            return
        end
        if type(mod) ~= "table" then
            summary.loaded[#summary.loaded + 1] = name
            add(("## %s (%s): loaded, returned a %s"):format(name, origin, type(mod)))
            return
        end
        summary.loaded[#summary.loaded + 1] = name
        local d = describe(mod)
        add(("## %s (%s): loaded"):format(name, origin))
        add("- functions: " .. list(d.functions))
        add("- Override_ hooks: " .. list(d.hooks))
        add("- fields: " .. list(d.fields))
        if #d.notes > 0 then add("- notes: " .. table.concat(d.notes, "; ")) end
        noteHits(name, d.functions)
        noteHits(name, d.hooks)
        noteHits(name, d.fields)
    end

    for _, name in ipairs(Probe.DOCUMENTED) do probeModule(name, "documented") end
    for _, name in ipairs(Probe.GUESSED) do probeModule(name, "guessed") end
    for _, name in ipairs(env.extra or {}) do probeModule(name, "extra") end

    add("")
    local G = env.G
    if type(G) == "table" then
        for _, root in ipairs(Probe.ROOTS) do
            local v = rawget(G, root)
            if type(v) == "table" then
                local d = describe(v)
                add(("## global %s"):format(root))
                add("- functions: " .. list(d.functions))
                add("- fields: " .. list(d.fields))
                noteHits(root, d.functions)
                noteHits(root, d.fields)
                -- one level deeper for sub-tables such as inzoi.cli
                for _, f in ipairs(d.fields) do
                    local key = f:match("^(.+):table$")
                    if key then
                        local sub = describe(rawget(v, key))
                        add(("- %s.%s functions: %s"):format(root, key, list(sub.functions)))
                        noteHits(root .. "." .. key, sub.functions)
                    end
                end
            end
        end
        local globals = {}
        for k in pairs(G) do globals[#globals + 1] = tostring(k) end
        add("## _G")
        add(list(sortedCopy(globals)))
        noteHits("_G", globals)
    end

    add("")
    add("## keyword hits (" .. table.concat(Probe.KEYWORDS, "/") .. ")")
    add(list(sortedCopy(summary.hits)))
    return table.concat(lines, "\n"), summary
end

return Probe
