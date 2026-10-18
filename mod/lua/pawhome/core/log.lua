-- Tiny logger. Keeps the last lines in memory (for a debug panel / bug reports)
-- and forwards them to the game log through an optional sink.
local Log = { lines = {}, max = 200, sink = nil, level = 2 }

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }

function Log.setSink(fn) Log.sink = fn end
function Log.setLevel(name) Log.level = LEVELS[name] or Log.level end

local function emit(name, msg)
    if LEVELS[name] < Log.level then return end
    local line = string.format("[PawHome][%s] %s", name, tostring(msg))
    Log.lines[#Log.lines + 1] = line
    if #Log.lines > Log.max then table.remove(Log.lines, 1) end
    if Log.sink then pcall(Log.sink, name, line) end
end

function Log.debug(msg) emit("debug", msg) end
function Log.info(msg) emit("info", msg) end
function Log.warn(msg) emit("warn", msg) end
function Log.error(msg) emit("error", msg) end
function Log.clear() Log.lines = {} end

return Log
