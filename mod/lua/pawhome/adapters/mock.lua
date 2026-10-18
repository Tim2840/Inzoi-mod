-- In-memory game used by the tests and by the UI preview. It implements the adapter
-- contract from core/api.lua and records what the mod asked the "game" to do.
local Mock = {}

function Mock.new(opts)
    opts = opts or {}
    local m = {
        clock = opts.start or (8 * 60),     -- game minutes; day 0, 08:00
        store = opts.store or {},           -- survives "restarts" if the same table is reused
        money = { [1] = opts.money or 1000 },
        members = { [1] = { 101, 102 } },
        strays = opts.strays or {},
        notifications = {},
        buffs = {},
        animations = {},
        entities = {},
        nextEntity = 1,
        spawned = 0,
        failSpawn = false,
        localeName = opts.locale or "en",
        caps = opts.caps or { spawn = true, moveStray = true, buffs = true, animate = true },
    }

    function m.now() return m.clock end
    function m.saveGet(key) return m.store[key] end
    function m.saveSet(key, value) m.store[key] = value end
    function m.locale() return m.localeName end
    function m.notify(hid, kind, text)
        m.notifications[#m.notifications + 1] = { household = hid, kind = kind, text = text }
    end
    function m.householdMembers(hid) return m.members[hid] or {} end
    function m.funds(hid) return m.money[hid] or 0 end
    function m.charge(hid, amount)
        if (m.money[hid] or 0) < amount then return false end
        m.money[hid] = m.money[hid] - amount
        return true
    end
    function m.addBuff(zoi, buff, minutes)
        m.buffs[#m.buffs + 1] = { zoi = zoi, buff = buff, minutes = minutes, at = m.clock }
    end
    function m.listStrays() return m.strays end
    function m.bringStray(ref, hid)
        local id = m.nextEntity; m.nextEntity = id + 1
        m.entities[id] = { household = hid, from = ref }
        return id
    end
    function m.spawnPet(hid, spec)
        if m.failSpawn then return nil end
        local id = m.nextEntity; m.nextEntity = id + 1
        m.entities[id] = { household = hid, spec = spec }
        m.spawned = m.spawned + 1
        return id
    end
    function m.entityExists(ref) return m.entities[ref] ~= nil end
    function m.despawnPet(ref) m.entities[ref] = nil end
    function m.releaseStray(ref, spec) m.strays[#m.strays + 1] = { id = "released" .. #m.strays, ref = ref, spec = spec } end
    function m.playAnimation(ref, anim) m.animations[#m.animations + 1] = { ref = ref, anim = anim } end

    return m
end

return Mock
