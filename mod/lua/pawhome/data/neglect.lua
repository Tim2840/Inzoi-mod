-- Neglect -> animal control -> shelter -> redeem. Mirrors the ZoiPets design:
-- soft penalty, then a warning visit, then the pet is taken to the shelter and
-- can be redeemed for a fee (after a wait, with part of the bond lost).
return {
    impoundHours = 48,        -- continuous neglect (average pet) before animal control takes the pet
    softFraction = 0.25,      -- soft penalty starts here: the bond slowly drops
    warnFraction = 0.4,       -- animal control visits and warns
    softBondLossPerHour = 0.4,

    holdDays = 10,            -- the shelter keeps the pet this long, then it is rehomed
    redeemWaitHours = 24,     -- cannot be redeemed right away
    redeemBondKeep = 0.5,     -- bond multiplier after redemption (the pet is wary)
    redeemNeeds = { hunger = 60, energy = 70, fun = 40, bladder = 70 },
}
