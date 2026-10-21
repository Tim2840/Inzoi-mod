-- Walking-cat probe: B2 ObjectTemplate binding on the cat templates. Takes commands from B1
-- (inzoi.message.send_to_sim) and answers with send_to_client to the same entity.
local M = {}

local function m(obj, name, ...)
    local f = obj[name]
    if f == nil then error("no method " .. name) end
    return f(obj, ...)
end

local function vs(v)
    local ok, s = pcall(function() return string.format("(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z) end)
    return ok and s or tostring(v)
end

local function reply(owner, text)
    local ok, eid = pcall(function() return owner:GetObjectKey().Value end)
    if ok then pcall(inzoi.message.send_to_client, eid, "pwp:b2", text) end
end

local function nums(s)
    local t = {}
    for n in tostring(s):gmatch("[-%d%.]+") do t[#t + 1] = tonumber(n) end
    return t
end

function M.on_lua_message(self, owner, channel, payload)
    if type(channel) ~= "string" or channel:sub(1, 4) ~= "pwp:" then return end
    local verb = channel:sub(5)
    local out
    if verb == "info" then
        local parts = {}
        local function try(label, fn)
            local ok, r = pcall(fn)
            parts[#parts + 1] = label .. "=" .. (ok and tostring(r) or ("ERR " .. tostring(r)))
        end
        try("loc", function() return vs(m(owner, "GetLocation")) end)
        try("yaw", function() return m(owner, "GetRotation").Yaw end)
        try("scale", function() return vs(m(owner, "GetScale")) end)
        try("site", function() return tostring(m(owner, "GetLocatedSiteDtId")) end)
        try("playing", function() return tostring(m(owner, "IsPlayingAnimation")) end)
        try("b1spawned", function() return tostring(m(owner, "IsB1Spawned")) end)
        out = "info " .. table.concat(parts, " ")
    elseif verb == "setloc" then
        local n = nums(payload)
        local ok, err = pcall(function()
            local loc = m(owner, "GetLocation")
            loc.X, loc.Y, loc.Z = n[1], n[2], n[3]
            local rot = m(owner, "GetRotation")
            if n[4] then rot.Yaw = n[4] end
            m(owner, "SetLocationAndRotationOnlySimul", loc, rot, false)
        end)
        local okL, now = pcall(m, owner, "GetLocation")
        out = "setloc " .. tostring(ok) .. " " .. tostring(err) .. " now " .. (okL and vs(now) or "?")
    elseif verb == "scale" then
        local n = nums(payload)
        local ok, err = pcall(function()
            local v = m(owner, "GetScale")
            v.X, v.Y, v.Z = n[1], n[1], n[1]
            m(owner, "SetScale", v)
        end)
        local okS, now = pcall(m, owner, "GetScale")
        out = "scale " .. tostring(ok) .. " " .. tostring(err) .. " now " .. (okS and vs(now) or "?")
    else
        out = "unknown " .. verb
    end
    reply(owner, out)
end

return M
