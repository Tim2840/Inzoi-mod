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
        spawnCalls = 0,
        hidden = {},            -- entities that exist but are not reported (like an unloaded level)
        generations = {},       -- older saves per key, newest first (like the .bak files)
        failSpawn = false,
        localeName = opts.locale or "en",
        slot = (not opts.noSave) and (opts.slot or "slot1") or nil,   -- noSave: start on the loading screen
        slotted = opts.slotted or false,        -- true: one data file per savegame slot (like the UE4SS adapter)
        listeners = {},
        caps = opts.caps or { spawn = true, moveStray = true, buffs = true, animate = true },
    }

    function m.now() return m.clock end
    m.rejectedWrites = 0
    local function k(key)
        if not m.slotted then return key end
        if m.slot == nil then return nil end      -- no save loaded: reads are empty, writes are rejected
        return m.slot .. "|" .. key
    end
    function m.saveGet(key)
        local name = k(key)
        return name and m.store[name] or nil
    end
    function m.saveSet(key, value)
        local name = k(key)
        if not name then m.rejectedWrites = m.rejectedWrites + 1 return end
        local old = m.store[name]
        if old ~= nil and old ~= value then
            local gens = m.generations[name] or {}
            table.insert(gens, 1, old)
            while #gens > 3 do table.remove(gens) end
            m.generations[name] = gens
        end
        m.store[name] = value
    end
    function m.saveGetBackup(key, n)
        local name = k(key)
        local gens = name and m.generations[name]
        return gens and gens[n] or nil
    end
    if opts.slotted then
        function m.slotId() return m.slot end
        -- the "player" loads another save
        function m.switchSlot(name)
            m.slot = name
            for _, fn in ipairs(m.listeners) do fn() end
        end
    end
    if opts.subscribe then
        function m.subscribe(event, fn)
            if event == "slot_changed" then m.listeners[#m.listeners + 1] = fn end
        end
    end
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
        m.spawnCalls = m.spawnCalls + 1
        if m.failSpawn then return nil end
        local id = m.nextEntity; m.nextEntity = id + 1
        m.entities[id] = { household = hid, spec = spec }
        m.spawned = m.spawned + 1
        return id
    end
    function m.entityExists(ref) return m.entities[ref] ~= nil and not m.hidden[ref] end
    function m.despawnPet(ref) m.entities[ref] = nil end
    m.coatList = nil                    -- the last list the mod gave setCoats
    function m.setCoats(list) m.coatList = list end
    function m.playAnimation(ref, anim) m.animations[#m.animations + 1] = { ref = ref, anim = anim } end
    m.looks = {}                        -- ref -> the last look the engine asked for
    function m.petLook(ref, look) m.looks[ref] = look end
    m.backupOffer = nil                 -- { day, cache } the tests put here
    function m.backup() return m.backupOffer end
    function m.restoreBackup()
        if not m.backupOffer then return false end
        for key, value in pairs(m.backupOffer.cache) do m.saveSet(key, value) end
        m.backupOffer = nil
        return true
    end
    m.lot = {}                          -- household id -> object row ids on its lot
    function m.homeObjects(hid, watched)
        local want, out = {}, {}
        for _, id in ipairs(watched or {}) do want[id] = true end
        for _, id in ipairs(m.lot[hid] or {}) do
            if want[id] then out[#out + 1] = id end
        end
        return out
    end
    m.care = {}
    function m.giveCare(ref, kind, zoi)
        local list = m.care[ref] or {}
        list[#list + 1] = { kind = kind, zoi = zoi }
        m.care[ref] = list
    end
    function m.takeCare(ref)
        local list = m.care[ref] or {}
        m.care[ref] = nil
        return list
    end

    return m
end

return Mock
