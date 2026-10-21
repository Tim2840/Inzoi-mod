-- Gifts a cat brings after a happy moment. They are real inZOI items: the game's own object
-- (data/Object row id in `object`) is put in the Zoi's bag by a data script, and the household's
-- album remembers which kinds it has received. tools/../mod/ui/bridge.js builds the scripts from
-- the same object ids (a test keeps the two lists equal).
-- Higher bond levels bring gifts more often and make the rarer ones likelier.
return {
    order = { "stone", "catnip", "treat", "toy", "plush", "bouquet", "ribbon", "amethyst", "aquamarine", "emerald" },
    stone      = { rarity = "common",   object = "CarriableStone01" },
    catnip     = { rarity = "common",   object = "CatLeaf01" },
    treat      = { rarity = "common",   object = "CatPuree01" },
    toy        = { rarity = "common",   object = "CatToy01" },
    plush      = { rarity = "common",   object = "GiftCatDoll01" },
    bouquet    = { rarity = "uncommon", object = "GiftBouquet01" },
    ribbon     = { rarity = "uncommon", object = "CollectionRibbonCoral01" },
    amethyst   = { rarity = "uncommon", object = "AmethystStone" },
    aquamarine = { rarity = "rare",     object = "AquamarineStone" },
    emerald    = { rarity = "rare",     object = "EmeraldStone" },

    rarityOrder = { "common", "uncommon", "rare" },
    rarityWeight = { common = 70, uncommon = 25, rare = 5 },
    -- weight x (1 + level * shift): rarer gifts gain more from a closer bond
    rarityShift = { common = 0, uncommon = 0.6, rare = 1.6 },
    level = { stranger = 0, acquainted = 1, friend = 2, best_friend = 3 },

    -- chance of a gift after a happy moment, by bond level
    chance = { stranger = 0.15, acquainted = 0.25, friend = 0.35, best_friend = 0.5 },
}
