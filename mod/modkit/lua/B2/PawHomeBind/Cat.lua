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

-- From the B1 cat binding (inzoi.message.send_to_sim to the cat's entity, seen working
-- 2026-10-21, docs/research/walking-cat.md 4.5).
function M.on_lua_message(self, owner, channel, payload)
    Runtime.onCatMessage(owner, channel, payload)
end

return M
