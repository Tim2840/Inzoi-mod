-- What a cat wants right now (docs/design/gameplay-v2.md). One want at a time; it lasts a few
-- game hours and simply expires when nobody takes care of it (no penalty).
--   need/onlyBelow: the want only comes up while that need is below the limit, and the lower the
--                   need the more likely it is (weight x (1 + (100 - need) / 50))
--   traitBoost: personality traits that make a want more likely
return {
    order = { "feed", "play", "cuddle", "groom", "clean_litter" },
    feed = { weight = 1.0, need = "hunger", onlyBelow = 85 },
    play = { weight = 1.0, need = "fun", onlyBelow = 90, requiresAbove = { energy = 15 } },
    cuddle = { weight = 1.2 },
    groom = { weight = 0.5 },
    clean_litter = { weight = 1.0, need = "bladder", onlyBelow = 60 },

    traitBoost = {
        playful = { play = 2.0 }, frisky = { play = 1.6 }, curious = { play = 1.3 },
        affectionate = { cuddle = 2.0 }, spoiled = { cuddle = 1.4, feed = 1.3 }, talkative = { cuddle = 1.3 },
        glutton = { feed = 2.0 }, lazy = { play = 0.6, cuddle = 1.3 },
        aloof = { cuddle = 0.5 }, skittish = { cuddle = 0.7 },
    },

    durationMinutes = { 120, 240 },     -- how long one want stays
    gapMinutes = { 30, 90 },            -- quiet time before the next one
}
