-- Bound to Zoi "ResidenceFamily": messages from B2 arrive here.
local Runtime = require("pawhome.adapters.inzoi_b1")

local M = {}

---@param self table
---@param owner AB1Character
function M.on_lua_message(self, owner, channel, payload)
    Runtime.onMessage(owner, channel, payload)
end

return M
