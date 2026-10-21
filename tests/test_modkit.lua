-- The ModKit route end to end, without the game: B2 adapter <-> B1 relay <-> a fake UI that
-- follows the same protocol as mod/ui/bridge.js, with the real engine and RPC on top.
local T = require("framework")
local Wire = require("pawhome.adapters.inzoi_wire")
local ModKit = require("pawhome.adapters.inzoi")
local Relay = require("pawhome.adapters.inzoi_relay")
local App = require("pawhome.app")
local Rpc = require("pawhome.rpc")
local Storage = require("pawhome.core.storage")

-- ------------------------------------------------------------------ fake world

local function world(opts)
    opts = opts or {}
    local w = {
        day = 3, hour = 8, minute = 0,
        zoi = 501, household = 77, members = { 501, 502 },
        money = opts.money or 5000,
        cfg = opts.cfg or {},     -- "section/key" -> value (the mod's settings files; survive loads)
        toSim = {}, toClient = {}, -- queued inzoi.message deliveries
        toasts = {},
        queued = {},              -- interactions put in the Zoi's queue
        home = true,              -- is the Zoi on the household's lot
        uiState = opts.uiState,   -- what wf.state.pawhome held when the save was loaded
        catMsgs = {},             -- messages the B2 adapter sent to cat entities
    }
    w.b2 = {
        time = function() return w.day, w.hour, w.minute end,
        possessed = function() return w.zoi end,
        household = function() return w.household end,
        householdMembers = function() return w.members end,
        funds = function() return w.money end,
        charge = function(_, amount)
            if w.money < amount then return false end
            w.money = w.money - amount
            return true
        end,
        send = function(eid, ch, payload) w.toClient[#w.toClient + 1] = { eid, ch, payload } end,
        atHome = function() return w.home end,
        enqueue = function(zoi, target, bag)
            w.queued[#w.queued + 1] = { zoi = zoi, target = target, bag = bag }
            return true
        end,
    }
    w.b1 = {
        cfgSave = function(s, k, v) w.cfg[s .. "/" .. k] = v return true end,
        cfgLoad = function(s, k) return w.cfg[s .. "/" .. k] end,
        sendToSim = function(eid, ch, payload) w.toSim[#w.toSim + 1] = { eid, ch, payload } end,
        toast = function(text) w.toasts[#w.toasts + 1] = text end,
    }
    return w
end

-- A UI that speaks the bridge.js protocol (kept deliberately literal).
local function fakeUi(w, state)
    local ui = { state = state or {}, session = nil, answered = nil, outbox = {}, nextSeq = 1,
                 lastSeen = 0, relayEpoch = nil, nextRpc = 1, results = {}, epoch = "ui1" }
    local function send(channel, data)
        ui.outbox[#ui.outbox + 1] = { seq = ui.nextSeq, channel = channel, payload = ui.session .. "|" .. data }
        ui.nextSeq = ui.nextSeq + 1
        local entries = { { seq = 0, channel = "epoch", payload = ui.epoch } }
        for _, e in ipairs(ui.outbox) do entries[#entries + 1] = e end
        w.cfg["bridge/to_sim"] = Wire.encodeMailbox(entries)
    end
    function ui.poll()
        local entries = Wire.decodeMailbox(w.cfg["bridge/to_ui"])
        local ep = entries[1] and entries[1].channel == "epoch" and entries[1].payload
        if ep ~= ui.relayEpoch then ui.relayEpoch, ui.lastSeen = ep, 0 end
        for _, e in ipairs(entries) do
            if e.seq > ui.lastSeen then
                ui.lastSeen = e.seq
                local from, data = e.payload:match("^([^|]*)|(.*)$")
                if e.channel == "pawhome:hello" then
                    ui.session = from
                elseif from == ui.session and e.channel == "pawhome:save" then
                    local t = Wire.fromJson(data)
                    ui.state[t.key] = t.value
                elseif from == ui.session and e.channel == "pawhome:rpc_result" then
                    local t = Wire.fromJson(data)
                    ui.results[t.id] = t.result
                end
            end
        end
        if ui.session and ui.answered ~= ui.session then
            ui.answered = ui.session
            send("pawhome:state", Wire.toJson(ui.state))
        end
    end
    function ui.call(method, args)
        local id = ui.nextRpc
        ui.nextRpc = id + 1
        send("pawhome:rpc", Wire.toJson({ id = id, method = method, args = args or {} }))
        return id
    end
    return ui
end

-- Wires everything and runs message delivery until nothing moves.
local function boot(opts)
    opts = opts or {}
    local w = world(opts)
    local adapter = ModKit.new(w.b2, { session = opts.session or "S1", spawn = opts.spawn,
        animate = opts.animate, scale = opts.scale, random = opts.random })
    local app = assert(App.new(adapter, { seed = 7 }))
    adapter.rpc = function(method, args)
        return Rpc.handle(app, { household = w.household, zoi = w.zoi }, method, args)
    end
    local relay = Relay.new(w.b1, { epoch = "R1" })
    local scenario = { w = w, adapter = adapter, app = app, relay = relay, ui = fakeUi(w, opts.uiState) }
    local function pump(rounds)
        for _ = 1, rounds or 6 do
            adapter.tick(10)
            while #w.toClient > 0 do
                local m = table.remove(w.toClient, 1)
                if m[1] == w.zoi then
                    relay.onMessage(m[1], m[2], m[3])
                else
                    -- sent to a cat's entity: the B1 cat binding's business
                    w.catMsgs[#w.catMsgs + 1] = { eid = m[1], kind = Wire.kind(m[2]), payload = m[3] }
                end
            end
            scenario.ui.poll()      -- whichever page is loaded right now
            relay.tick(10)
            while #w.toSim > 0 do
                local m = table.remove(w.toSim, 1)
                adapter.onMessage(m[2], m[3])
            end
            app:tick()
        end
    end
    scenario.pump = pump
    return scenario
end

-- ------------------------------------------------------------------ wire

T.test("wire: long payloads are split and put back together in any order", function()
    local data = string.rep("abc|é,;%", 400)
    local parts = Wire.split("S", "9", data, 100)
    T.gt(#parts, 1)
    local asm = Wire.assembler()
    local got
    for i = #parts, 1, -1 do
        local s, id, d = asm.add(parts[i])
        if d then got = { s, id, d } end
    end
    T.eq(got[1], "S"); T.eq(got[2], "9"); T.eq(got[3], data)
end)

T.test("wire: mailbox entries survive characters that would break a command line", function()
    local text = Wire.encodeMailbox({ { seq = 3, channel = "pawhome:save", payload = 'a b"c\n;d,e%' } })
    T.falsy(text:find('[ "\n]'), "no spaces, quotes or line breaks")
    local e = Wire.decodeMailbox(text)[1]
    T.eq(e.seq, 3); T.eq(e.channel, "pawhome:save"); T.eq(e.payload, 'a b"c\n;d,e%')
end)

T.test("wire: JSON round trip of nested tables, unicode and escapes", function()
    local v = { name = "咪咪 \"Mimi\"\n", list = { 1, 2.5, true, false }, nested = { ok = true } }
    local back = Wire.fromJson(Wire.toJson(v))
    T.eq(back.name, v.name); T.eq(back.list[2], 2.5); T.eq(back.list[4], false); T.eq(back.nested.ok, true)
    T.eq(Wire.fromJson('{"a":"\\u54aa"}').a, "咪")
end)

T.test("wire: an empty table is sent to the UI as an empty list", function()
    T.eq(Wire.toJson({}), "[]")
    T.eq(Wire.toJson({ pets = {} }), '{"pets":[]}')
end)

T.test("wire: other mods' channels are ignored", function()
    T.eq(Wire.kind("pawhome:save"), "save")
    T.eq(Wire.kind("AlimonyMoods"), nil)
    T.eq(Wire.kind("zwlsm_out"), nil)
end)

-- ------------------------------------------------------------------ handshake and saving

T.test("modkit: the engine stays paused until the UI hands over the save data", function()
    local w = world()
    local adapter = ModKit.new(w.b2, { session = "S1" })
    T.eq(adapter.slotId(), nil)
    local app = assert(App.new(adapter, { seed = 1 }))
    T.truthy(app:noSave(), "no save loaded yet")
end)

T.test("modkit: a new game starts empty, saves reach wf.state and come back after a reload", function()
    local s = boot()
    s.pump()
    T.eq(s.adapter.slotId(), "S1", "handshake done")
    local offers = s.app:offers(77, true)
    local r = s.app:adoptOffer(77, 501, offers[1].id, "Mimi")
    T.truthy(r.ok, r.message)
    s.pump()
    T.truthy(s.ui.state[Storage.KEY], "the save reached the UI's wf.state")

    -- the player saves and loads: a new B2 session gets the same wf.state from the UI
    local again = boot({ session = "S2", uiState = s.ui.state })
    again.pump()
    T.eq(again.adapter.slotId(), "S2")
    local names = {}
    for _, p in ipairs(again.app:view(77, 501).pets) do names[#names + 1] = p.name end
    T.eq(table.concat(names, ","), "Mimi")
end)

T.test("modkit: answers from an earlier game session are ignored", function()
    local s = boot({ session = "S2" })
    -- a stale state message (session S1) arrives first
    for _, part in ipairs(Wire.split("S1", "x", Wire.toJson({ [Storage.KEY] = "garbage" }))) do
        s.adapter.onMessage("pawhome:state", part)
    end
    T.eq(s.adapter.slotId(), nil, "still waiting for this session's data")
    s.pump()
    T.eq(s.adapter.slotId(), "S2")
end)

T.test("modkit: a UI that was reloaded finds the running session again", function()
    local s = boot()
    s.pump()
    local reloaded = fakeUi(s.w, s.ui.state)
    reloaded.relayEpoch = s.ui.relayEpoch
    reloaded.lastSeen = s.ui.lastSeen          -- it skips what was already in the mailbox
    reloaded.epoch = "ui2"
    s.ui = reloaded
    for _ = 1, 7 do s.adapter.tick(10) end     -- a minute later B2 says hello again
    while #s.w.toClient > 0 do
        local m = table.remove(s.w.toClient, 1)
        s.relay.onMessage(m[1], m[2], m[3])
    end
    reloaded.poll()
    T.eq(reloaded.session, "S1")
    T.eq(reloaded.answered, "S1", "it answered with its wf.state")
end)

T.test("modkit: a UI reloaded mid-session with an empty wf.state does not wipe the pets", function()
    local s = boot()
    s.pump()
    local offers = s.app:offers(77, true)
    T.truthy(s.app:adoptOffer(77, 501, offers[1].id, "Mimi").ok)
    s.pump()
    -- the page is remounted: wf.state is empty until the next save is loaded
    local reloaded = fakeUi(s.w, {})
    reloaded.relayEpoch = s.ui.relayEpoch
    reloaded.lastSeen = s.ui.lastSeen
    reloaded.epoch = "ui3"
    s.ui = reloaded
    for _ = 1, 7 do s.adapter.tick(10) end
    s.pump(3)
    T.eq(s.app:view(77, 501).pets[1].name, "Mimi", "the engine kept its pets")
    T.truthy(reloaded.state[Storage.KEY], "the reloaded UI got a full copy back")
    T.truthy(reloaded.state[Storage.KEY]:find("Mimi"), "including the pet")
end)

T.test("modkit: toasts are shown by the relay, not written to the mailbox", function()
    local s = boot()
    s.pump()
    s.adapter.notify(77, "info", "Mimi is hungry")
    s.pump(1)
    T.eq(s.w.toasts[#s.w.toasts], "Mimi is hungry")
end)

-- ------------------------------------------------------------------ RPC

T.test("modkit: UI calls reach the engine and the answer comes back", function()
    local s = boot()
    s.pump()
    local id = s.ui.call("offers", { refresh = true })
    s.pump()
    local res = s.ui.results[id]
    T.truthy(res and res.offers, "offers came back")
    T.gt(#res.offers, 0)
    T.eq(res.money, 5000)
    local id2 = s.ui.call("adoptOffer", { offerId = res.offers[1].id, name = "Tama" })
    s.pump()
    T.truthy(s.ui.results[id2].result.ok)
    T.eq(s.ui.results[id2].view.pets[1].name, "Tama")
end)

T.test("modkit: unknown RPC methods return an error instead of breaking the bridge", function()
    local s = boot()
    s.pump()
    local id = s.ui.call("dropTables", {})
    s.pump()
    T.truthy(s.ui.results[id].error)
end)

-- ------------------------------------------------------------------ summoned cats

T.test("modkit: adopting with spawn queues the welcome interaction and binds the summoned cat", function()
    local s = boot({ spawn = true })
    s.pump()
    local offers = s.app:offers(77, true)
    local r = s.app:adoptOffer(77, 501, offers[1].id, "Mimi")
    T.truthy(r.ok, r.message)
    T.eq(s.w.queued[1].bag, ModKit.WELCOME)
    local pet = s.app:view(77, 501).pets[1]
    -- a city cat appearing elsewhere is not ours
    s.adapter.onCatBegin(9001, { home = false })
    -- the summoned cat appears on the household's lot
    s.adapter.onCatBegin(109546, { home = true })
    s.pump()
    T.truthy(pet)
    T.truthy(s.adapter.entityExists(s.app.ctx.state.pets[1].entity), "bound to the real cat")
    T.eq(s.adapter.refs[s.app.ctx.state.pets[1].entity], 109546)
end)

T.test("modkit: the placeholder-to-cat mapping survives save and load", function()
    local s = boot({ spawn = true })
    s.pump()
    local offers = s.app:offers(77, true)
    T.truthy(s.app:adoptOffer(77, 501, offers[1].id, "Mimi").ok)
    s.adapter.onCatBegin(109546, { home = true })
    s.pump()
    local again = boot({ session = "S2", uiState = s.ui.state, spawn = true })
    again.adapter.onCatBegin(109546, { home = true })
    again.pump()
    local ref = again.app.ctx.state.pets[1].entity
    T.eq(again.adapter.refs[ref], 109546)
    T.truthy(again.adapter.entityExists(ref))
    T.eq(#again.w.queued, 0, "no second cat is summoned")
end)

T.test("modkit: a cat adopted away from home is summoned when the Zoi gets home", function()
    local s = boot({ spawn = true })
    s.pump()
    s.w.home = false
    local offers = s.app:offers(77, true)
    T.truthy(s.app:adoptOffer(77, 501, offers[1].id, "Mimi").ok, "adopting works anywhere")
    T.eq(#s.w.queued, 0, "nothing is summoned at the gym")
    s.w.hour = s.w.hour + 6
    T.truthy(s.adapter.entityExists(s.app.ctx.state.pets[1].entity), "still counted as on its way")
    s.w.home = true
    s.pump(1)
    T.eq(s.w.queued[1].bag, ModKit.WELCOME, "summoned once home")
    T.eq(#s.w.queued, 1)
end)

T.test("modkit: a summon that never shows up is given up after a while so the engine retries", function()
    local s = boot({ spawn = true })
    s.pump()
    local ref = s.adapter.spawnPet(77, {})
    T.truthy(s.adapter.entityExists(ref))
    s.w.hour = s.w.hour + 4
    T.falsy(s.adapter.entityExists(ref))
end)

T.test("modkit: sending a pet away queues the goodbye interaction on its cat", function()
    local s = boot({ spawn = true })
    s.pump()
    local ref = s.adapter.spawnPet(77, {})
    s.adapter.onCatBegin(109546, { home = true })
    s.adapter.despawnPet(ref)
    T.eq(s.w.queued[#s.w.queued].bag, ModKit.SEND_AWAY)
    T.eq(s.w.queued[#s.w.queued].target, 109546)
    T.eq(s.adapter.refs[ref], nil)
end)

-- ------------------------------------------------------------------ city cats and care

T.test("modkit: a summoned cat found on the home lot after the welcome interaction is bound", function()
    local s = boot({ spawn = true })
    s.w.homeCats = {}
    s.w.b2.homeCats = function() return s.w.homeCats end
    s.pump()
    local offers = s.app:offers(77, true)
    T.truthy(s.app:adoptOffer(77, 501, offers[1].id, "Mimi").ok)
    -- the cat appears; the cat binding never reports it, only the lot search finds it
    s.w.homeCats = { 112400 }
    s.adapter.onInteractionFinished({ entity_id = 501, target_entity_id = 501, interaction_bag_id = ModKit.WELCOME })
    local ref = s.app.ctx.state.pets[1].entity
    T.eq(s.adapter.refs[ref], 112400)
    T.truthy(s.adapter.entityExists(ref))
end)

T.test("modkit: city cats the Zoi fed can be adopted as strays; others cannot", function()
    local s = boot()
    s.pump()
    s.adapter.onCatBegin(89129, { home = false })
    s.adapter.onCatBegin(87988, { home = false })
    s.adapter.onInteractionFinished({ entity_id = 501, target_entity_id = 89129, interaction_bag_id = "Object_Void_Cat_Dev" })
    s.adapter.onInteractionFinished({ entity_id = 14704, target_entity_id = 87988, interaction_bag_id = "Object_Void_Cat_Tickle" })
    local strays = s.adapter.listStrays(77)
    T.eq(#strays, 1)
    T.eq(strays[1].ref, 89129)
    s.w.day = s.w.day + 4
    T.eq(#s.adapter.listStrays(77), 0, "forgotten after a few days")
end)

T.test("modkit: care given to one of our cats is collected once", function()
    local s = boot({ spawn = true })
    s.pump()
    local ref = s.adapter.spawnPet(77, {})
    s.adapter.onCatBegin(109546, { home = true })
    s.adapter.onInteractionFinished({ entity_id = 501, target_entity_id = 109546, interaction_bag_id = "Object_Void_Cat_Tickle" })
    local care = s.adapter.takeCare(ref)
    T.eq(#care, 1); T.eq(care[1].kind, "play"); T.eq(care[1].zoi, 501)
    T.eq(#s.adapter.takeCare(ref), 0)
end)


-- ------------------------------------------------------------------ backups outside the savegame

T.test("modkit: pets saved while the UI mod was off come back from the relay's backup", function()
    local s1 = boot({ spawn = false })
    s1.pump()
    local offers = s1.app:offers(77, true)
    T.truthy(s1.app:adoptOffer(77, 501, offers[1].id, "Luna").ok)
    s1.pump(6)
    T.truthy(s1.w.cfg["backup/h77"], "the relay kept a copy")

    -- the game was saved without the UI mod: the next load has no data at all
    local s2 = boot({ spawn = false, session = "S2", cfg = s1.w.cfg, uiState = {} })
    s2.pump(6)
    local v = s2.app:view(77, 501)
    T.eq(#v.pets, 0)
    T.truthy(v.backup, "a backup is offered"); T.eq(v.backup.names[1], "Luna"); T.eq(v.backup.day, 3)
    T.truthy(s1.w.cfg["backup/h77"]:find("Luna"), "the empty new start did not overwrite the backup")

    local r = s2.app:restoreBackup()
    T.truthy(r.ok, r.message)
    v = s2.app:view(77, 501)
    T.eq(#v.pets, 1); T.eq(v.pets[1].name, "Luna"); T.eq(v.backup, nil)
    s2.pump(2)
    T.truthy(s2.ui.state["pawhome.save"]:find("Luna"), "the UI got the restored data for the next save")
end)

T.test("modkit: starting over instead of restoring replaces the backup with the new pets", function()
    local s1 = boot({ spawn = false })
    s1.pump()
    T.truthy(s1.app:adoptOffer(77, 501, s1.app:offers(77, true)[1].id, "Luna").ok)
    s1.pump(6)
    local s2 = boot({ spawn = false, session = "S2", cfg = s1.w.cfg, uiState = {} })
    s2.pump(6)
    T.truthy(s2.app:view(77, 501).backup)
    T.truthy(s2.app:adoptOffer(77, 501, s2.app:offers(77, true)[1].id, "Coco").ok)
    T.eq(s2.app:view(77, 501).backup, nil)
    s2.pump(6)
    T.truthy(s1.w.cfg["backup/h77"]:find("Coco")); T.falsy(s1.w.cfg["backup/h77"]:find("Luna"))
end)

T.test("modkit: no backup is offered when the savegame has its own pets or there is none", function()
    local s1 = boot({ spawn = false })
    s1.pump()
    T.eq(s1.app:view(77, 501).backup, nil)                 -- nothing anywhere
    local offers = s1.app:offers(77, true)
    T.truthy(s1.app:adoptOffer(77, 501, offers[1].id, "Luna").ok)
    s1.pump(6)
    local s2 = boot({ spawn = false, session = "S2", cfg = s1.w.cfg, uiState = s1.ui.state })
    s2.pump(6)
    local v = s2.app:view(77, 501)
    T.eq(#v.pets, 1); T.eq(v.backup, nil)
    T.falsy(s2.app:restoreBackup().ok)
end)

-- ------------------------------------------------------------------ the cat's looks (option a, S2)

local CatB1 = require("pawhome.adapters.inzoi_cat_b1")
local Anim = require("pawhome.data.animations")

-- A random source that staggers nothing and never picks a one-shot.
local function calm(a, b)
    if a == nil then return 0.99 end
    return a
end

local function adoptedCat(opts)
    local s = boot(opts)
    s.pump()
    local offers = s.app:offers(77, true)
    T.truthy(s.app:adoptOffer(77, 501, offers[1].id, "Mimi").ok)
    s.adapter.onCatBegin(109546, { home = true })
    return s, s.app.ctx.state.pets[1]
end

local function sent(s, kind)
    -- messages sent outside pump() are still waiting in the outbox
    for i = #s.w.toClient, 1, -1 do
        local m = s.w.toClient[i]
        if m[1] ~= s.w.zoi then
            table.remove(s.w.toClient, i)
            table.insert(s.w.catMsgs, { eid = m[1], kind = Wire.kind(m[2]), payload = m[3] })
        end
    end
    local out = {}
    for _, m in ipairs(s.w.catMsgs) do
        if m.kind == kind and m.eid == 109546 then out[#out + 1] = m.payload end
    end
    return out
end

T.test("looks: a kitten is shown at its stage's size, repeated now and then for late actors", function()
    local s, pet = adoptedCat({ spawn = true, scale = true })
    pet.stage = "kitten"
    s.w.hour = s.w.hour + 1
    s.pump()
    local scales = sent(s, "scale")
    T.eq(scales[#scales], "0.600")
    for _ = 1, 60 do s.w.minute = s.w.minute + 1; s.adapter.tick(10) end
    scales = sent(s, "scale")
    T.gt(#scales, 1, "sent again by the idle timer")
    for _, v in ipairs(scales) do T.eq(v, "0.600") end
    pet.stage = "adult"
    s.w.hour = s.w.hour + 1
    s.pump()
    scales = sent(s, "scale")
    T.eq(scales[#scales], "1.000")
end)

T.test("looks: nothing is sent while the scale and animate caps are off", function()
    local s, pet = adoptedCat({ spawn = true })
    pet.stage = "kitten"
    s.w.hour = s.w.hour + 1
    s.pump()
    T.eq(#s.w.catMsgs, 0)
    T.falsy(s.adapter.playAnimation(pet.entity, "pet_eat"))
end)

T.test("looks: the size is sent again whenever the cat's actor reappears", function()
    local s, pet = adoptedCat({ spawn = true, scale = true })
    pet.stage = "kitten"
    s.w.hour = s.w.hour + 1
    s.pump()
    local n = #sent(s, "scale")
    s.adapter.onCatMessage(109546, "cat_begin")
    s.pump()
    T.eq(#sent(s, "scale"), n + 1)
    -- a cat that is not ours is left alone
    s.adapter.onCatBegin(9001, { home = false })
    s.adapter.onCatMessage(9001, "cat_begin")
    s.pump()
    for _, m in ipairs(s.w.catMsgs) do T.eq(m.eid, 109546) end
end)

T.test("looks: care from the panel plays its animation and returns to the mood's idle", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, random = calm })
    pet.needs.hunger = 30
    local r = s.app:perform(pet.id, 501, "feed")
    T.truthy(r.ok, r.message)
    s.pump(1)
    local anims = sent(s, "anim")
    T.truthy(#anims >= 1)
    local name, seconds, back = anims[1]:match("^([^|]*)|([^|]*)|(.*)$")
    T.eq(name, Anim.sequences.eat.name)
    T.eq(tonumber(seconds), Anim.sequences.eat.seconds)
    T.truthy(back:find("Sit_Idle"), "returns to a sitting idle")
end)

T.test("looks: care given with the game's own interaction does not replay an animation", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, random = calm })
    pet.needs.hunger = 30
    local ev = { entity_id = 501, target_entity_id = 109546, interaction_bag_id = "Object_Void_Cat_Dev" }
    s.adapter.onInteractionStarted(ev)
    s.adapter.onInteractionFinished(ev)
    local res = s.app:applyCare()
    T.eq(#res, 1); T.truthy(res[1].ok)
    T.eq(#sent(s, "anim"), 0)
end)

T.test("looks: nothing is played on a cat while a game interaction runs on it", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, random = calm })
    s.adapter.petLook(pet.entity, { mood = "content", stage = "adult", scale = 1 })
    local ev = { entity_id = 501, target_entity_id = 109546, interaction_bag_id = "Object_Void_Cat_Tickle" }
    s.adapter.onInteractionStarted(ev)
    T.falsy(s.adapter.playAnimation(pet.entity, "pet_play"))
    for _ = 1, 30 do s.w.minute = s.w.minute + 2; s.adapter.tick(10) end
    T.eq(#sent(s, "anim"), 0)
    s.adapter.onInteractionEnded(ev)
    for _ = 1, 30 do s.w.minute = s.w.minute + 2; s.adapter.tick(10) end
    T.truthy(#sent(s, "anim") >= 1, "the idle comes back after the interaction")
end)

T.test("looks: the idle follows the mood and is not resent while it does not change", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, random = calm })
    s.adapter.petLook(pet.entity, { mood = "angry", stage = "adult", scale = 1 })
    for _ = 1, 40 do s.w.minute = s.w.minute + 1; s.adapter.tick(10) end
    local anims = sent(s, "anim")
    T.eq(#anims, 1)
    T.eq(anims[1], Anim.sequences[Anim.moods.angry.base].name .. "|0|")
    s.adapter.petLook(pet.entity, { mood = "asleep", stage = "adult", scale = 1 })
    for _ = 1, 40 do s.w.minute = s.w.minute + 1; s.adapter.tick(10) end
    anims = sent(s, "anim")
    T.eq(#anims, 2)
    T.eq(anims[2], Anim.sequences[Anim.moods.asleep.base].name .. "|0|")
end)

T.test("looks: every mood and action points at a known animation", function()
    local actions = require("pawhome.data.actions")
    for mood, def in pairs(Anim.moods) do
        T.truthy(Anim.sequences[def.base] and Anim.sequences[def.base].loop, mood .. " base is a loop")
        for _, e in ipairs(def.extra) do
            T.truthy(Anim.sequences[e[1]] and Anim.sequences[e[1]].seconds, mood .. " extra is a one-shot")
        end
    end
    for _, id in ipairs(actions.order) do
        local anim = actions[id].animation
        if anim then T.truthy(Anim.sequences[Anim.actions[anim]], id) end
    end
    for _, mood in ipairs({ "happy", "playful", "energized", "content", "asleep", "sad", "uncomfortable", "tense", "angry", "sick" }) do
        T.truthy(Anim.moods[mood], mood)
    end
end)

-- B1 side, with a fake actor
local function fakeCats()
    local f = { actors = {}, toSim = {} }
    function f.actor(eid)
        local x = { eid = eid, scale = 1, valid = true, anim = nil }
        f.actors[eid] = x
        return x
    end
    f.platform = {
        actorId = function(x) return x.eid end,
        valid = function(x) return x.valid end,
        setScale = function(x, s) x.scale = s; return true end,
        playVat = function(x, name)
            if name:find("Walk") then return false end   -- not baked: the game ignores it
            x.anim = name
            return true
        end,
        currentVat = function(x) return x.anim end,
        sendToSim = function(eid, ch, p) f.toSim[#f.toSim + 1] = { eid, ch, p } end,
    }
    f.cats = CatB1.new(f.platform)
    return f
end

T.test("cat B1: the size is applied on begin, again after a stale start, and asks B2 for it", function()
    local f = fakeCats()
    local a = f.actor(109546)
    a.valid = false                          -- early reference (research 4.3)
    f.cats.onBegin(a)
    T.eq(f.toSim[1][2], "pawhome:cat_begin")
    f.cats.onMessage(a, "pawhome:scale", "0.600")
    T.eq(a.scale, 1, "not applied to a stale actor")
    a.valid = true
    f.cats.tick(2)
    T.eq(a.scale, 0.6)
    -- a respawned actor starts at the game's size and gets ours again
    local b = f.actor(109546)
    f.cats.onBegin(b)
    T.eq(b.scale, 0.6)
end)

T.test("cat B1: a one-shot returns to the sitting idle and is not cut short", function()
    local f = fakeCats()
    local a = f.actor(109546)
    f.cats.onBegin(a)
    f.cats.onMessage(a, "pawhome:anim", "ANIM_VoidCat_Eat|8.7|ANIM_VoidCat_Sit_Idle_01")
    T.eq(a.anim, "ANIM_VoidCat_Eat")
    f.cats.onMessage(a, "pawhome:anim", "ANIM_VoidCat_Sit_Idle_02|0|")
    T.eq(a.anim, "ANIM_VoidCat_Eat", "still eating")
    for _ = 1, 10 do f.cats.tick(1) end
    T.eq(a.anim, "ANIM_VoidCat_Sit_Idle_01")
end)

T.test("cat B1: an animation the game started blocks ours for a while", function()
    local f = fakeCats()
    local a = f.actor(109546)
    f.cats.onBegin(a)
    f.cats.onMessage(a, "pawhome:anim", "ANIM_VoidCat_Sit_Idle_01|0|")
    f.cats.tick(1)
    a.anim = "ANIM_Void_Cat_Welcoming"       -- the game's Play interaction
    f.cats.tick(1)
    f.cats.onMessage(a, "pawhome:anim", "ANIM_VoidCat_Sit_Idle_02|0|")
    T.eq(a.anim, "ANIM_Void_Cat_Welcoming")
    for _ = 1, CatB1.GRACE + 1 do f.cats.tick(1) end
    f.cats.onMessage(a, "pawhome:anim", "ANIM_VoidCat_Sit_Idle_02|0|")
    T.eq(a.anim, "ANIM_VoidCat_Sit_Idle_02")
end)

T.test("cat B1: other mods' messages and unknown kinds are ignored", function()
    local f = fakeCats()
    local a = f.actor(109546)
    f.cats.onBegin(a)
    f.cats.onMessage(a, "othermod:anim", "ANIM_VoidCat_Eat|8.7|")
    f.cats.onMessage(a, "pawhome:dance", "x")
    T.eq(a.anim, nil)
end)
