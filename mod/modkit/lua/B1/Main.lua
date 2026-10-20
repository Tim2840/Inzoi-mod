-- Paw Home, B1 (game thread) boot module: runs the relay between B2 and the UI.
local Runtime = require("pawhome.adapters.inzoi_b1")

local M = {}

function M.on_begin()
    Runtime.start()
end

-- Called as on_tick(dt) or on_tick(self, dt); the last numeric argument is the frame time.
function M.on_tick(...)
    local dt = select(select("#", ...), ...)
    if type(dt) == "number" then Runtime.tick(dt) end
end

function M.on_end()
    Runtime.stop()
end

return M
