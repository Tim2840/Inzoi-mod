-- Small helpers shared by every module. Pure Lua, no game calls.
local M = {}

M.MINUTES_PER_HOUR = 60
M.MINUTES_PER_DAY = 1440

function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.round(x, digits)
    local m = 10 ^ (digits or 0)
    return math.floor(x * m + 0.5) / m
end

function M.copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = M.copy(v) end
    return out
end

function M.contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

function M.removeValue(list, value)
    for i, v in ipairs(list) do
        if v == value then
            table.remove(list, i)
            return true
        end
    end
    return false
end

-- Keys of a table in a stable order (numbers first, then strings).
function M.sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta == "number" end
        return a < b
    end)
    return keys
end

function M.trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Length in characters (UTF-8 aware, so 3 Chinese characters count as 3).
function M.charLength(s)
    local n = 0
    for _ in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n
end

function M.hourOfDay(minutes)
    return (minutes % M.MINUTES_PER_DAY) / M.MINUTES_PER_HOUR
end

return M
