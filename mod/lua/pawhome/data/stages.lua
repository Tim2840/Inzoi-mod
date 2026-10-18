-- Life stages, lengths in game days (multiplied by settings.lifeScale and a
-- per-pet +-15% roll). Pets only die of old age, like in The Sims 4.
return {
    { id = "kitten", days = 5,  decayMul = { hunger = 1.3, fun = 1.4, energy = 1.1 }, bondGain = 1.2 },
    { id = "adult",  days = 16, decayMul = {},                                         bondGain = 1.0 },
    { id = "elder",  days = 8,  decayMul = { energy = 1.3, fun = 0.7 },                bondGain = 1.0 },
}
