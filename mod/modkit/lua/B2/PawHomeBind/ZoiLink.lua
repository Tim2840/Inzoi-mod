-- Bound to Zoi "ResidenceFamily": messages from the B1 relay arrive here, and the
-- character objects are registered for the household, money and interaction calls.
local Runtime = require("pawhome.adapters.inzoi_b2")

local M = {}

---@param self table
---@param owner FB2Character
function M.on_begin(self, owner)
    Runtime.onZoiBegin(owner)
end

---@param self table
---@param owner FB2Character
function M.on_end(self, owner)
    Runtime.onZoiEnd(owner)
end

---@param self table
---@param owner FB2Character
function M.on_lua_message(self, owner, channel, payload)
    Runtime.onZoiBegin(owner)      -- also registers Zois that existed before a hot mount
    Runtime.onMessage(channel, payload)
end

return M
