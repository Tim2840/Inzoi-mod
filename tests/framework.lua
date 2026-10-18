-- Minimal test framework (no dependencies, runs on plain Lua 5.1-5.4).
local T = { passed = 0, failed = 0, failures = {}, current = "" }

function T.test(name, fn)
    T.current = name
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = name .. "\n" .. tostring(err)
    end
end

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.eq(a, b, msg)
    if a ~= b then error((msg or "values differ") .. ": expected " .. fmt(b) .. ", got " .. fmt(a), 2) end
end

function T.near(a, b, eps, msg)
    if math.abs(a - b) > eps then
        error((msg or "not close") .. ": expected " .. b .. " +- " .. eps .. ", got " .. a, 2)
    end
end

function T.truthy(v, msg)
    if not v then error(msg or "expected a truthy value", 2) end
end

function T.falsy(v, msg)
    if v then error(msg or "expected a falsy value", 2) end
end

function T.gt(a, b, msg)
    if not (a > b) then error((msg or "not greater") .. ": " .. tostring(a) .. " > " .. tostring(b), 2) end
end

function T.lt(a, b, msg)
    if not (a < b) then error((msg or "not less") .. ": " .. tostring(a) .. " < " .. tostring(b), 2) end
end

return T
