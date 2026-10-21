-- Care interactions. needs = flat change before trait/stage multipliers (there are no
-- cooldowns: see data/care.lua for how repeating an action wears off), bond is the base bond change,
-- xp is Pet Training XP for the Zoi doing it.
-- Actions mirror The Sims 4 pet interactions: feed, play, cuddle, groom, litter,
-- praise/scold (behaviour shaping) and get-to-know (reveals traits).
return {
    order = { "feed", "play", "cuddle", "groom", "clean_litter", "praise", "scold", "get_to_know" },
    feed = {
        needs = { hunger = 55 }, bond = 2, xp = 1,
        requiresBelow = { hunger = 85 }, animation = "pet_eat",
    },
    play = {
        needs = { fun = 45, energy = -8, hunger = -4 }, bond = 3, xp = 2,
        requiresAbove = { energy = 15 }, animation = "pet_play",
    },
    cuddle = {
        needs = { fun = 12 }, bond = 4, xp = 1, animation = "pet_cuddle",
    },
    groom = {
        needs = { fun = 6 }, bond = 2, xp = 2, animation = "pet_groom",
    },
    clean_litter = {
        scope = "household", needs = { bladder = 100 }, bond = 0, xp = 0,
        animation = nil, zoiFunPenalty = true,
    },
    praise = {
        bond = 1.5, xp = 1.5, shape = 1, animation = "pet_happy",
    },
    scold = {
        bond = -2, xp = 1, shape = -1, animation = "pet_cower",
    },
    get_to_know = {
        bond = 1.5, xp = 0.5, reveal = true, animation = "pet_sniff",
    },
}
