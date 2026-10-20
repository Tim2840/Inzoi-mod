-- Illness and the vet (roadmap S3). A pet whose needs stay bad can fall ill; illness makes
-- some needs drop faster until the pet recovers on its own (after recoverHours of good
-- care) or is taken to the vet (settings.vetFee). Illness never kills.
-- chancePerHour applies only while `when` holds; stage multipliers make kittens and
-- elders a little more fragile.
return {
    order = { "upset_tummy", "cold", "fleas" },
    upset_tummy = {
        when = { below = { hunger = "critical" } },
        chancePerHour = 0.04,
        decayMul = { energy = 1.3, fun = 1.2 },
        recoverHours = 36,
    },
    cold = {
        when = { below = { energy = "critical" } },
        chancePerHour = 0.03,
        decayMul = { energy = 1.5 },
        recoverHours = 60,
    },
    fleas = {
        when = { always = true },
        chancePerHour = 0.0015,          -- about once in four game weeks, only the vet cures it
        decayMul = { fun = 1.4 },
        recoverHours = nil,
    },
    stageChanceMul = { kitten = 1.3, adult = 1.0, elder = 1.5 },
    -- recovery only counts while the average of the needs is at least this
    goodCareAverage = 50,
    -- the vet visit also tops these needs up a little
    vetNeeds = { energy = 15, fun = 10 },
}
