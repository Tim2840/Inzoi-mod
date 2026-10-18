-- Life stages and natural death. Aging can be switched off in settings; pets
-- then stay in their current stage forever (like household aging off in The Sims 4).
local stages = require("pawhome.data.stages")
local Util = require("pawhome.core.util")

local A = {}

local function stageIndex(id)
    for i, s in ipairs(stages) do
        if s.id == id then return i end
    end
    return 1
end

local function dayMinutes(ctx, pet)
    return Util.MINUTES_PER_DAY * ctx.cfg.lifeScale * pet.lifeMul
end

-- Age (minutes) at which a stage begins / the pet's whole life ends.
function A.stageStart(ctx, pet, id)
    local days = 0
    for i = 1, stageIndex(id) - 1 do days = days + stages[i].days end
    return days * dayMinutes(ctx, pet)
end

function A.lifeEnd(ctx, pet)
    local days = 0
    for _, s in ipairs(stages) do days = days + s.days end
    return days * dayMinutes(ctx, pet)
end

function A.ageDays(pet)
    return math.floor(pet.ageMinutes / Util.MINUTES_PER_DAY)
end

-- Advances age; returns "grew_up", "died" or nil.
function A.step(ctx, pet, minutes)
    if not ctx.cfg.agingEnabled then return nil end
    pet.ageMinutes = pet.ageMinutes + minutes
    if pet.ageMinutes >= A.lifeEnd(ctx, pet) then return "died" end
    local idx = stageIndex(pet.stage)
    local nextStage = stages[idx + 1]
    if nextStage and pet.ageMinutes >= A.stageStart(ctx, pet, nextStage.id) then
        pet.stage = nextStage.id
        return "grew_up"
    end
    return nil
end

return A
