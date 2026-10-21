-- Coat pattern of a pet: chosen at adoption, kept in the save, shown by the game adapter.
local Api = require("pawhome.core.api")
local Registry = require("pawhome.pets.registry")
local coats = require("pawhome.data.coats")

local C = {}

function C.valid(id)
    return type(id) == "string" and coats[id] ~= nil and id ~= "order"
end

function C.random(ctx)
    return ctx.rng:weighted(coats.order, function(id) return coats[id].weight end)
end

function C.texture(id)
    local def = C.valid(id) and coats[id] or nil
    return def and def.texture or nil
end

-- The choices the UI offers at adoption: { { id, label }, ... }
function C.choices(ctx)
    local out = {}
    for _, id in ipairs(coats.order) do out[#out + 1] = { id = id, label = ctx.t("coats." .. id) } end
    return out
end

-- Tells the adapter which coat each pet that lives at home should show.
function C.publish(ctx)
    local list = {}
    for _, pet in ipairs(Registry.home(ctx, nil)) do
        if pet.entity ~= nil and C.valid(pet.coat) then
            list[#list + 1] = { ref = pet.entity, coat = pet.coat, texture = C.texture(pet.coat) }
        end
    end
    Api.setCoats(list)
    return list
end

return C
