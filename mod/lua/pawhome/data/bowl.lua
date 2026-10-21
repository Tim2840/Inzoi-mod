-- The food bowl: a Build Mode object in the Pet category (PawHome_FoodBowl, the game's own bowl model).
--   meals:         meals in a full bowl; the Zoi fills it from the bowl's own menu
--   autoBelow:     a cat this hungry (needs.hunger at or below) goes to a filled bowl by itself
--   autoGapMinutes: game minutes before the same cat eats from the bowl by itself again
--   frontCm:       how far in front of the bowl the cat is put when it comes to eat
return {
    object = "PawHome_FoodBowl",
    meals = 4,
    autoBelow = 45,
    autoGapMinutes = 90,
    frontCm = 35,
}
