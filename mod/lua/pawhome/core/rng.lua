-- Seedable Park-Miller generator. Stays below 2^53 so it behaves the same on
-- Lua 5.1 (doubles) and 5.4 (integers), and its state can be saved and restored.
local Rng = {}
Rng.__index = Rng

local MOD = 2147483647
local MUL = 16807

local function defaultSeed()
    local ok, t = pcall(function() return os.time() end)
    return ok and t or 12345
end

function Rng.new(seed)
    local self = setmetatable({}, Rng)
    self:setState(seed or defaultSeed())
    return self
end

function Rng:setState(s)
    s = math.floor(tonumber(s) or 1) % MOD
    if s <= 0 then s = s + MOD - 1 end
    self.s = s
end

function Rng:getState()
    return self.s
end

-- Float in (0, 1).
function Rng:next()
    self.s = (self.s * MUL) % MOD
    return self.s / MOD
end

function Rng:int(lo, hi)
    return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng:range(lo, hi)
    return lo + self:next() * (hi - lo)
end

function Rng:chance(p)
    return self:next() < p
end

function Rng:pick(list)
    if #list == 0 then return nil end
    return list[self:int(1, #list)]
end

-- items: list; weightFn(item) -> number >= 0
function Rng:weighted(items, weightFn)
    local total = 0
    for _, it in ipairs(items) do total = total + weightFn(it) end
    if total <= 0 then return self:pick(items) end
    local r = self:next() * total
    for _, it in ipairs(items) do
        r = r - weightFn(it)
        if r < 0 then return it end
    end
    return items[#items]
end

return Rng
