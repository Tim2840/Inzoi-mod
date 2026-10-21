-- Is there a litter box on the household's lot? Looked up once per engine tick / view.
local data = require("pawhome.data.litter")
local Api = require("pawhome.core.api")

local L = {}

function L.present(ctx, householdId)
    ctx.litter = ctx.litter or {}
    local v = ctx.litter[householdId]
    if v == nil then
        v = #Api.homeObjects(householdId, { data.object }) > 0
        ctx.litter[householdId] = v
    end
    return v
end

function L.forget(ctx) ctx.litter = {} end

return L
