-- Entry point. The game-side glue (adapters/inzoi.lua) calls Main.start once the
-- world is loaded, then Main.tick on every game-hour change.
local App = require("pawhome.app")
local Log = require("pawhome.core.log")

local Main = { app = nil }

function Main.start(adapter)
    local app, err = App.new(adapter)
    if not app then
        Log.error("failed to start: " .. tostring(err))
        return nil, err
    end
    Main.app = app
    app:tick()
    return app
end

function Main.tick()
    if Main.app then return Main.app:tick() end
    return {}
end

return Main
