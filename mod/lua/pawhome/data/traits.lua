-- Personality traits. A pet gets 1-3, never a conflicting pair.
--   decay      per-need multiplier on how fast the need drops
--   bondGain   multiplier on positive bond changes
--   runaway    >1 means leaves home sooner when neglected
--   scoldResist 1 = obeys, 0 = ignores scolding completely
--   mischief   multiplier on misbehaviour chance
--   trainingXp multiplier on Pet Training XP gained from this pet
--   actionGain per-action multiplier on need gains
--   reveal     multiplier on how fast "Get to Know" uncovers traits
return {
    affectionate = { weight = 10, conflicts = { "aloof" },           bondGain = 1.4, actionGain = { cuddle = 1.3 } },
    aloof        = { weight = 8,  conflicts = { "affectionate" },    bondGain = 0.6, scoldResist = 0.5, runaway = 1.2, reveal = 0.6 },
    clever       = { weight = 8,  conflicts = {},                    trainingXp = 1.5, reveal = 1.4 },
    curious      = { weight = 9,  conflicts = {},                    mischief = 1.3, decay = { fun = 1.2 } },
    frisky       = { weight = 9,  conflicts = { "lazy" },            decay = { fun = 1.3, energy = 0.85 } },
    free_spirit  = { weight = 6,  conflicts = {},                    runaway = 1.8, bondGain = 0.9 },
    glutton      = { weight = 8,  conflicts = {},                    decay = { hunger = 1.4 }, actionGain = { feed = 1.2 } },
    lazy         = { weight = 8,  conflicts = { "frisky" },          decay = { energy = 1.3, fun = 0.7 } },
    mischievous  = { weight = 9,  conflicts = {},                    mischief = 1.8, scoldResist = 0.6 },
    playful      = { weight = 10, conflicts = {},                    decay = { fun = 1.4 }, actionGain = { play = 1.3 } },
    skittish     = { weight = 7,  conflicts = {},                    bondGain = 0.8, runaway = 1.3, reveal = 0.8 },
    spoiled      = { weight = 6,  conflicts = {},                    scoldResist = 0.3, decay = { hunger = 1.15 }, bondGain = 1.1 },
    talkative    = { weight = 7,  conflicts = {},                    decay = { fun = 1.1 }, reveal = 1.2 },
}
