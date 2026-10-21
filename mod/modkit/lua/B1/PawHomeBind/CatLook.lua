-- Bound (B1) to the void-cat object templates: every cat actor that is created (load,
-- summon, coming back into view) is reported so our pets keep their own coat.
-- Verified 20261019.16318.W, 2026-10-21: owner is the BP_Void_Cat_C actor, and on_begin
-- also fires for a cat summoned while playing (docs/research/fixed-coat.md).
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

return M
