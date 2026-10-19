# Compatibility (UE4SS route)

One row per inZOI build. "T1" = main-menu smoke (`scripts/smoke-t1.ps1`: injection +
save file). "Caps" = which adapter caps have in-game evidence on that build (M1-3b).
A build may be added to `pawhome_verified_builds.txt` only when its caps column has evidence.

| inZOI build | Version | Fingerprint | UE4SS | T1 | Caps | Evidence |
|---|---|---|---|---|---|---|
| 20260915.15331.W-325961 | v0.10.0 | not recorded | v3.0.1 Beta #0 (8f7b2ca3) | PASS (ZoiPets mod, not PawHome) | none | ZoiPets `docs/04-phase0-validation.md`, 2026-09-25 |
| 20261013.16166.W-334313 | v0.11.0 | `size:289803704` | v3.0.1 Beta #0 (8f7b2ca3) | **PASS** ×2 (PawHome, 2026-10-19 first write; 2026-10-20 read-back + `.bak` rotation) | none (safe mode) | [`2026-10-19`](qa/results/2026-10-19-20261013.16166.W-334313.md), [`2026-10-20`](qa/results/2026-10-20-20261013.16166.W-334313.md) |
