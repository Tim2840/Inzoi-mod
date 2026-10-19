local Mock = require("pawhome.adapters.mock")
local App = require("pawhome.app")

local H = {}

-- opts: seed, money, strays, caps, store, locale, maxPets
-- maxPets defaults to 4 here because many tests compare several pets in one household;
-- the shipped default (1) is checked on its own in test_pets.lua.
function H.new(opts)
    opts = opts or {}
    local mock = Mock.new(opts)
    local app = assert(App.new(mock, { seed = opts.seed or 4242 }))
    app:tick() -- records the start time
    assert(app:setSetting("maxPetsPerHousehold", opts.maxPets or 4))
    return app, mock
end

-- Plays the clock forward in hourly ticks (what the game adapter does).
function H.advance(app, mock, minutes, step)
    step = step or 60
    local notes, done = {}, 0
    while done < minutes do
        local dt = math.min(step, minutes - done)
        mock.clock = mock.clock + dt
        for _, n in ipairs(app:tick()) do notes[#notes + 1] = n end
        done = done + dt
    end
    return notes
end

-- Adopts shelter offer #idx and returns the pet record. Optional traits override.
function H.adopt(app, idx, traits, stage)
    local offers = app:offers(1)
    local r = app:adoptOffer(1, 101, offers[idx or 1].id, "Tester")
    assert(r.ok, r.message)
    local pet
    for _, p in ipairs(app.ctx.state.pets) do
        if p.id == r.petId then pet = p end
    end
    if traits then
        pet.traits = traits
        pet.revealed = {}
        for _, id in ipairs(traits) do pet.revealed[id] = true end
    end
    if stage then pet.stage = stage end
    return pet
end

-- Sets every need to the same value.
function H.setNeeds(pet, v)
    for k in pairs(pet.needs) do pet.needs[k] = v end
end

return H
