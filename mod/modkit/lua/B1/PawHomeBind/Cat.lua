-- Bound to the cat object templates on the game thread: the cat's size and animations.
local Runtime = require("pawhome.adapters.inzoi_b1")

local M = {}

---@param self table
---@param owner AB1GameObject
function M.on_begin(self, owner)
    Runtime.onCatBegin(owner)
end

---@param self table
---@param owner AB1GameObject
function M.on_end(self, owner)
    Runtime.onCatEnd(owner)
end

---@param self table
---@param owner AB1GameObject
function M.on_lua_message(self, owner, channel, payload)
    Runtime.onCatMessage(owner, channel, payload)
end

return M
