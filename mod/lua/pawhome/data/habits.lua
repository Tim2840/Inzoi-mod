-- Misbehaviours a cat can have. tendency is 0-1 and is shaped by praise/scold.
-- chancePerHour is the base chance when tendency = 1 and the pet is at home.
return {
    order = { "scratch", "knock", "counter" },
    scratch = { start = 0.35, chancePerHour = 0.06, funBoost = 10 },
    knock   = { start = 0.30, chancePerHour = 0.05, funBoost = 12 },
    counter = { start = 0.30, chancePerHour = 0.05, funBoost = 8 },
    shapeStep = 0.14,   -- tendency change for one praise/scold at Pet Training 0
}
