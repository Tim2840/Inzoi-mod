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
                 lastSeen = 0, relayEpoch = nil, nextRpc = 1, results = {}, epoch = "ui1", opened = {} }
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
                elseif from == ui.session and e.channel == "pawhome:open" then
                    ui.opened[#ui.opened + 1] = Wire.fromJson(data)
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
    function ui.wake()
        ui.outbox[#ui.outbox + 1] = { seq = ui.nextSeq, channel = "pawhome:wake", payload = "-|" }
        ui.nextSeq = ui.nextSeq + 1
        local entries = { { seq = 0, channel = "epoch", payload = ui.epoch } }
        for _, e in ipairs(ui.outbox) do entries[#entries + 1] = e end
        w.cfg["bridge/to_sim"] = Wire.encodeMailbox(entries)
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
        animate = opts.animate, scale = opts.scale, idleLoop = opts.idleLoop, random = opts.random })
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

T.test("modkit: the coats of our summoned cats reach the game thread", function()
    local s = boot({ spawn = true })
    local got = {}
    s.relay.onCoats = function(text) got[#got + 1] = text end
    s.pump()
    local offers = s.app:offers(77, true)
    T.truthy(s.app:adoptOffer(77, 501, offers[1].id, "Mimi", "calico").ok)
    s.pump()
    T.eq(got[#got] or "", "", "no cat in the list while it is still on its way")
    s.adapter.onCatBegin(109546, { home = true })
    s.pump()
    T.eq(got[#got], "109546=Void_Cat_001_002_D")
    local n = #got
    require("pawhome.pets.coats").publish(s.app.ctx)     -- what every engine tick does
    local sent = {}
    for _, m in ipairs(s.w.toClient) do
        if m[2] == "pawhome:coats" then sent[#sent + 1] = m[3] end
    end
    T.eq(table.concat(sent, ","), "", "an unchanged list is not sent again on every tick")
    s.pump(8)     -- 80 seconds: the minute's hello repeats the list for a relay that restarted
    T.gt(#got, n)
    T.eq(got[#got], "109546=Void_Cat_001_002_D")

    -- after a load the list is sent as soon as the save data arrived
    local again = boot({ session = "S2", uiState = s.ui.state, spawn = true })
    local got2 = {}
    again.relay.onCoats = function(text) got2[#got2 + 1] = text end
    again.adapter.onCatBegin(109546, { home = true })
    again.pump()
    T.eq(got2[#got2], "109546=Void_Cat_001_002_D")
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

T.test("modkit: a page that starts late asks B2 to say hello at once instead of waiting a minute", function()
    local s = boot({ spawn = false })
    s.pump()                                          -- connected; the next hello is a minute away
    local hellos = 0
    local send = s.w.b2.send
    s.w.b2.send = function(eid, ch, payload)
        if ch == "pawhome:hello" then hellos = hellos + 1 end
        return send(eid, ch, payload)
    end
    s.adapter.sinceHello = 0                          -- it has just said hello
    s.pump(1)
    T.eq(hellos, 0, "quiet while nothing is asked")
    s.ui.wake()
    s.pump(2)                                         -- the relay passes it on, then B2 answers
    T.truthy(hellos >= 1, "hello right after the wake message")
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

T.test("modkit: care from the cat's own menu counts: pet gently, treats, snack, play", function()
    local s = boot({ spawn = true })
    s.pump()
    local offers = s.app:offers(77, true)
    T.truthy(s.app:adoptOffer(77, 501, offers[1].id, "Mimi").ok)
    s.adapter.onCatBegin(109546, { home = true })
    local pet = s.app.ctx.state.pets[1]
    pet.want = nil; pet.wantNext = math.huge
    pet.needs.hunger = 30; pet.needs.fun = 20
    local kinds = {
        Petting_Cat = "cuddle", Giving_Snack_To_Cat = "feed", Giving_Catnip_Candy_To_Cat = "feed",
        Object_Void_Cat_Tickle = "play", Object_Void_Cat_Dev = "feed", Playing_Toy_With_Cat = "play",
    }
    for bag, kind in pairs(kinds) do
        T.eq(ModKit.CARE[bag], kind, bag)
        s.adapter.onInteractionFinished({ entity_id = 501, target_entity_id = 109546, interaction_bag_id = bag })
    end
    local res = s.app:applyCare()
    T.eq(#res, 6, "every menu interaction became one care event")
    local cuddles = 0
    for _, r in ipairs(res) do if r.action == "cuddle" then cuddles = cuddles + 1 end end
    T.eq(cuddles, 1)
end)

T.test("modkit: a gift is queued on the Zoi as a tiny interaction that puts the real item in her bag", function()
    local s = boot({ spawn = false })
    s.pump()
    T.truthy(s.adapter.giveItem(77, "CatToy01"))
    T.eq(#s.w.queued, 1)
    T.eq(s.w.queued[1].bag, "PawHome_Gift_CatToy01")
    T.eq(s.w.queued[1].zoi, 501); T.eq(s.w.queued[1].target, 501, "an interaction on herself")
    s.w.home = false                                -- a gift does not wait for the Zoi to be home
    T.truthy(s.adapter.giveItem(77, "GiftBouquet01"))
    T.eq(#s.w.queued, 2)
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

-- The clips queued for the cat (interactions PawHome_Vat_<key>, see adapters/inzoi.lua playClip)
local function clips(s)
    local out = {}
    for _, q in ipairs(s.w.queued) do
        local key = tostring(q.bag):match("^PawHome_Vat_(.+)$")
        if key then out[#out + 1] = key end
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

T.test("looks: care from the panel plays its clip through the game and returns to the mood's idle", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, idleLoop = true, random = calm })
    pet.needs.hunger = 30
    local r = s.app:perform(pet.id, 501, "feed")
    T.truthy(r.ok, r.message)
    s.pump(1)
    local c = clips(s)
    local ate = false
    for _, k in ipairs(c) do if k == "eat" then ate = true end end
    T.truthy(ate, "the eat clip was queued")
    for _ = 1, Anim.sequences.eat.seconds + 2 do s.adapter.tick(1) end
    c = clips(s)
    T.eq(c[#c], Anim.moods[pet.mood and "content" or "content"].base, "back to a sitting idle")
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

T.test("looks: pressing buttons quickly plays every reaction at once", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, random = calm })
    s.adapter.petLook(pet.entity, { mood = "content", stage = "adult", scale = 1 })
    local before = #clips(s)
    T.truthy(s.adapter.playAnimation(pet.entity, "pet_cuddle"))
    T.truthy(s.adapter.playAnimation(pet.entity, "pet_play"), "the first reaction (12 s) does not hold the second back")
    local c = clips(s)
    T.eq(#c - before, 2)
    T.eq(c[#c - 1], "patted")
    T.eq(c[#c], "welcoming")
end)

T.test("looks: without idle loops (the default) only reactions play and the cat is left to its own idle", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, random = calm })
    s.adapter.petLook(pet.entity, { mood = "content", stage = "adult", scale = 1 })
    s.adapter.onCatMessage(109546, "cat_begin")
    for _ = 1, 60 do s.w.minute = s.w.minute + 1; s.adapter.tick(5) end
    T.eq(#clips(s), 0, "no idle clip is queued")
    T.truthy(s.adapter.playAnimation(pet.entity, "pet_cuddle"))
    local c = clips(s)
    T.eq(c[#c], "patted")
    for _ = 1, 40 do s.adapter.tick(1) end
    T.eq(#clips(s), #c, "and nothing follows it")
end)

T.test("looks: nothing is played on a cat while a game interaction runs on it", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, idleLoop = true, random = calm })
    s.adapter.petLook(pet.entity, { mood = "content", stage = "adult", scale = 1 })
    local ev = { entity_id = 501, target_entity_id = 109546, interaction_bag_id = "Object_Void_Cat_Tickle" }
    s.adapter.onInteractionStarted(ev)
    local n = #clips(s)
    T.falsy(s.adapter.playAnimation(pet.entity, "pet_play"))
    for _ = 1, 30 do s.w.minute = s.w.minute + 2; s.adapter.tick(10) end
    T.eq(#clips(s), n, "nothing while the game's interaction runs")
    s.adapter.onInteractionEnded(ev)
    for _ = 1, 30 do s.w.minute = s.w.minute + 2; s.adapter.tick(10) end
    T.truthy(#clips(s) > n, "the idle comes back after the interaction")
end)

T.test("looks: our own clip interactions are not mistaken for the game playing on the cat", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, random = calm })
    s.adapter.petLook(pet.entity, { mood = "content", stage = "adult", scale = 1 })
    local ev = { entity_id = 501, target_entity_id = 109546, interaction_bag_id = "PawHome_Vat_sit1" }
    s.adapter.onInteractionStarted(ev)
    T.truthy(s.adapter.playAnimation(pet.entity, "pet_play"), "still free to play")
    s.adapter.onInteractionEnded(ev)
end)

T.test("looks: a loop is started again when it has played through, only while the Zoi has nothing else to do", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, idleLoop = true, random = calm })
    s.adapter.petLook(pet.entity, { mood = "content", stage = "adult", scale = 1 })
    s.adapter.onCatMessage(109546, "cat_begin")
    for _ = 1, 3 do s.adapter.tick(1) end
    local n = #clips(s)
    T.truthy(n >= 1)
    for _ = 1, Anim.sequences.sit1.cycle - 4 do s.adapter.tick(1) end
    T.eq(#clips(s), n, "not before the clip ends")
    for _ = 1, 6 do s.adapter.tick(1) end
    T.eq(#clips(s), n + 1, "started over")
    s.w.b2.zoiIdle = function() return false end
    for _ = 1, 40 do s.adapter.tick(1) end
    T.eq(#clips(s), n + 1, "waits while the Zoi is busy")
    s.w.b2.zoiIdle = function() return true end
    for _ = 1, 4 do s.adapter.tick(1) end
    T.eq(#clips(s), n + 2, "and goes on when she is free")
end)

T.test("looks: the idle follows the mood and only the mood's loop is restarted", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, idleLoop = true, random = calm })
    s.adapter.petLook(pet.entity, { mood = "angry", stage = "adult", scale = 1 })
    for _ = 1, 40 do s.w.minute = s.w.minute + 1; s.adapter.tick(10) end
    local base = Anim.moods.angry.base
    for _, k in ipairs(clips(s)) do T.eq(k, base) end
    s.adapter.petLook(pet.entity, { mood = "asleep", stage = "adult", scale = 1 })
    for _ = 1, 40 do s.w.minute = s.w.minute + 1; s.adapter.tick(10) end
    local c = clips(s)
    T.eq(c[#c], Anim.moods.asleep.base)
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
        setLocation = function(x, lx, ly, lz) x.loc = { lx, ly, lz }; return true end,
        setYaw = function(x, yaw) x.yaw = yaw; return true end,
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

T.test("cat B1: a reaction the player asked for is shown at once, an idle change waits for the game", function()
    local f = fakeCats()
    local a = f.actor(109546)
    f.cats.onBegin(a)
    f.cats.onMessage(a, "pawhome:anim", "ANIM_VoidCat_Sit_Idle_01|0|")
    a.anim = "ANIM_VoidCat_Eat"                      -- the game changed the animation by itself
    f.cats.tick(1)                                   -- B1 notices the change
    f.cats.onMessage(a, "pawhome:anim", "ANIM_VoidCat_Sit_Idle_02|0|")
    T.eq(a.anim, "ANIM_VoidCat_Eat", "an ordinary idle change keeps off the game's animation")
    f.cats.onMessage(a, "pawhome:anim", "ANIM_Void_Cat_Welcoming|5.7|ANIM_VoidCat_Sit_Idle_01|1")
    T.eq(a.anim, "ANIM_Void_Cat_Welcoming", "the player's button is shown right away")
    -- and a second button press replaces the first reaction instead of waiting for it to end
    f.cats.onMessage(a, "pawhome:anim", "ANIM_VoidCat_Being_Patted|12.2|ANIM_VoidCat_Sit_Idle_01|1")
    T.eq(a.anim, "ANIM_VoidCat_Being_Patted")
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

T.test("cat B1: a loop is started over at its length so the cat never freezes on the last frame", function()
    local f = fakeCats()
    local a = f.actor(109546)
    local plays = 0
    local play = f.platform.playVat
    f.platform.playVat = function(x, name) plays = plays + 1; return play(x, name) end
    f.cats.onBegin(a)
    f.cats.onMessage(a, "pawhome:anim", "ANIM_VoidCat_Sit_Idle_01|0||1|15")
    T.eq(plays, 1)
    for _ = 1, 14 do f.cats.tick(1) end
    T.eq(plays, 1, "not before the clip ends")
    for _ = 1, 2 do f.cats.tick(1) end
    T.eq(plays, 2, "started over")
    for _ = 1, 15 do f.cats.tick(1) end
    T.eq(plays, 3, "and again")
    -- a one-shot resumes the loop it returns to, with its own restart time
    f.cats.onMessage(a, "pawhome:anim", "ANIM_VoidCat_Eat|8.7|ANIM_VoidCat_Sit_Idle_02|1|43.2")
    for _ = 1, 10 do f.cats.tick(1) end
    T.eq(a.anim, "ANIM_VoidCat_Sit_Idle_02")
    local after = plays
    for _ = 1, 40 do f.cats.tick(1) end
    T.eq(plays, after, "not restarted early")
    for _ = 1, 6 do f.cats.tick(1) end
    T.eq(plays, after + 1, "restarted after its own length")
    -- the game's own animation is left alone
    a.anim = "ANIM_VoidCat_Eat"
    f.cats.tick(1)
    local n = plays
    for _ = 1, 10 do f.cats.tick(1) end
    T.truthy(plays == n, "no restarts over a game animation")
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

T.test("modkit: our phone and city-cat entries open the shop on the page", function()
    local s = boot({ spawn = false })
    s.pump()
    s.adapter.onInteractionStarted({ interaction_bag_id = "PawHome_ShopPhone", entity_id = 501 })
    s.adapter.onInteractionStarted({ interaction_bag_id = "PawHome_Adopt", entity_id = 501, target_entity_id = 89129 })
    s.adapter.onInteractionStarted({ interaction_bag_id = "PawHome_ShopPhone", entity_id = 777 })   -- not our Zoi
    s.adapter.onInteractionStarted({ interaction_bag_id = "Self_SmartPhone_Check", entity_id = 501 }) -- not ours
    s.adapter.onCatBegin(109615, { home = true })
    s.adapter.onInteractionStarted({ interaction_bag_id = "PawHome_Adopt", entity_id = 501, target_entity_id = 109615 }) -- a home cat
    s.pump(2)
    T.eq(#s.ui.opened, 2)
    T.eq(s.ui.opened[1].shell, "phone")
    T.eq(s.ui.opened[2].tab, "adopt"); T.eq(s.ui.opened[2].stray, "cat89129")
    local strays = s.app:strays(77)
    local found = false
    for _, st in ipairs(strays) do if tostring(st.ref) == "89129" then found = true end end
    T.truthy(found, "the cat the player chose to adopt is offered as a stray")
end)

T.test("modkit: litter box refill, cat teleport-to-litter-box, and call-cat-over work end to end", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, random = calm })
    s.w.b2.homeObjects = function(watched)
        local out = {}
        for _, id in ipairs(watched or {}) do
            if id == "PawHome_LitterBox" or id == "PawHome_LitterBag" then out[#out + 1] = id end
        end
        return out
    end
    local movedTo = nil
    s.w.b2.moveCatToObject = function(eid, objId)
        movedTo = { eid = eid, obj = objId }
        return 120.5, -340.0, 15.0, 90.0
    end
    local movedToZoi = nil
    s.w.b2.moveCatToZoi = function(eid, zoiId)
        movedToZoi = { eid = eid, zoi = zoiId }
        return 210.0, 400.0, 12.0, 270.0
    end
    pet.needs.bladder = 20
    T.truthy(s.app:refillLitter(77, 501).ok)
    T.eq(pet.needs.bladder, 100)
    T.truthy(movedTo and movedTo.eid == 109546 and movedTo.obj == "PawHome_LitterBox")
    T.eq(s.app:view(77, 501).pets[1].litterStatus.state, "dirty")
    -- cleaning is done from the litter box's own menu (the interaction targets the box, not the cat)
    T.truthy(s.app:cleanLitterBox(77, 501).ok)
    T.eq(s.app:view(77, 501).pets[1].litterStatus.state, "clean")
    -- away from home the cat is moved by hand
    s.w.home = false
    T.truthy(s.app:callPet(pet.id, 501).ok)
    T.truthy(movedToZoi and movedToZoi.eid == 109546 and movedToZoi.zoi == 501)
    local teleports = sent(s, "teleport")
    T.eq(#teleports, 3)
    T.eq(teleports[1], "210.0|400.0|12.0|270.0")
    T.eq(teleports[3], "120.5|-340.0|15.0|90.0")
end)

T.test("modkit: at home, calling the cat summons it anew in front of the Zoi and the old one vanishes", function()
    local s, pet = adoptedCat({ spawn = true, animate = true, random = calm })
    local ref = pet.entity
    T.eq(s.adapter.resolve and s.adapter.resolve(ref) or 109546, 109546)
    local queued = #s.w.queued
    T.truthy(s.app:callPet(pet.id, 501).ok)
    local q1, q2 = s.w.queued[queued + 1], s.w.queued[queued + 2]
    T.truthy(q1 and q1.bag == "PawHome_Vanish" and q1.target == 109546, "the old cat vanishes")
    T.truthy(q2 and q2.bag == "PawHome_WelcomeCat", "a new one is summoned")
    T.eq(#sent(s, "teleport"), 0, "no moving by hand")
    -- the pet stays present while it is on its way, and becomes the new cat when it appears
    T.truthy(s.adapter.entityExists(ref))
    s.adapter.onCatBegin(109999, { home = true })
    T.eq(pet.entity, ref, "the pet keeps its reference")
    T.truthy(s.adapter.entityExists(ref))
    T.truthy(s.adapter.playAnimation(ref, "pet_cuddle"), "and its looks follow the new cat")
    T.eq(s.w.queued[#s.w.queued].target, 109999)
end)

T.test("cat B1: teleport message moves the cat actor and reapplies after a stale start", function()
    local f = fakeCats()
    local a = f.actor(109546)
    a.valid = false
    f.cats.onBegin(a)
    f.cats.onMessage(a, "pawhome:teleport", "120.5|-340.0|15.0|90.0")
    T.eq(a.loc, nil, "waits for valid actor")
    a.valid = true
    f.cats.tick(2)
    T.truthy(a.loc and a.loc[1] == 120.5 and a.loc[2] == -340.0 and a.loc[3] == 15.0)
    T.eq(a.yaw, 90.0)
end)

T.test("platform: a called cat is put in a spot clear of furniture, not under the table in front of the Zoi", function()
    local Platform = require("pawhome.adapters.inzoi_platform")
    -- nothing around: ahead, a little to the side, 1 m away
    local x, y, yaw, how = Platform.pickSpot(0, 0, 0, {})
    T.eq(how, "clear")
    T.truthy(x > 70 and math.abs(y) > 40 and math.abs(y) < 70, "ahead and to the side")
    T.truthy(math.abs(((yaw - 180 - 35) + 180) % 360 - 180) < 1, "faces the Zoi")
    -- a table right in front of her (origin 1 m ahead): the cat goes somewhere else
    local table_ = { { x = 100, y = 0 } }
    local x2, y2 = Platform.pickSpot(0, 0, 0, table_)
    local d = math.sqrt((x2 - 100) ^ 2 + y2 ^ 2)
    T.truthy(d >= Platform.CLEAR_CM, "clear of the table: " .. d)
    -- crowded all around: the least crowded spot, still answered
    local crowd = {}
    for a = 0, 350, 10 do crowd[#crowd + 1] = { x = math.cos(math.rad(a)) * 120, y = math.sin(math.rad(a)) * 120 } end
    local _, _, _, how3 = Platform.pickSpot(0, 0, 0, crowd)
    T.truthy(how3 == "clear" or how3 == "least crowded")
end)

T.test("platform: a called cat lands on the floor under the Zoi, not at her body centre", function()
    local Platform = require("pawhome.adapters.inzoi_platform")
    -- seen in game 2026-10-22: Zoi Z 158.0, floor 75.3; the cat floated when put at 158
    local z, how = Platform.floorUnderZoi(158.0, nil, nil, nil)
    T.truthy(math.abs(z - 75.3) < 5, "default half height lands near the floor: " .. z)
    T.eq(how, "default half height")
    T.eq(select(1, Platform.floorUnderZoi(158.0, 75.3, 88, 80)), 75.3)        -- the game's floor first
    T.eq(select(1, Platform.floorUnderZoi(158.0, nil, 88, 80)), 70.0)          -- then its half height
    T.eq(select(1, Platform.floorUnderZoi(158.0, nil, nil, 76.0)), 76.0)       -- then the cat's own floor
    -- a floating cat (Z 158) or one on another storey is not trusted as the floor
    T.eq(select(2, Platform.floorUnderZoi(158.0, nil, nil, 158.0)), "default half height")
    T.eq(select(2, Platform.floorUnderZoi(158.0, nil, nil, -250.0)), "default half height")
    -- on a deck the navigation floor (0.0) is the ground below it: the Zoi's feet decide
    -- (Cahaya_Residence_LocalHouse1 2026-10-22: Zoi Z 158.0, half height 90, node floor 0.0, deck at 68)
    local z2, how2 = Platform.floorUnderZoi(158.0, 0.0, 90, 0.0)
    T.eq(z2, 68.0)
    T.eq(how2, "half height")
    -- nonsense answers from the game are ignored
    T.eq(select(2, Platform.floorUnderZoi(158.0, 900, 0, nil)), "default half height")
end)
