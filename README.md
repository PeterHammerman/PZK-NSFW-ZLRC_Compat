# ZLRC Compat — A-Life (+Jeem) x ZomboRut / ZomboLust x Being Female (B42.21)

Separate compatibility mod. **No code from any of the three mods is copied** (ZomboRut's license forbids derivatives);
everything hooks through global tables / events at runtime. Enable it after all of them (`loadModAfter` is set).
Sandbox page: **ZLRC**. Turn on `Debug logging` and look for `[ZLRC]` lines in the console when reporting problems.


## Limits
* **Single-player / host only.** A-Life's stance lookup (`ProjectALife.Talk.stance`) is a server API; on a pure MP client
  items 1 and 5 can't tell friendly from hostile and fail safe (no strip guard stance info → NPC treated as non-hostile
  for item 1; item 5 menu hidden).
* Item 5 only offers what ZomboRut ships: there is no male-player Cowgirl and no F+F Doggy scene. NPC must be *friendly or allied*
  (A-Life stance), not merely neutral. More positions: add rows to `POSITIONS` in `ZLRC_NpcSex.lua`.
* Item 8: a Lewd-trait flat passive gain landing in the same frame as a zombie-driven gain is scaled with it.
* Rinsing works on blood/dirt visuals only; ZomboRut cum layers live on the player, not on targets.

## Install
Copy `ZLRC_Compat` into `Zomboid/mods/`, enable after ProjectALifeNPCs, (ProjectALifeJimmy), ZomboDesire, ZomboLust, ZomboRut.


