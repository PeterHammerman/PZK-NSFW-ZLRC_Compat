# PZK ZLRC Compat — A-Life (+Jeem) x ZomboRut / ZomboLust x Being Female (B42.21)  v 1.0

Compatibility mod. Lua integrations use the required mods' APIs and runtime hooks. With ZomboRut author permission,
the FM missionary support adds compatibility-owned animation definitions that reference ZomboRut's existing clips;
the required mods themselves are not modified. Enable this mod after all of them (`loadModAfter` is set).
Sandbox page: **ZLRC**. Turn on `Debug logging` and look for `[ZLRC]` lines in the console when reporting problems.

<img width="1024" height="874" alt="obraz" src="https://github.com/user-attachments/assets/e92e6e50-04ac-4f5c-9337-60985da7ba5f" />


## Whats adding and Limits
* Ask for X with friendly NPCS
* Ability to wash (desinfect) zombie corpse to not get stench
* Bik animations from Zombolust/Zombodesire
* Being Female integration
* Press K near atacking hostile NPCs to offer peacefull resolution with classic roleplay (provided by Zombolust and Zomborut). Hostile surrender-chain action NPC limits based on ZomboLust difficulty (Casual: 1, Normal: up to 3, Vicious: configured maximum). After resolution you have some time to walk away. Be carful with earlier wounds before surrendering - player can still die.
* Vicious difficulty from Zombolust: hostile NPC chains bypass Being Female condom use; Casual and Normal retain its normal condom behavior.
* ZomboRut's Shy (`Innocent`) personality hides defeat/subdue-style Ask-for-sex options (except the existing F-F options) and shows a disabled red-tooltip option when outdoors or when another A-Life NPC is within 8 tiles. A successful hostile NPC chain uses ZomboRut's trauma system and raises stress to maximum.
* NPC-scene womb visuals follow the scene's condom rule. ZomboLust bik videos use the existing free clips.
* NPC Ask-for-sex supports missionary for female-player/male-NPC pairs using a dedicated FM scene registration and the existing female/male missionary animation clips.
* A-life NPC from your faction will not chasing over dragged & subdued body
* Some sandbox options

Woks in SP. MP not tested (I don't have possibility to do that), Male player not tested - need integration fix with being female mod first. Some additional features, polishing will come later.

## ADDONS:
- visible pregnancy vanilla player (https://github.com/PeterHammerman/PZK-BF-VanillaBodyShapes)
- minimal Healthbar compatibility (https://github.com/PeterHammerman/PZK-NSFW-minimalHealthbarCompat)

## WIP
- Better Zombolust integration for traits, professions and excitation mechanics.


## Links to required mods:

A-life https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183

A-Life Jeem extension https://steamcommunity.com/sharedfiles/filedetails/?id=3806944055

Zombodesire https://www.loverslab.com/files/file/44539-project-zomboid-zombodesire-framework/

Zomborut https://www.loverslab.com/topic/265927-project-zomboid-zomborut-%E2%80%94-b42-nsfw-framework/

ZomboLust https://www.loverslab.com/files/file/51310-project-zomboid-zombolust/

Being Female https://www.loverslab.com/files/file/48296-being-female/


Further development will be targeted for vanilla player model only and vanilla basis. 
