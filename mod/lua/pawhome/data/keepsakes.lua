-- Little gifts a cat brings after a happy moment, collected in the household's album.
--   coins: money the household receives each time
-- Higher bond levels bring gifts more often and make the rarer ones likelier.
return {
    order = { "feather", "yarn", "leaf", "button", "pebble", "bell", "fishbone", "mouse", "flower", "star" },
    feather  = { rarity = "common", coins = 10 },
    yarn     = { rarity = "common", coins = 10 },
    leaf     = { rarity = "common", coins = 10 },
    button   = { rarity = "common", coins = 10 },
    pebble   = { rarity = "common", coins = 10 },
    bell     = { rarity = "uncommon", coins = 30 },
    fishbone = { rarity = "uncommon", coins = 30 },
    mouse    = { rarity = "uncommon", coins = 30 },
    flower   = { rarity = "rare", coins = 80 },
    star     = { rarity = "rare", coins = 120 },

    rarityOrder = { "common", "uncommon", "rare" },
    rarityWeight = { common = 70, uncommon = 25, rare = 5 },
    -- weight x (1 + level * shift): rarer gifts gain more from a closer bond
    rarityShift = { common = 0, uncommon = 0.6, rare = 1.6 },
    level = { stranger = 0, acquainted = 1, friend = 2, best_friend = 3 },

    -- chance of a gift after a happy moment, by bond level
    chance = { stranger = 0.15, acquainted = 0.25, friend = 0.35, best_friend = 0.5 },
}
