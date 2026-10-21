-- Adapter for the official ModKit route (ADR 0007, 0008; design: docs/design/modkit-runtime.md).
-- Runs on the B2 (simulation) thread. Every game call goes through `platform`, a table of
-- small functions implemented by adapters/inzoi_platform.lua in the game and by a fake in
-- the tests:
--   platform.time()                      -> day, hour, minute
--   platform.possessed()                 -> entity id (number) of the Zoi the player controls, or nil
--   platform.household(zoiId)            -> household id or nil
--   platform.householdMembers(hid)       -> { zoi ids }
--   platform.funds(hid)                  -> number
--   platform.charge(hid, amount)         -> true when the money was taken
--   platform.send(entityId, channel, payload)        B2 -> B1 message (inzoi.message.send_to_client)
--   platform.enqueue(zoiId, targetId, interactionBagId) -> true when queued
--   platform.atHome(zoiId)               -> true when the Zoi is on the household's lot
--   platform.homeCats()                  -> entity ids of the summoned cats on the home lot (optional)
--   platform.homeObjects(watched)        -> object row ids from `watched` found on the home lot (optional)
--   platform.log(line)                   optional
--
-- Looks (option a of docs/research/walking-cat.md): the cat cannot walk, but it can play the
-- nine animations baked into it and be shown smaller as a kitten. The B1 cat binding does
-- that on the cat's actor; this side decides what and when and sends it to the cat's entity:
--   "pawhome:anim"  "<sequence>|<seconds>|<sequence to return to>"   (seconds 0 = a loop)
--   "pawhome:scale" "<scale>"
-- The B1 side answers "pawhome:cat_begin" whenever the cat's actor (re)appears.
--
-- Saving: B2 cannot write the savegame. The UI keeps the data in wf.state (saved inside the
-- game's save file) and hands it over after every load; until then slotId() returns nil and
-- the engine pauses (see core/api.lua). saveSet sends the new value back to the UI.
--
-- Cats: our "home cat" is a DEV_Void_Cat summoned by the data script PawHome_SpawnCat that
-- runs at the end of the interaction PawHome_WelcomeCat. The cat appears in front of the
-- Zoi, so the interaction is only started while the Zoi is at home; spawnPet returns a
-- placeholder ref ("pending:<n>") at once and binds it to the real entity when the cat
-- binding reports a new cat on the household's lot. Sending a cat away waits the same way.
local Wire = require("pawhome.adapters.inzoi_wire")
local Serialize = require("pawhome.core.serialize")
local Anim = require("pawhome.data.animations")

local ModKit = {
    HELLO_EVERY_SECONDS = 5,
    HELLO_WHEN_READY_SECONDS = 60,
    PENDING_MINUTES = 180,       -- give up on a summon after 3 game hours; the engine retries
    MET_CAT_MINUTES = 3 * 1440,  -- city cats the Zoi met within 3 game days can be adopted
    REFS_KEY = "pawhome.refs",
    SAVE_KEY = "pawhome.save",   -- core/storage.lua Storage.KEY: the engine's data
    BACKUP_EVERY_SECONDS = 30,   -- at most one backup copy to the relay per 30 real seconds
    WELCOME = "PawHome_WelcomeCat",
    SEND_AWAY = "PawHome_SendAway",
    GIFT_PREFIX = "PawHome_Gift_",
    -- The care the player gives from the cat's own interaction menu (all vanilla interactions
    -- except the first two, which the mod appends to the menu in bridge.js).
    CARE = {
        Object_Void_Cat_Dev = "feed", Giving_Snack_To_Cat = "feed", Giving_Catnip_Candy_To_Cat = "feed",
        Object_Void_Cat_Tickle = "play", Playing_Toy_With_Cat = "play",
        Petting_Cat = "cuddle",
    },
    -- our entry interactions (rows added by mod/ui/bridge.js) -> where the shop opens
    OPEN = {
        PawHome_ShopPhone = { shell = "phone" },
        PawHome_Adopt = { shell = "phone", tab = "adopt" },   -- on a city cat
    },
}

