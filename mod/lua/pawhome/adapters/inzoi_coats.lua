-- B1 (game thread): keeps our cats in their own coat (docs/research/fixed-coat.md).
-- The game picks a random coat texture whenever a cat actor is created (load, summon,
-- coming back into view). The B1 cat binding reports every cat actor here; B2 sends the
-- list of our cats as "<entity id>=<texture>;..." (channel pawhome:coats).
-- The last list is also kept in a cfg file, so right after a load our cats get their coat
-- before B2 has finished its handshake with the UI.
-- Game calls go through `platform`:
--   platform.actorEntityId(actor)         -> number or nil
--   platform.applyCoat(actor, texture)    -> true when the coat was set
--   platform.cfgSave(section, key, value) / platform.cfgLoad(section, key)
--   platform.log(line)                    optional
local Coats = { SECTION = "coats", KEY = "map" }

function Coats.parse(text)
    local map = {}
    for eid, texture in tostring(text or ""):gmatch("(%d+)=([%w_]+)") do
        map[tonumber(eid)] = texture
    end
    return map
end

function Coats.new(platform)
    local c = { actors = {}, map = {}, applied = {} }

    local function log(line)
        if platform.log then pcall(platform.log, "[PawHome coats] " .. line) end
    end

    local function apply(eid)
        local actor, texture = c.actors[eid], c.map[eid]
        if actor == nil or texture == nil or c.applied[eid] == texture then return end
        local ok, done = pcall(platform.applyCoat, actor, texture)
        if ok and done then
            c.applied[eid] = texture
        else
            log("could not set the coat of cat " .. tostring(eid) .. ": " .. tostring(done))
        end
    end

    -- the list from the last session, until B2 sends the current one
    do
        local ok, cached = pcall(platform.cfgLoad, Coats.SECTION, Coats.KEY)
        if ok and cached then c.map = Coats.parse(cached) end
    end

    -- B1 cat binding on_begin: the actor was just created with a random coat.
    function c.onActor(actor)
        local ok, eid = pcall(platform.actorEntityId, actor)
        if not ok or eid == nil then return end
        c.actors[eid] = actor
        c.applied[eid] = nil
        apply(eid)
    end

    function c.onActorEnd(actor)
        local ok, eid = pcall(platform.actorEntityId, actor)
        if ok and eid ~= nil and c.actors[eid] == actor then
            c.actors[eid], c.applied[eid] = nil, nil
        end
    end

    -- The current list from B2 (replaces the previous one).
    function c.setList(text)
        c.map = Coats.parse(text)
        pcall(platform.cfgSave, Coats.SECTION, Coats.KEY, tostring(text or ""))
        for eid in pairs(c.map) do apply(eid) end
    end

    return c
end

return Coats
