-- Need decay, sleeping and the litter-box accident.
local data = require("pawhome.data.needs")
local stages = require("pawhome.data.stages")
local Util = require("pawhome.core.util")
local Traits = require("pawhome.pets.traits")

local N = {}

function N.initial(ctx)
    local out = {}
    for _, id in ipairs(data.order) do
        local range = data[id].start
        out[id] = ctx.rng:range(range[1], range[2])
    end
    return out
end

function N.state(id, value)
    local def = data[id]
    if value < def.critical then return "critical" end
    if value < def.low then return "low" end
    return "ok"
end

function N.isCritical(pet)
    local count = 0
    for _, id in ipairs(data.order) do
        if pet.needs[id] < data[id].critical then
            count = count + 1
            if id == "hunger" or id == "bladder" then return true end
        end
    end
    return count >= 2
end

function N.average(pet)
    local sum = 0
    for _, id in ipairs(data.order) do sum = sum + pet.needs[id] end
    return sum / #data.order
end

function N.sleeping(pet, worldMinutes)
    local h = Util.hourOfDay(worldMinutes)
    local from, to = data.sleepStartHour, data.sleepEndHour
    if Traits.has(pet, "lazy") then to = to + 1 end
    if from > to then return h >= from or h < to end
    return h >= from and h < to
end

local function stageMul(pet, id)
    for _, s in ipairs(stages) do
        if s.id == pet.stage then return (s.decayMul and s.decayMul[id]) or 1 end
    end
    return 1
end

-- Returns true when the pet had a litter accident during this step.
function N.step(ctx, pet, minutes, sleeping)
    local hours = minutes / 60
    local accident = false
    for _, id in ipairs(data.order) do
        local def = data[id]
        local v = pet.needs[id]
        if id == "energy" and sleeping then
            v = v + def.sleepRecoverPerHour * hours
        else
            local rate = def.decayPerHour * ctx.cfg.needDecayScale
                * Traits.keyed(pet, "decay", id) * stageMul(pet, id)
                * (ctx.decayMul and ctx.decayMul(ctx, pet, id) or 1)
            if sleeping then rate = rate * def.sleepMul end
            v = v - rate * hours
        end
        pet.needs[id] = Util.clamp(v, 0, 100)
    end
    if pet.needs.bladder <= 0 then
        pet.needs.bladder = data.accidentResetTo
        accident = true
    end
    return accident
end

function N.apply(pet, changes, gainMulFn)
    for id, delta in pairs(changes) do
        if pet.needs[id] ~= nil then
            if delta > 0 and gainMulFn then delta = delta * gainMulFn() end
            pet.needs[id] = Util.clamp(pet.needs[id] + delta, 0, 100)
        end
    end
end

return N
