-- Mood is derived from needs every time it is asked for, never stored.
local needsData = require("pawhome.data.needs")
local Needs = require("pawhome.pets.needs")

local M = {}

function M.compute(pet, sleeping)
    if sleeping then return "asleep" end
    local n = pet.needs
    local hungerBad = n.hunger < needsData.hunger.critical
    local litterBad = n.bladder < needsData.bladder.critical
    if hungerBad and litterBad then return "angry" end
    if hungerBad then return "sad" end
    if litterBad or n.energy < needsData.energy.critical then return "uncomfortable" end
    if n.fun < needsData.fun.critical then return "tense" end
    if n.fun >= 70 and n.energy >= 50 then return "playful" end
    if n.energy >= 85 then return "energized" end
    local avg = Needs.average(pet)
    if avg >= 70 then return "happy" end
    if avg >= 45 then return "content" end
    return "tense"
end

return M
