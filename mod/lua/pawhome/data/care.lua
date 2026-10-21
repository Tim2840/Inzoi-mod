-- How care is weighed (docs/design/gameplay-v2.md). There are no cooldowns: pressing the same
-- action again and again just gets less out of it.
return {
    -- every use of an action adds 1 to its "fatigue" n; the gain is multiplied by
    -- 1 / (1 + perUse * n), never below `min`. n drops by 1 every `recoverMinutes` game minutes.
    fatigue = { perUse = 0.6, recoverMinutes = 20, min = 0.2 },

    -- a "happy moment" is the cat's current want being met
    delight = {
        needMul = 1.25,        -- gains on the needs
        bondFlat = 2,          -- extra bond (scaled by personality and age like any other gain)
        bondMul = 2,           -- and the action's own bond change counts double
        xpMul = 1.5,
    },
}
