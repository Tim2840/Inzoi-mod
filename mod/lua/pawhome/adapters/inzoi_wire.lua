-- Wire format shared by the B2 adapter (adapters/inzoi.lua) and the B1 relay
-- (adapters/inzoi_relay.lua). Pure Lua, no game calls, so it is fully unit-tested.
--
--  * Messages between B2 and B1 go through inzoi.message as (channel, payload) strings.
--    Channels start with "pawhome:"; other mods' messages arrive on the same entity and
--    are ignored. Payloads may be long, so they are split into parts:
--        "<session>|<msgId>|<part>/<total>|<data>"
--  * Text that goes through a CLI command line (uimod.cfg_save) is percent-encoded so it
--    never contains spaces, quotes or line breaks.
--  * JSON is used only on the wire to the HTML UI (the engine itself never uses JSON).
local Wire = { PREFIX = "pawhome:", CHUNK = 900 }

-- ---------------------------------------------------------------- channels

function Wire.channel(kind) return Wire.PREFIX .. kind end

-- "pawhome:save" -> "save"; anything else -> nil (another mod's message).
function Wire.kind(channel)
    if type(channel) ~= "string" then return nil end
    if channel:sub(1, #Wire.PREFIX) ~= Wire.PREFIX then return nil end
    return channel:sub(#Wire.PREFIX + 1)
end

-- ---------------------------------------------------------------- percent encoding

function Wire.escape(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

function Wire.unescape(s)
    return (tostring(s):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- ---------------------------------------------------------------- multi-part messages

-- Returns a list of payload strings for one logical message.
function Wire.split(session, msgId, data, size)
    size = size or Wire.CHUNK
    data = data or ""
    local total = math.max(1, math.ceil(#data / size))
    local parts = {}
    for i = 1, total do
        local piece = data:sub((i - 1) * size + 1, i * size)
        parts[i] = ("%s|%s|%d/%d|%s"):format(session, msgId, i, total, piece)
    end
    return parts
end

function Wire.parsePart(payload)
    if type(payload) ~= "string" then return nil end
    local session, msgId, i, n, data = payload:match("^([^|]*)|([^|]*)|(%d+)/(%d+)|(.*)$")
    if not session then return nil end
    return { session = session, msgId = msgId, index = tonumber(i), total = tonumber(n), data = data }
end

-- Collects parts until a message is complete. Parts of different messages may interleave.
function Wire.assembler()
    local pending = {}
    local A = {}
    -- Returns (session, msgId, data) when the message is complete, otherwise nil.
    function A.add(payload)
        local p = Wire.parsePart(payload)
        if not p or p.index < 1 or p.index > p.total then return nil end
        local key = p.session .. "|" .. p.msgId
        local entry = pending[key] or { parts = {}, count = 0, total = p.total }
        pending[key] = entry
        if entry.parts[p.index] == nil then
            entry.parts[p.index] = p.data
            entry.count = entry.count + 1
        end
        if entry.count < entry.total then return nil end
        pending[key] = nil
        return p.session, p.msgId, table.concat(entry.parts)
    end
    return A
end

-- ---------------------------------------------------------------- mailbox files
-- A mailbox is one cfg value holding numbered entries: "seq,channel,payload;..." with
-- every field percent-encoded. The writer keeps the newest entries; the reader remembers
-- the last sequence number it handled.

function Wire.encodeMailbox(entries)
    local out = {}
    for i, e in ipairs(entries) do
        out[i] = e.seq .. "," .. Wire.escape(e.channel) .. "," .. Wire.escape(e.payload)
    end
    return table.concat(out, ";")
end

function Wire.decodeMailbox(text)
    local entries = {}
    if type(text) ~= "string" or text == "" then return entries end
    for item in text:gmatch("[^;]+") do
        local seq, ch, pl = item:match("^(%d+),([^,]*),(.*)$")
        if seq then
            entries[#entries + 1] = { seq = tonumber(seq), channel = Wire.unescape(ch), payload = Wire.unescape(pl) }
        end
    end
    return entries
end

-- ---------------------------------------------------------------- minimal JSON

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end

function Wire.toJson(v)
    local t = type(v)
    if v == nil then return "null"
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v % 1 == 0 and math.abs(v) < 2^53 then return string.format("%d", v) end
        return string.format("%.14g", v)
    elseif t == "string" then return encodeString(v)
    elseif t == "table" then
        local arr, n = isArray(v)
        local out = {}
        -- an empty table becomes [] : the UI's empty collections (pets, offers) are lists
        if arr then
            for i = 1, n do out[i] = Wire.toJson(v[i]) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            out[#out + 1] = encodeString(tostring(k)) .. ":" .. Wire.toJson(v[k])
        end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
end

function Wire.fromJson(s)
    local pos = 1
    local function ws() pos = s:find("[^ \t\r\n]", pos) or (#s + 1) end
    local value
    local function str()
        local out = {}
        pos = pos + 1
        while true do
            local c = s:sub(pos, pos)
            if c == "" then error("unterminated string") end
            if c == '"' then pos = pos + 1 break end
            if c == "\\" then
                local e = s:sub(pos + 1, pos + 1)
                local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if e == "u" then
                    local code = tonumber(s:sub(pos + 2, pos + 5), 16)
                    if utf8 and utf8.char then out[#out + 1] = utf8.char(code) else out[#out + 1] = "?" end
                    pos = pos + 6
                else
                    out[#out + 1] = map[e] or e
                    pos = pos + 2
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(out)
    end
    function value()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while true do
                ws()
                local k = str(); ws()
                if s:sub(pos, pos) ~= ":" then error("expected ':' at " .. pos) end
                pos = pos + 1
                t[k] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == "}" then return t end
                if d ~= "," then error("expected ',' or '}' at " .. pos) end
            end
        elseif c == "[" then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
            while true do
                t[#t + 1] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == "]" then return t end
                if d ~= "," then error("expected ',' or ']' at " .. pos) end
            end
        elseif c == '"' then return str()
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if not num or num == "" then error("unexpected character at " .. pos) end
            pos = pos + #num
            return tonumber(num)
        end
    end
    local ok, result = pcall(value)
    if not ok then return nil, result end
    return result
end

return Wire
