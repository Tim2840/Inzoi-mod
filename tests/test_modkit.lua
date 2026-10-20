-- The ModKit route end to end, without the game: B2 adapter <-> B1 relay <-> a fake UI that
-- follows the same protocol as mod/ui/bridge.js, with the real engine and RPC on top.
local T = require("framework")
local Wire = require("pawhome.adapters.inzoi_wire")
local Inzoi = require("pawhome.adapters.inzoi")
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
        cfg = {},                 -- "section/key" -> value (the shared mailbox files)
        toSim = {}, toClient = {}, -- queued inzoi.message deliveries
        toasts = {},
        queued = {},              -- interactions put in the Zoi's queue
        uiState = opts.uiState,   -- what wf.state.pawhome held when the save was loaded
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
    local adapter = Inzoi.new(w.b2, { session = opts.session or "S1", spawn = opts.spawn })
    local app = assert(App.new(adapter, { seed = 7 }))
    adapter.rpc = function(method, args)
        return Rpc.handle(app, { household = w.household, zoi = w.zoi }, method, args)
    end
    local relay = Relay.new(w.b1, { epoch = "R1" })
    local ui = fakeUi(w, opts.uiState)
    local function pump(rounds)
        for _ = 1, rounds or 6 do
            adapter.tick(10)
            while #w.toClient > 0 do
                local m = table.remove(w.toClient, 1)
                relay.onMessage(m[1], m[2], m[3])
            end
            ui.poll()
            relay.tick(10)
            while #w.toSim > 0 do
                local m = table.remove(w.toSim, 1)
                adapter.onMessage(m[2], m[3])
            end
            app:tick()
        end
    end
    return { w = w, adapter = adapter, app = app, relay = relay, ui = ui, pump = pump }
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

T.test("wire: other mods' channels are ignored", function()
    T.eq(Wire.kind("pawhome:save"), "save")
    T.eq(Wire.kind("AlimonyMoods"), nil)
    T.eq(Wire.kind("zwlsm_out"), nil)
end)

-- ------------------------------------------------------------------ handshake and saving

T.test("modkit: the engine stays paused until the UI hands over the save data", function()
    local w = world()
    local adapter = Inzoi.new(w.b2, { session = "S1" })
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
    T.eq(s.w.queued[1].bag, Inzoi.WELCOME)
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
    T.eq(s.w.queued[#s.w.queued].bag, Inzoi.SEND_AWAY)
    T.eq(s.w.queued[#s.w.queued].target, 109546)
    T.eq(s.adapter.refs[ref], nil)
end)

-- ------------------------------------------------------------------ city cats and care

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
