-- Bound to Manager "Time": gives the B2 runtime a tick (real seconds).
local Runtime = require("pawhome.adapters.inzoi_b2")

local M = {}

---@param self table
---@param manager FB2TimeManager
---@param dt number
function M.on_tick(self, manager, dt)
    Runtime.tick(dt)
end

return M
