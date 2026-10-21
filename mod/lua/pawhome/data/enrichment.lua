-- Cat furniture the game sells in Build mode (category "Pet"; see docs/research/cat-items.md).
-- Each piece on the household's lot slows the decay of some needs: 0.25 = 25% slower.
-- Several pieces add up, capped at maxReduction per need. Duplicates of one piece count once.
return {
    order = { "CatScratcher01", "CatTower01", "CatWheel01" },
    items = {
        CatScratcher01 = { fun = 0.20 },
        CatTower01     = { fun = 0.15, energy = 0.15 },
        CatWheel01     = { fun = 0.25 },
    },
    -- other object rows that count as one of the pieces above (colour variants)
    aliases = { CatTower01_v01 = "CatTower01" },
    maxReduction = 0.5,
}
