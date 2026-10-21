-- Walking-cat probe: B1 Component binding on UB1AnimToTexComponent (VAT objects).
local Core = require("PawWalk.Core")
local M = {}
function M.on_begin(self, comp)
    local ok, actor = pcall(Core.m, comp, "GetOwner")
    if not ok then Core.log("vat comp: GetOwner failed " .. tostring(actor)); return end
    local okD, dtid = pcall(function() return tostring(actor.ObjectDataTableId) end)
    if okD and dtid:find("Void_Cat") then Core.addCat(actor, "vatcomp") end
end
return M
