-- Paw Home, B2 (simulation) boot module: starts the engine for this game session.
-- Loading the engine can fail (a sandbox restriction, a missing module); that must not take
-- the whole boot module down, and the runtime reports it once a Zoi is possessed.
local ok, Runtime = pcall(require, "pawhome.adapters.inzoi_b2")
if not ok then
    local err = tostring(Runtime)
    Runtime = { start = function() end, stop = function() end }
    pcall(function()
        local _, _, data = inzoi.cli.execute("entity.get_possessed")
        local eid = tonumber(tostring(data):match("(%d+)"))
        if eid then inzoi.message.send_to_client(eid, "pawhome:diag", "load failed: " .. err) end
    end)
end

local M = {}

function M.on_begin()
    Runtime.start({ spawn = true })
end

function M.on_end()
    Runtime.stop()
end

return M