function ModKit.new(platform, opts)
    opts = opts or {}
    local a = {
        caps = { spawn = opts.spawn == true, moveStray = false, buffs = false,
                 animate = opts.animate == true, scale = opts.scale == true },
        random = opts.random or math.random,
        platform = platform,
        session = opts.session or tostring(math.random(100000, 999999)),
        ready = false,
        cache = {},
        listeners = {},
        assembler = Wire.assembler(),
        nextMsg = 0,
        sinceHello = math.huge,
        refs = {},          -- placeholder ref -> entity id
        pending = {},       -- list of { ref, at, household, queued }
        leaving = {},       -- cat entity ids to send away once the Zoi is home
        gifts = {},         -- gift interactions waiting for the Zoi: { household, bag }
        nextPending = 1,
        cats = {},          -- entity id -> { home = bool, site = id }
        met = {},           -- entity id -> game minute the possessed Zoi last cared for it
        careLog = {},       -- entity id -> list of { kind, zoi, at } not yet taken by the engine
        backupDirty = false,
        sinceBackup = math.huge,
        backupOffer = nil,  -- { day, cache } from the relay when the savegame had no data
        coats = {},         -- pet ref -> coat texture name (from the engine, see setCoats)
        coatsSent = nil,    -- the last coat list sent to B1
        rpc = nil,          -- function(method, args) -> result table
        looks = {},         -- pet ref -> { mood, stage, scale } from the engine
        shown = {},         -- cat entity id -> { scale, base, nextIdle, busyUntil }
        busy = {},          -- cat entity id -> true while a game interaction runs on it
    }

    local function log(line)
        if platform.log then pcall(platform.log, "[PawHome] " .. line) end
    end

    local function target()
        return platform.possessed()
    end

    local function sendLong(kind, data)
        local eid = target()
        if eid == nil then return false end
        a.nextMsg = a.nextMsg + 1
        for _, part in ipairs(Wire.split(a.session, tostring(a.nextMsg), data)) do
            platform.send(eid, Wire.channel(kind), part)
        end
        return true
    end

    -- ------------------------------------------------------------ adapter contract

    function a.now()
        local d, h, m = platform.time()
        return d * 1440 + h * 60 + m
    end

    function a.slotId() return a.ready and a.session or nil end

    function a.saveGet(key) return a.cache[key] end

    function a.saveSet(key, value)
        a.cache[key] = value
        sendLong("save", Wire.toJson({ key = key, value = value }))
        a.backupDirty = true
    end

    -- Backups: the savegame keeps our data in the UI's wf.state, which is lost when the game
    -- is saved while the UI mod is off. The relay keeps a copy per household in the mod's
    -- settings files (uimod.cfg_save), outside the savegame. Copies without pets are not sent,
    -- so an empty new start never overwrites a good backup.
    local function petCount(cache)
        local state = cache[ModKit.SAVE_KEY] and Serialize.decode(cache[ModKit.SAVE_KEY])
        local n = 0
        for _, pet in ipairs(type(state) == "table" and type(state.pets) == "table" and state.pets or {}) do
            if pet.status == "home" or pet.status == "impounded" then n = n + 1 end
        end
        return n
    end

    local function sendBackup()
        local hid = platform.household and platform.household()
        if hid == nil or petCount(a.cache) == 0 then return end
        if sendLong("backup", Wire.toJson({ hid = hid, day = math.floor(a.now() / 1440), cache = a.cache })) then
            a.backupDirty = false
        end
    end

    function a.backup() return a.backupOffer end

    function a.restoreBackup()
        local offer = a.backupOffer
        if not offer then return false end
        a.backupOffer = nil
        for key, value in pairs(offer.cache) do
            if type(value) == "string" then a.saveSet(key, value) end
        end
        local refs = a.cache[ModKit.REFS_KEY] and Serialize.decode(a.cache[ModKit.REFS_KEY])
        a.refs = type(refs) == "table" and refs or {}
        log("backup from day " .. tostring(offer.day) .. " restored")
        a.scanHomeCats()
        return true
    end

    function a.subscribe(event, fn)
        if event == "slot_changed" then a.listeners[#a.listeners + 1] = fn end
    end

    function a.locale() return a.localeName or "en" end

    function a.notify(householdId, kind, text)
        local eid = target()
        if eid == nil then return end
        platform.send(eid, Wire.channel("toast"), tostring(text))
    end

    function a.householdMembers(hid) return platform.householdMembers(hid) or {} end
    function a.funds(hid) return platform.funds(hid) or 0 end
    function a.charge(hid, amount) return platform.charge(hid, amount) == true end
    -- a gift item: a tiny self interaction (row PawHome_Gift_<object id>, added by mod/ui/bridge.js)
    -- whose finish script puts the object in the Zoi's bag; queued like the summon interaction
    function a.giveItem(hid, objectId)
        a.gifts[#a.gifts + 1] = { household = hid, bag = ModKit.GIFT_PREFIX .. tostring(objectId) }
        a.serviceQueue()
        return true
    end
    function a.homeObjects(hid, watched)
        if not platform.homeObjects then return {} end
        return platform.homeObjects(watched) or {}
    end

    local function persistRefs()
        a.saveSet(ModKit.REFS_KEY, Serialize.encode(a.refs))
    end

    local function resolve(ref)
        if type(ref) == "number" then return ref end
        return a.refs[ref]
    end

    -- Coats (docs/research/fixed-coat.md): the game re-rolls a cat's coat whenever its actor
    -- is created, and only the game thread (B1) can change it. B2 sends B1 the list
    -- "<entity id>=<texture>;..." of our cats; the B1 cat binding applies it.
    local function coatText()
        local parts = {}
        for ref, texture in pairs(a.coats) do
            local eid = resolve(ref)
            if eid ~= nil then parts[#parts + 1] = tostring(eid) .. "=" .. texture end
        end
        table.sort(parts)
        return table.concat(parts, ";")
    end

    function a.sendCoats(force)
        if not a.ready then return end
        local text = coatText()
        if not force and text == a.coatsSent then return end
        if sendLong("coats", text) then a.coatsSent = text end
    end

    function a.setCoats(list)
        local map = {}
        for _, c in ipairs(list or {}) do
            if c.ref ~= nil and type(c.texture) == "string" then map[c.ref] = c.texture end
        end
        a.coats = map
        a.sendCoats(false)
    end

    function a.spawnPet(householdId, spec)
        if not a.caps.spawn then return nil end
        local ref = "pending:" .. a.session .. ":" .. a.nextPending
        a.nextPending = a.nextPending + 1
        a.pending[#a.pending + 1] = { ref = ref, at = a.now(), household = householdId, queued = false }
        log("summon waiting for the Zoi to be home: " .. ref)
        a.serviceQueue()
        return ref
    end

    function a.entityExists(ref)
        local eid = resolve(ref)
        if eid ~= nil then return a.cats[eid] ~= nil end
        for _, p in ipairs(a.pending) do
            -- waiting for the Zoi to come home counts as present; after the summon was
            -- started, give it a few game hours before the engine may try again
            if p.ref == ref then return not p.queued or a.now() - p.at < ModKit.PENDING_MINUTES end
        end
        return false
    end

    function a.despawnPet(ref)
        local eid = resolve(ref)
        for i = #a.pending, 1, -1 do
            if a.pending[i].ref == ref then table.remove(a.pending, i) end
        end
        if type(ref) == "string" and a.refs[ref] then
            a.refs[ref] = nil
            persistRefs()
        end
        if eid == nil or a.cats[eid] == nil then return end
        a.leaving[#a.leaving + 1] = eid
        a.serviceQueue()
    end

    -- Starts the summon / goodbye interactions that wait for the Zoi to be at home.
    function a.serviceQueue()
        local zoi = target()
        if zoi == nil then return end
        for i = #a.gifts, 1, -1 do                     -- a gift does not wait for the Zoi to be home
            if platform.enqueue(zoi, zoi, a.gifts[i].bag) then table.remove(a.gifts, i) end
        end
        if not platform.atHome(zoi) then return end
        for _, p in ipairs(a.pending) do
            if not p.queued and platform.enqueue(zoi, zoi, ModKit.WELCOME) then
                p.queued, p.at = true, a.now()
                log("summon started " .. p.ref)
            end
        end
        for i = #a.leaving, 1, -1 do
            local eid = a.leaving[i]
            if a.cats[eid] == nil or platform.enqueue(zoi, eid, ModKit.SEND_AWAY) then
                table.remove(a.leaving, i)
            end
        end
    end

    -- City cats the player's Zoi has fed or played with recently.
    function a.listStrays(householdId)
        local out, now = {}, a.now()
        local owned = {}
        for _, eid in pairs(a.refs) do owned[eid] = true end
        for eid, at in pairs(a.met) do
            local cat = a.cats[eid]
            if cat and not cat.home and not owned[eid] and now - at < ModKit.MET_CAT_MINUTES then
                out[#out + 1] = { id = "cat" .. eid, ref = eid, stage = "adult", appearance = eid }
            end
        end
        table.sort(out, function(x, y) return x.ref < y.ref end)
        return out
    end

    -- ------------------------------------------------------------ looks

    local function catOf(ref)
        local eid = resolve(ref)
        if eid ~= nil and a.cats[eid] ~= nil then return eid end
        return nil
    end

    local function refOf(eid)
        for ref, e in pairs(a.refs) do if e == eid then return ref end end
        return nil
    end

    local function shownOf(eid)
        local st = a.shown[eid]
        if not st then st = {}; a.shown[eid] = st end
        return st
    end

    local function moodDef(ref)
        local look = a.looks[ref]
        return Anim.moods[look and look.mood or "content"] or Anim.moods.content
    end

    -- force: a reaction the player asked for; B1 shows it at once instead of waiting for the game's
    -- own animation changes to settle
    local function sendAnim(eid, key, backKey, force)
        local seq = Anim.sequences[key]
        if not seq then return false end
        local back = backKey and Anim.sequences[backKey]
        platform.send(eid, Wire.channel("anim"),
            seq.name .. "|" .. tostring(seq.seconds or 0) .. "|" .. (back and back.name or "") .. (force and "|1" or ""))
        local st = shownOf(eid)
        if seq.loop then st.base = key elseif back then st.base = backKey end
        -- a game minute is about 2 real seconds at normal speed; B1 also refuses to cut a
        -- one-shot short, so this only keeps B2 from sending in the meantime
        if seq.seconds then st.busyUntil = a.now() + math.ceil(seq.seconds / 2) + 1 end
        return true
    end

    local function sendScale(eid, scale)
        platform.send(eid, Wire.channel("scale"), string.format("%.3f", scale))
        shownOf(eid).scale = scale
    end

    local function free(eid)
        if a.busy[eid] then return false end
        local st = a.shown[eid]
        return not (st and st.busyUntil and a.now() < st.busyUntil)
    end

    -- care from the panel: the matching one-shot, then back to the mood's sitting idle
    function a.playAnimation(ref, id)
        if not a.caps.animate then return false end
        local eid, key = catOf(ref), Anim.actions[id]
        -- only the game's own interaction on the cat holds this back, not our earlier animation
        if eid == nil or key == nil or a.busy[eid] then return false end
        return sendAnim(eid, key, moodDef(ref).base, true)
    end

    -- force: send even if it was sent before (a message to a cat whose actor is not ready
    -- yet is lost, e.g. right after a summon; the idle timer repeats the size now and then)
    local function showScale(eid, ref, force)
        local look = a.looks[ref]
        if a.caps.scale and look and look.scale and (force or shownOf(eid).scale ~= look.scale) then
            sendScale(eid, look.scale)
        end
    end

    function a.petLook(ref, look)
        if type(look) ~= "table" then return false end
        a.looks[ref] = look
        local eid = catOf(ref)
        if eid ~= nil then showScale(eid, ref) end
        return true
    end

    -- Now and then, each cat at home shows its mood: mostly the sitting idle that suits it,
    -- sometimes a short reaction. Nothing is sent while the game itself plays on the cat.
    local function idleStep()
        local now, cfg = a.now(), Anim.idle
        for ref in pairs(a.looks) do
            local eid = catOf(ref)
            if eid ~= nil and a.cats[eid].home then
                local st = shownOf(eid)
                if st.nextIdle == nil then
                    st.nextIdle = now + a.random(0, cfg.everyMinutes)   -- stagger the cats
                    showScale(eid, ref, true)
                elseif now >= st.nextIdle and not a.caps.animate then
                    st.nextIdle = now + cfg.everyMinutes
                    showScale(eid, ref, true)
                elseif now >= st.nextIdle and free(eid) then
                    st.nextIdle = now + cfg.everyMinutes + a.random(-cfg.jitterMinutes, cfg.jitterMinutes)
                    showScale(eid, ref, true)
                    local def = moodDef(ref)
                    local pick
                    if #def.extra > 0 and a.random() < cfg.extraChance then
                        local total = 0
                        for _, e in ipairs(def.extra) do total = total + e[2] end
                        local roll = a.random() * total
                        for _, e in ipairs(def.extra) do
                            roll = roll - e[2]
                            if roll <= 0 then pick = e[1] break end
                        end
                        pick = pick or def.extra[#def.extra][1]
                    end
                    if pick then sendAnim(eid, pick, def.base)
                    elseif st.base ~= def.base then sendAnim(eid, def.base) end
                end
            end
        end
    end
    a.idleStep = idleStep

    -- The B1 cat binding saw the cat's actor (re)appear: it starts at the game's size and
    -- animation, so show the pet's look again.
    function a.onCatMessage(eid, kind)
        if kind ~= "cat_begin" or a.cats[eid] == nil then return end
        local ref = refOf(eid)
        if ref == nil then return end
        local st = shownOf(eid)
        st.scale = nil
        showScale(eid, ref)
        if a.caps.animate and st.base and free(eid) then sendAnim(eid, st.base) end
    end

    -- a game interaction on one of our cats: keep our animations off it meanwhile
    local function markBusy(ev)
        local eid = ev and tonumber(ev.target_entity_id)
        if eid ~= nil and a.cats[eid] ~= nil then a.busy[eid] = true end
    end

    -- canceled / failed / finished: the game leaves the cat in the interaction's last
    -- pose; the next idle change puts it back on its sitting idle a little later
    function a.onInteractionEnded(ev)
        local eid = ev and tonumber(ev.target_entity_id)
        if eid ~= nil and a.busy[eid] then
            a.busy[eid] = nil
            local st = shownOf(eid)
            st.base = nil
            st.nextIdle = a.now() + 2
        end
    end

    -- ------------------------------------------------------------ events from the game

    -- B2 binding tick (any binding, real seconds). Says hello every few seconds until the UI
    -- answers, then once a minute so a UI that was reloaded can find this session again.
    function a.tick(dt)
        a.sinceBackup = a.sinceBackup + (dt or 0)
        -- the player started over instead of restoring: back up the new pets from now on
        if a.backupOffer and a.backupDirty and petCount(a.cache) > 0 then a.backupOffer = nil end
        if a.ready and a.backupDirty and a.backupOffer == nil and a.sinceBackup >= ModKit.BACKUP_EVERY_SECONDS then
            a.sinceBackup = 0
            pcall(sendBackup)
        end
        a.sinceQueue = (a.sinceQueue or 0) + (dt or 0)
        if a.sinceQueue >= ModKit.HELLO_EVERY_SECONDS then
            a.sinceQueue = 0
            if a.ready and (#a.pending > 0 or #a.leaving > 0 or #a.gifts > 0) then a.serviceQueue() end
            if a.ready then idleStep() end
        end
        a.sinceHello = a.sinceHello + (dt or 0)
        local every = a.ready and ModKit.HELLO_WHEN_READY_SECONDS or ModKit.HELLO_EVERY_SECONDS
        if a.sinceHello >= every then
            local eid = target()
            if eid ~= nil then
                platform.send(eid, Wire.channel("hello"), a.session)
                a.sinceHello = 0
                if a.ready then a.sendCoats(true) end
            end
        end
    end

    local function onState(data)
        if a.ready then
            -- A UI that was reloaded during the session (mod remount) starts with an empty
            -- wf.state: the game restores it only when a save is loaded. Keep our data and
            -- give the UI a full copy instead of taking its (empty) one.
            local count = 0
            for key, value in pairs(a.cache) do
                sendLong("save", Wire.toJson({ key = key, value = value }))
                count = count + 1
            end
            log("UI reconnected; sent it " .. count .. " keys")
            return
        end
        local t, err = Wire.fromJson(data ~= "" and data or "{}")
        if type(t) ~= "table" then
            log("state from UI is unreadable: " .. tostring(err))
            t = {}
        end
        a.cache = {}
        for k, v in pairs(t) do
            if type(v) == "string" then a.cache[k] = v end
        end
        local refs = a.cache[ModKit.REFS_KEY] and Serialize.decode(a.cache[ModKit.REFS_KEY])
        a.refs = type(refs) == "table" and refs or {}
        a.ready = true
        log("state received (" .. #data .. " bytes)")
        if a.cache[ModKit.SAVE_KEY] == nil then
            -- nothing in this savegame: ask the relay whether it kept a copy for this household
            local hid, eid = platform.household and platform.household(), target()
            if hid ~= nil and eid ~= nil then
                platform.send(eid, Wire.channel("backup_get"), a.session .. "|" .. tostring(hid))
            end
        end
        a.scanHomeCats()
        for _, fn in ipairs(a.listeners) do pcall(fn) end
    end

    local function onRpc(data)
        local req = Wire.fromJson(data)
        if type(req) ~= "table" then return end
        local result
        if not a.ready then
            result = { error = "not_ready" }
        elseif a.rpc then
            local ok, r = pcall(a.rpc, req.method, req.args or {})
            result = ok and r or { error = tostring(r) }
        else
            result = { error = "not_ready" }
        end
        sendLong("rpc_result", Wire.toJson({ id = req.id, result = result }))
    end

    -- B2 Zoi binding on_lua_message(self, owner, channel, payload).
    function a.onMessage(channel, payload)
        local kind = Wire.kind(channel)
        if kind ~= "state" and kind ~= "rpc" and kind ~= "backup_data" then return end
        local session, _, data = a.assembler.add(payload)
        if data == nil then return end
        if session ~= a.session then return end      -- an answer to an earlier game session
        if kind == "state" then onState(data)
        elseif kind == "rpc" then onRpc(data)
        else
            local t = data ~= "" and Wire.fromJson(data)
            -- the engine offers it only while this savegame has no pets (App:backupInfo)
            if type(t) == "table" and type(t.cache) == "table" and petCount(t.cache) > 0 then
                a.backupOffer = { day = t.day, cache = t.cache }
                log("relay has a backup from day " .. tostring(t.day))
            end
        end
    end

    -- ObjectTemplate binding on a cat: on_begin. info = { home = bool, site = id }.
    function a.onCatBegin(eid, info)
        info = info or {}
        a.cats[eid] = { home = info.home == true, site = info.site }
        if not info.home then return end
        for _, ref in pairs(a.refs) do if ref == eid then return end end
        local p = table.remove(a.pending, 1)
        if p then
            a.refs[p.ref] = eid
            log("summoned cat " .. tostring(eid) .. " is " .. p.ref)
            persistRefs()
            showScale(eid, p.ref)
            a.sendCoats(false)
        end
    end

    function a.onCatEnd(eid)
        a.cats[eid], a.shown[eid], a.busy[eid] = nil, nil, nil
    end

    -- Summoned cats are not reported by the cat binding, so after our welcome interaction
    -- the home lot is searched for cats we do not know yet.
    function a.scanHomeCats()
        if not platform.homeCats then return end
        local ok, list = pcall(platform.homeCats)
        if not ok or type(list) ~= "table" then return end
        for _, eid in ipairs(list) do
            if a.cats[eid] == nil or not a.cats[eid].home then a.onCatBegin(eid, { home = true }) end
        end
    end

    -- interaction.started event: the player's Zoi picked one of our entries (phone, computer,
    -- "adopt" on a city cat) -> the page shows the shop. Event fields as in interaction.finished.
    function a.onInteractionStarted(ev)
        markBusy(ev)
        local entry = ev and ModKit.OPEN[ev.interaction_bag_id]
        if not entry or ev.entity_id ~= target() then return false end
        local open = { shell = entry.shell, tab = entry.tab }
        local cat = ev.target_entity_id
        if entry.tab == "adopt" and cat then
            -- the entry is on every DEV_Void_Cat, our home cats included: those are already ours
            for _, eid in pairs(a.refs) do if eid == cat then return false end end
            if a.cats[cat] and a.cats[cat].home then return false end
            a.cats[cat] = a.cats[cat] or { home = false }   -- missed by the binding (hot remount)
            a.met[cat] = a.now()                             -- choosing "adopt" counts as meeting it
            open.stray = "cat" .. tostring(cat)
        end
        return sendLong("open", Wire.toJson(open))
    end

    -- interaction.finished event: summoned cats, city cats the player met, and care given.
    function a.onInteractionFinished(ev)
        a.onInteractionEnded(ev)
        if ev and ev.interaction_bag_id == ModKit.WELCOME then
            a.scanHomeCats()
            return
        end
        local kind = ev and ModKit.CARE[ev.interaction_bag_id]
        if not kind then return end
        local eid = ev.target_entity_id
        if ev.entity_id == target() then a.met[eid] = a.now() end
        local list = a.careLog[eid] or {}
        list[#list + 1] = { kind = kind, zoi = ev.entity_id, at = a.now() }
        a.careLog[eid] = list
    end

    -- Care events for one of our pets since the last call (the engine applies them).
    function a.takeCare(ref)
        local eid = resolve(ref)
        if eid == nil then return {} end
        local list = a.careLog[eid] or {}
        a.careLog[eid] = nil
        return list
    end

    return a
end

return ModKit
