-- Player-facing defaults. Saved per savegame; the settings page edits these.
return {
    language = "auto",            -- "auto" | "en" | "zh-TW"
    agingEnabled = true,          -- pets grow up and eventually pass away
    lifeScale = 1.0,              -- 2.0 = pets live twice as long
    needDecayScale = 1.0,         -- 0.5 = needs drop half as fast
    animalControl = true,         -- badly neglected pets are taken to the shelter (can be redeemed)
    maxPetsPerHousehold = 1,      -- PO 2026-10-20 (ADR 0006): one pet by default; the settings page allows up to 4
    catchupCapHours = 12,         -- never simulate more than this after a long gap (load / fast-forward)
    notificationCooldownHours = 6,
    shelterFee = 150,
    redeemFee = 200,              -- fee to get a pet back from the shelter
    strayFee = 0,
    shelterOfferCount = 3,
    misbehaviorEnabled = true,    -- scratching furniture, knocking things over
    illnessEnabled = true,        -- neglected pets can fall ill (never fatal); the vet cures them
    vetFee = 120,
    debug = false,
}
