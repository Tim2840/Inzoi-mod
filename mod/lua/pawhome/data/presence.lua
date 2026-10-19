-- Keeping the in-game cat in sync with the saved pet (only when the adapter can spawn).
-- The game may unload a cat (the player is away from the lot) or refuse to create one, so
-- the engine retries gently instead of on every tick.
return {
    retryMinutes = 60,     -- minimum game minutes between two attempts for the same pet
    maxFailures = 5,       -- after this many failed attempts in a row, pause until the next game day
}
