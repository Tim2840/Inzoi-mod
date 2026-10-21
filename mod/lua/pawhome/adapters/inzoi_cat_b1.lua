-- B1 (game thread) side of the cat's looks: plays the VAT animations the B2 adapter asks for
-- and keeps the cat's size (adapters/inzoi.lua, "Looks"). One instance for the game thread;
-- the B1 cat binding (mod/modkit/lua/B1/PawHomeBind/Cat.lua) forwards its callbacks here.
--
-- Game calls go through `platform` (adapters/inzoi_platform.lua Platform.b1, a fake in tests):
--   platform.actorId(actor)          -> cat entity id (number) or nil
--   platform.valid(actor)            -> false for an actor reference that is no longer usable
--   platform.setScale(actor, s)      -> true when applied
--   platform.playVat(actor, name)    -> true when the cat now plays `name`
--   platform.currentVat(actor)       -> name of the VAT animation the cat plays, or nil
--   platform.sendToSim(eid, channel, payload)
--   platform.log(line)               optional
--
-- Rules that keep the game's own animations intact:
--   * an animation that we did not start (the game's Play / Give Snack on the cat) blocks
--     ours for `GRACE` seconds after it was last seen changing;
--   * a one-shot of ours is never cut short by the next request;
--   * after a one-shot the cat goes back to the sitting idle it was given.
local Wire = require("pawhome.adapters.inzoi_wire")

local CatB1 = {
    GRACE = 15,            -- seconds a foreign animation blocks ours
    POLL = 1,              -- seconds between looks at what the cat plays
    REAPPLY = { 1.5, 5 },  -- seconds after on_begin to apply the size again (early refs go stale)
}

function CatB1.new(platform)
    local c = { cats = {}, t = 0, sincePoll = 0 }

    local function log(line)
        if platform.log then pcall(platform.log, "cat: " .. line) end
    end

    local function lower(s) return s and tostring(s):lower() or nil end

    local function applyScale(cat)
        if not (cat.scale and cat.actor and platform.valid(cat.actor)) then return false end
        local ok, done = pcall(platform.setScale, cat.actor, cat.scale)
        if ok and done == true then
            if cat.logged ~= cat.scale then log("size " .. tostring(cat.scale) .. " on " .. tostring(cat.eid)) end
            cat.logged = cat.scale
            return true
        end
        log("size failed on " .. tostring(cat.eid) .. ": " .. tostring(done))
        return false
    end

    local function blocked(cat)
        if cat.foreignAt and c.t - cat.foreignAt < CatB1.GRACE then return "game" end
        if cat.backAt and c.t < cat.backAt then return "one-shot" end
        return nil
    end

    local function play(cat, name)
        if not (cat.actor and platform.valid(cat.actor)) then return false end
        local ok, done = pcall(platform.playVat, cat.actor, name)
        if ok and done then
            log("plays " .. tostring(name) .. " on " .. tostring(cat.eid))
            cat.ours = lower(name)
            cat.lastSeen = cat.ours
            return true
        end
        log("could not play " .. tostring(name) .. " on " .. tostring(cat.eid))
        return false
    end

    local function catFor(actor)
        local ok, eid = pcall(platform.actorId, actor)
        if not ok or eid == nil then return nil end
        local cat = c.cats[eid]
        if not cat then
            cat = { eid = eid }
            c.cats[eid] = cat
        end
        return cat
    end

    -- B1 cat binding on_begin: the actor appeared (load, coming home, summon, respawn).
    function c.onBegin(actor)
        local cat = catFor(actor)
        if not cat then return end
        cat.actor = actor
        cat.ours, cat.lastSeen, cat.foreignAt, cat.backAt, cat.back = nil, nil, nil, nil, nil
        cat.reapply = {}
        for i, s in ipairs(CatB1.REAPPLY) do cat.reapply[i] = c.t + s end
        applyScale(cat)
        pcall(platform.sendToSim, cat.eid, Wire.channel("cat_begin"), "")
    end

    function c.onEnd(actor)
        local ok, eid = pcall(platform.actorId, actor)
        local cat = ok and eid and c.cats[eid]
        if cat and cat.actor == actor then cat.actor = nil end
    end

    -- B1 cat binding on_lua_message, from the B2 adapter.
    function c.onMessage(actor, channel, payload)
        local kind = Wire.kind(channel)
        if kind ~= "scale" and kind ~= "anim" then return end
        local cat = catFor(actor)
        if not cat then return end
        if not cat.actor then cat.actor = actor end
        if kind == "scale" then
            cat.scale = tonumber(payload)
            applyScale(cat)
            return
        end
        -- "name|seconds|back" or "name|seconds|back|1": the last field marks a reaction the player just
        -- asked for (a panel button); it is shown at once, whatever else the cat was doing
        local name, seconds, back, force = tostring(payload):match("^([^|]*)|([^|]*)|([^|]*)|?(.*)$")
        if not name or name == "" then return end
        local why = force ~= "1" and blocked(cat) or nil
        if why then
            log("skipped " .. name .. " on " .. tostring(cat.eid) .. " (" .. why .. ")")
            return
        end
        if play(cat, name) then
            seconds = tonumber(seconds) or 0
            if seconds > 0 and back ~= "" then
                cat.backAt, cat.back = c.t + seconds, back
            else
                cat.backAt, cat.back = nil, nil
            end
        end
    end

    -- B1 Main on_tick, real seconds.
    function c.tick(dt)
        c.t = c.t + (dt or 0)
        c.sincePoll = c.sincePoll + (dt or 0)
        local poll = c.sincePoll >= CatB1.POLL
        if poll then c.sincePoll = 0 end
        for _, cat in pairs(c.cats) do
            if cat.actor then
                if cat.reapply and cat.reapply[1] and c.t >= cat.reapply[1] then
                    table.remove(cat.reapply, 1)
                    applyScale(cat)
                end
                if poll then
                    local ok, now = pcall(platform.currentVat, cat.actor)
                    now = ok and lower(now) or cat.lastSeen
                    if now ~= cat.lastSeen then
                        -- something other than us changed the animation: the game is playing
                        if cat.lastSeen ~= nil or cat.ours ~= nil then
                            if now ~= cat.ours then
                                cat.foreignAt = c.t
                                cat.backAt, cat.back = nil, nil
                            end
                        end
                        cat.lastSeen = now
                    end
                end
                if cat.backAt and c.t >= cat.backAt then
                    local back = cat.back
                    cat.backAt, cat.back = nil, nil
                    if not blocked(cat) then play(cat, back) end
                end
            end
        end
    end

    return c
end

return CatB1
