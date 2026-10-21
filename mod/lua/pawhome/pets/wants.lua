-- A pet's current want: comes up from its needs and personality, lasts a few game hours,
-- expires without penalty, and is "met" when the player does that very thing (from the panel
-- or with the game's own interaction on the cat). See docs/design/gameplay-v2.md.
local data = require("pawhome.data.wants")
local Litter = require("pawhome.pets.litter")

local W = {}

local function span(ctx, range) return math.floor(ctx.rng:range(range[1], range[2])) end

-- Can this want come up now? (a full cat is not hungry, a worn-out one does not want to play)
local function possible(ctx, pet, def)
    if def.needsLitterBox and not Litter.present(ctx, pet.household) then return false end
    if def.need and def.onlyBelow and pet.needs[def.need] >= def.onlyBelow then return false end
    for need, limit in pairs(def.requiresAbove or {}) do
        if pet.needs[need] < limit then return false end
    end
    return true
end

local function weight(pet, id)
    local def = data[id]
    local w = def.weight
    if def.need then w = w * (1 + (100 - pet.needs[def.need]) / 50) end
    for _, trait in ipairs(pet.traits or {}) do
        local boost = data.traitBoost[trait]
        if boost and boost[id] then w = w * boost[id] end
    end
    return w
end

function W.choose(ctx, pet)
    local candidates = {}
    for _, id in ipairs(data.order) do
        if possible(ctx, pet, data[id]) then candidates[#candidates + 1] = id end
    end
    if #candidates == 0 then return nil end
    return ctx.rng:weighted(candidates, function(id) return weight(pet, id) end)
end

-- Once per simulation step for a pet at home.
function W.tick(ctx, pet)
    local now = ctx.now
    local want = pet.want
    if want and now >= want.untilAt then
        pet.want = nil
        pet.wantNext = now + span(ctx, data.gapMinutes)
        want = nil
    end
    if want or now < (pet.wantNext or 0) then return end
    local id = W.choose(ctx, pet)
    if not id then return end
    pet.want = { id = id, since = now, untilAt = now + span(ctx, data.durationMinutes) }
    ctx.emit(pet, "want_new", { text = ctx.t("wants." .. id, { name = pet.name }) })
end

-- The player did `actionId`. True when that was the cat's want (a happy moment).
function W.fulfil(ctx, pet, actionId)
    local want = pet.want
    if not want or want.id ~= actionId then return false end
    pet.want = nil
    pet.wantNext = ctx.now + span(ctx, data.gapMinutes)
    pet.delights = (pet.delights or 0) + 1
    return true
end

-- For the panel: { id, text } or nil.
function W.view(ctx, pet)
    if pet.status ~= "home" or not pet.want then return nil end
    return { id = pet.want.id, text = ctx.t("wants." .. pet.want.id, { name = pet.name }) }
end

return W
