-- B1 runtime: one relay for the whole game thread. The thin binding scripts in
-- mod/modkit/lua/B1 forward their callbacks here.
local Relay = require("pawhome.adapters.inzoi_relay")
local Platform = require("pawhome.adapters.inzoi_platform")

local R = { relay = nil }

local function ensure(opts)
    if not R.relay then
        R.platform = Platform.b1(opts)
        R.relay = Relay.new(R.platform)
        R.platform.log("B1 relay started, mod " .. Platform.MOD_ID .. ", epoch " .. R.relay.epoch)
    end
    return R.relay
end

-- B1 Main on_begin.
function R.start(opts) ensure(opts) end

-- B1 Main on_tick, real seconds (verified: B1 Main receives on_tick with dt, 2026-10-20).
function R.tick(dt) ensure().tick(dt) end

-- B1 Zoi(ResidenceFamily) on_lua_message. owner is an AB1Character.
function R.onMessage(owner, channel, payload)
    local ok, eid = pcall(function() return owner:GetEntityId() end)   -- verified 2026-10-21
    if not ok then return end
    if type(eid) == "table" and eid.Value then eid = eid.Value end
    ensure().onMessage(eid, channel, payload)
end

function R.stop() R.relay = nil end

return R
