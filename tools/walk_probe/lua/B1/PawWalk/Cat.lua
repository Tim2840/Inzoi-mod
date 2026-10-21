-- Walking-cat probe: B1 ObjectTemplate binding on the cat templates.
local Core = require("PawWalk.Core")
local M = {}
function M.on_begin(self, owner) Core.addCat(owner, "template") end
function M.on_end(self, owner) Core.endCat(owner, "template") end
function M.on_lua_message(self, owner, channel, payload)
    if type(channel) == "string" and channel:sub(1, 4) == "pwp:" then
        Core.log("B1 cat got " .. channel .. " " .. tostring(payload))
    end
end
return M
