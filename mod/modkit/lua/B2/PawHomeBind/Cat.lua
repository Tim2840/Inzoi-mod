-- Bound to the city-cat object templates: reports every cat that appears or goes away.
local Runtime = require("pawhome.adapters.inzoi_b2")

local M = {}

---@param self table
---@param owner FB2GameObject
function M.on_begin(self, owner)
    Runtime.onCatBegin(owner)
end

---@param self table
---@param owner FB2GameObject
function M.on_end(self, owner)
    Runtime.onCatEnd(owner)
end

return M
