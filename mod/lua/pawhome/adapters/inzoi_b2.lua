-- B2 runtime: owns the adapter and the engine for one game session. The thin binding
-- scripts in mod/modkit/lua/B2 forward their callbacks here.
local ModKit = require("pawhome.adapters.inzoi")
local Platform = require("pawhome.adapters.inzoi_platform")
local App = require("pawhome.app")
local Rpc = require("pawhome.rpc")

local R = { platform = nil, adapter = nil, app = nil, handlers = {}, opts = {}, failed = nil }

-- Lines also go to the B1 relay's log (pawhome:diag), the only place a running B2 can report to.
local function log(line)
    if R.platform then R.platform.log(line) end    -- also reaches the relay log (see start)
end

local function who()
    local zoi = R.platform.possessed()
    return { household = R.platform.household(), zoi = zoi }
end

local function onHour()
    if R.app then
        local ok, err = pcall(function() R.app:tick(); R.app:autoLitter(R.platform.possessed()) end)
        if not ok then log("tick failed: " .. tostring(err)) end
    end
end

local function onInteraction(p)
    if not (R.adapter and type(p) == "table") then return end
    R.adapter.onInteractionFinished(p)
    if R.app and p.interaction_bag_id == ModKit.PLACE_LITTER then
        pcall(function() R.app:autoLitter(R.platform.possessed()) end)
    end
    if R.app and ModKit.CARE[p.interaction_bag_id] then
        local ok, res = pcall(function() return R.app:applyCare() end)
        if not ok then log("care failed: " .. tostring(res))
        elseif #res > 0 then
            local r = res[#res]
            log("care " .. tostring(r.action) .. " -> " .. tostring(r.petId) .. (r.ok and "" or " (" .. tostring(r.reason) .. ")"))
        end
    end
end

-- B2 Main on_begin. Also called lazily from the first binding callback, because a mod that is
-- mounted while a game is running never gets Main.on_begin for that session.
function R.start(opts)
    opts = opts or R.opts or {}
    R.opts = opts
    R.platform = Platform.b2(opts)
    R.platform.report = function(line) log(line) end
    -- the adapter logs through platform.log; show those lines in the relay log as well
    local keep = R.platform.log
    R.platform.log = function(line)
        keep(line)
        pcall(function()
            local eid = R.platform.possessed()
            if eid then R.platform.send(eid, "pawhome:diag", line) end
        end)
    end
    -- os is blocked in the game's sandbox; seed from the game clock instead
    pcall(function()
        local d, h, m = R.platform.time()
        math.randomseed(d * 1440 + h * 60 + m)
    end)
    R.adapter = ModKit.new(R.platform, { spawn = opts.spawn, animate = opts.animate, scale = opts.scale })
    local app, err = App.new(R.adapter, { seed = math.random(1, 2^30) })
    if not app then log("engine failed to start: " .. tostring(err)) return end
    R.app = app
    R.adapter.rpc = function(method, args) return Rpc.handle(R.app, who(), method, args) end
    R.handlers = {
        ["time.hour_changed"] = function() onHour() end,
        ["interaction.finished"] = onInteraction,
        -- our shop entries open the panel; a game interaction on one of our cats keeps our
        -- animations off it meanwhile
        ["interaction.started"] = function(ev)
            if R.adapter and type(ev) == "table" then pcall(R.adapter.onInteractionStarted, ev) end
        end,
        ["interaction.canceled"] = function(ev) if R.adapter and type(ev) == "table" then R.adapter.onInteractionEnded(ev) end end,
        ["interaction.failed"] = function(ev) if R.adapter and type(ev) == "table" then R.adapter.onInteractionEnded(ev) end end,
    }
    for name, fn in pairs(R.handlers) do
        local ok, e = pcall(inzoi.event.on, name, fn)       -- verified 2026-10-20 (B2)
        if not ok then log("subscribe " .. name .. " failed: " .. tostring(e)) end
    end
    log("started, session " .. R.adapter.session)
end

-- B2 Main on_end.
function R.stop()
    for name, fn in pairs(R.handlers) do pcall(inzoi.event.off, name, fn) end
    R.handlers = {}
    R.failed = nil
    log("stopped")
    if R.platform then R.platform.flushLog() end
    R.app, R.adapter = nil, nil
end

local function ensure()
    if R.adapter or R.failed then return R.adapter ~= nil end
    local ok, err = pcall(R.start)
    if not ok then
        R.failed = tostring(err)
        log("start failed: " .. R.failed)
    end
    return R.adapter ~= nil
end

-- Manager(Time) on_tick, real seconds.
function R.tick(dt)
    if not ensure() then return end
    R.adapter.tick(dt)
    -- one status line shortly after start: how many cats the cat binding has reported
    R.uptime = (R.uptime or 0) + (dt or 0)
    if not R.statusSent and R.uptime > 10 then
        R.statusSent = true
        local cats, home, zois = 0, 0, 0
        for _, c in pairs(R.adapter.cats) do
            cats = cats + 1
            if c.home then home = home + 1 end
        end
        for _ in pairs(R.platform.zois) do zois = zois + 1 end
        log(("status: %d cats known (%d at home), %d Zois known"):format(cats, home, zois))
    end
end

-- Zoi(ResidenceFamily) on_begin / on_end: keeps the character objects the platform needs.
function R.onZoiBegin(owner)
    if not ensure() then return end
    local ok, eid = pcall(function() return R.platform.value(owner:GetEntityId()) end)
    if ok and eid then
        if not R.platform.zois[eid] then R.platform.zois[eid] = owner end
    elseif not R.zoiIdFailed then
        R.zoiIdFailed = true
        log("Zoi id unreadable: " .. tostring(eid))
    end
end

function R.onZoiEnd(owner)
    if not R.platform then return end
    local ok, eid = pcall(function() return R.platform.value(owner:GetEntityId()) end)
    if ok and eid then R.platform.zois[eid] = nil end
end

-- Zoi(ResidenceFamily) on_lua_message.
function R.onMessage(channel, payload)
    if ensure() then R.adapter.onMessage(channel, payload) end
end

-- ObjectTemplate(cat) on_begin / on_end.
function R.onCatBegin(owner)
    if not ensure() then return end
    local ok, eid, info = pcall(R.platform.catInfo, owner)
    if not ok then log("cat begin failed: " .. tostring(eid)) return end
    if #R.adapter.pending > 0 then
        log("cat " .. tostring(eid) .. " appeared on " .. tostring(info.site) .. ", home=" .. tostring(info.home))
    end
    R.adapter.onCatBegin(eid, info)
end

-- ObjectTemplate(cat) on_lua_message: "pawhome:cat_begin" from the B1 cat binding.
function R.onCatMessage(owner, channel, payload)
    if not ensure() then return end
    local Wire = require("pawhome.adapters.inzoi_wire")
    local kind = Wire.kind(channel)
    if not kind then return end
    local ok, eid = pcall(function() return owner:GetObjectKey().Value end)
    if ok and eid then R.adapter.onCatMessage(eid, kind, payload) end
end

function R.onCatEnd(owner)
    if not ensure() then return end
    local ok, eid = pcall(function() return owner:GetObjectKey().Value end)
    if ok and eid then
        R.adapter.onCatEnd(eid)
        R.platform.cats[eid] = nil
    end
end

return R
