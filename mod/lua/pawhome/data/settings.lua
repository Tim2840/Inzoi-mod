-- Player-facing defaults. Saved per savegame; the settings page edits these.
return {
    language = "auto",            -- "auto" | "en" | "zh-TW"
    agingEnabled = true,          -- pets grow up and eventually pass away
    lifeScale = 1.0,              -- 2.0 = pets live twice as long
    needDecayScale = 1.0,         -- 0.5 = needs drop half as fast
    neglectRunaway = true,        -- badly neglected pets may leave home
    maxPetsPerHousehold = 4,
    catchupCapHours = 12,         -- never simulate more than this after a long gap (load / fast-forward)
    notificationCooldownHours = 6,
    shelterFee = 150,
    strayFee = 0,
    shelterOfferCount = 3,
    misbehaviorEnabled = true,    -- scratching furniture, knocking things over
    debug = false,
}
