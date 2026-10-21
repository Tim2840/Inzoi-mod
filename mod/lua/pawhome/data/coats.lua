-- Coat patterns of the home cat. The game's cat (BP_Void_Cat) picks one of these textures
-- at random whenever its actor is created; the mod sets the pet's own one instead
-- (docs/research/fixed-coat.md). `texture` is the asset name under
-- /Game/Characters/Void/Void_Cat/Textures/ - verified in game 20261019.16318.W, 2026-10-21.
-- `weight` is how often a shelter cat comes with that coat.
return {
    order = { "orange_tabby", "brown_tabby", "calico", "tuxedo" },
    orange_tabby = { texture = "Void_Cat_001_D", weight = 1 },
    brown_tabby  = { texture = "Void_Cat_001_001_D", weight = 1 },
    calico       = { texture = "Void_Cat_001_002_D", weight = 1 },
    tuxedo       = { texture = "Void_Cat_001_003_D", weight = 1 },
}
