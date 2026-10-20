-- Table <-> string for savegame storage. Output is a Lua table literal that is
-- loaded with an empty environment, so a tampered save cannot call anything.
local M = {}

local function isIdentifier(s)
    return type(s) == "string" and s:match("^[%a_][%w_]*$") ~= nil
end

local keywords = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%a+") do
    keywords[w] = true
end

local function encodeValue(v, out)
    local tv = type(v)
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            out[#out + 1] = "0"
        elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then
            out[#out + 1] = string.format("%d", v)
        else
            out[#out + 1] = string.format("%.14g", v)
        end
    elseif tv == "string" then
        out[#out + 1] = string.format("%q", v)
    elseif tv == "boolean" then
        out[#out + 1] = tostring(v)
    elseif tv == "table" then
        out[#out + 1] = "{"
        local n = #v
        for i = 1, n do
            encodeValue(v[i], out)
            out[#out + 1] = ","
        end
        local keys = {}
        for k in pairs(v) do
            if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta == "number" end
            return a < b
        end)
        for _, k in ipairs(keys) do
            if isIdentifier(k) and not keywords[k] then
                out[#out + 1] = k .. "="
            else
                out[#out + 1] = "["
                encodeValue(k, out)
                out[#out + 1] = "]="
            end
            encodeValue(v[k], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "nil" -- functions / userdata are never saved
    end
end

function M.encode(value)
    local out = {}
    encodeValue(value, out)
    return table.concat(out)
end

function M.decode(text)
    if type(text) ~= "string" or text == "" then return nil, "empty" end
    -- Lua 5.4 everywhere (game, UE4SS, tests). The game's sandbox rejects any file that even
    -- mentions the old Lua 5.1 loader, so there is no fallback for it; `load` with an empty
    -- environment and text-only mode cannot run code from the save.
    local fn, err = load("return " .. text, "=pawhome-save", "t", {})
    if not fn then return nil, err end
    local ok, result = pcall(fn)
    if not ok then return nil, result end
    if type(result) ~= "table" then return nil, "not a table" end
    return result
end

return M
