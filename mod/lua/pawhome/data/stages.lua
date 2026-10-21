-- Life stages, lengths in game days (multiplied by settings.lifeScale and a
-- per-pet +-15% roll). Pets only die of old age, like in The Sims 4.
-- scale: size of the cat in the game (1 = the game's cat); kittens are smaller.
return {
    { id = "kitten", days = 5,  scale = 0.6,  decayMul = { hunger = 1.3, fun = 1.4, energy = 1.1 }, bondGain = 1.2 },
    { id = "adult",  days = 16, scale = 1.0,  decayMul = {},                                         bondGain = 1.0 },
    { id = "elder",  days = 8,  scale = 0.95, decayMul = { energy = 1.3, fun = 0.7 },                bondGain = 1.0 },
}
