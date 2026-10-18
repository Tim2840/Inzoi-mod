-- Mood -> buff that bonded household members receive (when the adapter supports buffs).
-- minBond: the Zoi only feels it when their bond with the pet is at least this high.
return {
    happy         = { buff = "pawhome_happy_pet",    minutes = 240, minBond = 20 },
    playful       = { buff = "pawhome_playful_pet",  minutes = 180, minBond = 20 },
    energized     = { buff = nil },
    content       = { buff = nil },
    asleep        = { buff = "pawhome_sleeping_pet", minutes = 120, minBond = 35 },
    sad           = { buff = "pawhome_worried",      minutes = 240, minBond = 25 },
    uncomfortable = { buff = "pawhome_worried",      minutes = 240, minBond = 25 },
    tense         = { buff = nil },
    angry         = { buff = "pawhome_worried",      minutes = 240, minBond = 25 },
}
