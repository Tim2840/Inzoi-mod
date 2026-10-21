-- Walking-cat probe, B1 boot module.
local Core = require("PawWalk.Core")
local M = {}
function M.on_begin() Core.log("B1 main begin") end
function M.on_tick(...)
    local dt = select(select("#", ...), ...)
    if type(dt) == "number" then Core.tick(dt) end
end
return M
