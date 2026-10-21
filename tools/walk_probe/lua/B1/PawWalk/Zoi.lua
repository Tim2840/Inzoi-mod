-- Walking-cat probe: B1 Zoi binding, only to receive B2 reports.
local Core = require("PawWalk.Core")
local M = {}
function M.on_lua_message(self, owner, channel, payload)
    if type(channel) == "string" and channel:sub(1, 4) == "pwp:" then
        Core.log("B1 zoi got " .. channel .. " " .. tostring(payload))
    end
end
return M
