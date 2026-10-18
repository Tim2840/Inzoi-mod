-- Four needs, 0-100 where 100 is fully satisfied (same four as The Sims 4 pets).
-- decayPerHour is in game hours. sleepMul scales decay while the pet sleeps.
return {
    order = { "hunger", "energy", "fun", "bladder" },
    hunger  = { decayPerHour = 4.0, sleepMul = 0.4, low = 35, critical = 15, start = { 65, 95 } },
    energy  = { decayPerHour = 2.5, sleepMul = 0,   low = 30, critical = 12, start = { 60, 95 }, sleepRecoverPerHour = 9 },
    fun     = { decayPerHour = 2.2, sleepMul = 0.3, low = 35, critical = 15, start = { 45, 85 } },
    bladder = { decayPerHour = 2.8, sleepMul = 0.5, low = 30, critical = 10, start = { 60, 95 } },
    -- cats sleep roughly 23:00-07:00 (lazy cats sleep an hour more)
    sleepStartHour = 23,
    sleepEndHour = 7,
    accidentResetTo = 55,
}
