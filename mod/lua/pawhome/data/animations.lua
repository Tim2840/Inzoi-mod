-- How the cat looks alive without walking (docs/research/walking-cat.md, option a).
--
-- The inZOI cat (BP_Void_Cat) is a VAT mesh with nine baked animations; nothing else can be
-- played (4.8 in the research). Names are the game's AnimSequence names; an unknown name is
-- ignored by the game (the cat keeps what it is doing), so a typo cannot break the cat.
-- `seconds` is the length of a one-shot (from the game's montage rows); loops have none.
-- VAT animations do not blend: every switch shows the new animation's first frame at once,
-- so only animations that start from the sitting pose are used, and one-shots return to a
-- sitting idle when they end.
return {
    sequences = {
        -- `cycle`: real seconds after which B1 rotates/restarts the idle loop so the VAT
        -- playback clock resets and the cat continuously moves at 30 FPS instead of freezing.
        sit1      = { name = "ANIM_VoidCat_Sit_Idle_01", loop = true, cycle = 6.0 },
        sit2      = { name = "ANIM_VoidCat_Sit_Idle_02", loop = true, cycle = 8.0 },
        welcoming = { name = "ANIM_Void_Cat_Welcoming", seconds = 5.7 },
        eat       = { name = "ANIM_VoidCat_Eat", seconds = 8.7 },
        patted    = { name = "ANIM_VoidCat_Being_Patted", seconds = 12.2 },
        gift      = { name = "ANIM_VoidCat_Give_Gift", seconds = 9.7 },
        takeFood  = { name = "ANIM_VoidCat_Take_Food", seconds = 12.0 },
        hiss      = { name = "ANIM_Void_Cat_Hissing", seconds = 2.7 },
        scared    = { name = "ANIM_Void_Cat_Scared", seconds = 2.5 },
    },

    -- care from the Paw Home panel (data/actions.lua `animation`) -> sequence key
    actions = {
        pet_eat = "eat",
        pet_play = "welcoming",
        pet_cuddle = "patted",
        pet_groom = "patted",
        pet_litter = "takeFood",
        pet_happy = "gift",
        pet_cower = "scared",
        pet_sniff = "takeFood",
    },

    -- What the cat does now and then while it is at home, by mood (pets/moods.lua).
    -- base: the sitting idle the cat returns to; extra: occasional one-shots with weights.
    -- Restless or unhappy cats get their reaction rarely; a sleepy cat only sits quietly.
    moods = {
        happy         = { base = "sit1", extra = { { "welcoming", 1 }, { "gift", 1 } } },
        playful       = { base = "sit1", extra = { { "welcoming", 2 }, { "gift", 1 } } },
        energized     = { base = "sit1", extra = { { "welcoming", 1 } } },
        content       = { base = "sit1", extra = { { "welcoming", 1 }, { "patted", 1 } } },
        asleep        = { base = "sit2", extra = {} },
        sad           = { base = "sit2", extra = { { "scared", 1 } } },
        sick          = { base = "sit2", extra = { { "scared", 1 } } },
        uncomfortable = { base = "sit1", extra = {} },
        tense         = { base = "sit1", extra = { { "scared", 1 } } },
        angry         = { base = "sit1", extra = { { "hiss", 1 } } },
    },

    idle = {
        everyMinutes = 20,   -- game minutes between idle changes of one cat (+- jitter)
        jitterMinutes = 10,
        extraChance = 0.25,  -- chance that an idle change is a one-shot from `extra`
        busyGraceSeconds = 15, -- after the game played something on the cat, wait this long
    },
}
