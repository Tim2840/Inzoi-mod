-- Runs every suite and returns the number of failures.
local T = require("framework")

for _, suite in ipairs({ "test_core", "test_pets" }) do
    local ok, err = pcall(require, suite)
    if not ok then
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = suite .. " could not load\n" .. tostring(err)
    end
end

for _, f in ipairs(T.failures) do print("FAIL: " .. f .. "\n") end
print(string.format("%d passed, %d failed", T.passed, T.failed))
return T.failed
