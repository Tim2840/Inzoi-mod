-- Gifts the cat brings after a happy moment, and the household's album of them.
local data = require("pawhome.data.keepsakes")
local Api = require("pawhome.core.api")

local K = {}

local function album(ctx, householdId)
    ctx.state.album = ctx.state.album or {}
    ctx.state.album[householdId] = ctx.state.album[householdId] or {}
    return ctx.state.album[householdId]
end

function K.chance(level) return data.chance[level] or data.chance.stranger end

-- Picks a gift for a bond level (without any chance roll).
function K.pick(ctx, level)
    local shift = data.level[level] or 0
    return ctx.rng:weighted(data.order, function(id)
        local rarity = data[id].rarity
        return data.rarityWeight[rarity] * (1 + shift * data.rarityShift[rarity])
    end)
end

-- Gives the gift to the household: the real item goes into the Zoi's bag, the album
-- remembers it. Returns the result table.
function K.award(ctx, householdId, id)
    local items = album(ctx, householdId)
    local isNew = (items[id] or 0) == 0
    items[id] = (items[id] or 0) + 1
    Api.giveItem(householdId, data[id].object)
    return {
        id = id, isNew = isNew, rarity = data[id].rarity, object = data[id].object,
        name = ctx.t("keepsakes." .. id), count = items[id],
    }
end

-- After a happy moment: maybe a gift. Returns the award or nil.
function K.roll(ctx, pet, level)
    if not ctx.rng:chance(K.chance(level)) then return nil end
    return K.award(ctx, pet.household, K.pick(ctx, level))
end

-- For the panel: every gift of the game with how many the household has.
function K.view(ctx, householdId)
    local items = householdId ~= nil and album(ctx, householdId) or {}
    local list, owned = {}, 0
    for _, id in ipairs(data.order) do
        local n = items[id] or 0
        if n > 0 then owned = owned + 1 end
        list[#list + 1] = {
            id = id, count = n, owned = n > 0, rarity = data[id].rarity,
            rarityLabel = ctx.t("rarity." .. data[id].rarity),
            name = n > 0 and ctx.t("keepsakes." .. id) or ctx.t("ui.album_unknown"),
        }
    end
    return { items = list, owned = owned, total = #data.order }
end

return K
