# Milestone 5 — Combat and Monsters: audit report

Date: 2026-11-14. Plan reference: technical plan, milestone 5 (design document steps 4.1–4.7).
Project: Roblox Studio place "GUARDIAN TEST", audited and edited through Studio MCP. All play-mode checks ran with `GS_ForceMemoryData = true`, so no DataStore was read or written. The place was saved as cloud version 20 after the changes (saved, not published).

**Status: passed.** All eight plan items and both "done when" criteria are met and covered by passing tests. The roster is complete: 10 regular and 5 elite types exist with config, model, behaviour and tests. What was checked by other means, or not at all, is listed under "Not verified".

## Roster: what was there and what was missing

Verified against the project before any change. Names are the plan's names; the ids are the keys in `Config.Monsters`.

| Type (plan name) | Id | State found | State now |
| --- | --- | --- | --- |
| Rot Sprout — Гнилой Росток | `rot_sprout` | implemented | unchanged, tested |
| Spore Mosquito — Споровый Комар | `spore_mosquito` | implemented | unchanged, tested |
| Mold Slug — Плесневый Слизень | `mold_slug` | implemented | unchanged, tested |
| Fly Agaric Bandit — Мухоморный Разбойник | `fly_agaric_bandit` | implemented | unchanged, tested |
| Root Hunter — Корневой Охотник | `root_hunter` | implemented | unchanged, tested |
| Spore Carrier — Споровый Носильщик | `spore_carrier` | implemented | unchanged, tested |
| Mist Double — Туманный Двойник | `mist_double` | one config line, no model, no behaviour | implemented, tested |
| Crystal Tick — Кристальный Клещ | `crystal_tick` | one config line, no model, no behaviour | implemented, tested |
| Ash Hound — Пепельный Пёс | `ash_hound` | one config line, no model, no behaviour | implemented, tested |
| Void Cloak — Пустотный Плащ | `void_cloak` | one config line, no model, no behaviour | implemented, tested |
| Mycelium Knight — Рыцарь Мицелия (elite) | `mycelium_knight` | implemented | unchanged, tested |
| Moon Reaper — Лунный Жнец (elite) | `moon_reaper` | implemented | unchanged, tested |
| Index Keeper — Хранитель Индекса (elite) | `index_keeper` | implemented | unchanged, tested |
| Swarm Mother — Мать Роя (elite) | `swarm_mother` | one config line, no model, no behaviour | implemented, tested |
| Mold Gardener — Садовник Плесени (elite) | `mold_gardener` | one config line, no model, no behaviour | implemented, tested |

The earlier inventory called two of these "Queen of Rot" and "Spore Gardener". The plan has no types with those names; the two config-only elites were the Swarm Mother and the Mold Gardener, and those are what was implemented.

## Requirements against the project

| # | Plan requirement | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Basics: fist, weapon attack, block or defensive mushroom, potion, three active abilities, pet | Met | `CombatService` (Attack, SetBlock, UsePotion, three ability slots on Q/R/T, TogglePet). Tests: AuditCombat "fist and all four combat weapons…", "block reduces…; potion…", "lightning chains…; blink…; berserk…; pet…". |
| 2 | Weapons: Guardian Sickle, Spore Staff (poison, sleep, slow), Mushroom Hammer (stun, armor break), Mycelium Bow (binding threads) | Met | `Config.Weapons`. Test: AuditCombatLive "weapons in a fight: staff cycles poison, slow and sleep; hammer stuns and breaks armor; bow binds". |
| 3 | Mushrooms in combat: chain lightning, healing aura, teleport, berserk at the cost of max health, and others | Met | `Config.Combat.MushroomAbilities` (15 abilities). Tests: AuditCombat "lightning chains to two real monsters; blink moves; berserk lowers max HP…", Combat "Void Galactic blink: 28 studs…". |
| 4 | Five elemental reactions, table in config | Met | `Config.Combat.Reactions`. Tests: Combat "all 5 elemental reactions… resolve symmetrically", AuditCombatLive "all five elemental reactions fire on real monsters with their own effect". |
| 5 | Poise: when it empties the enemy is stunned for 2 s and takes ×1.3 | Met | `Config.Combat.Stagger`, `MonsterService:AddPoiseDamage`. Test: Combat "live combat: Mycelium Knight… staggers for 2s at x1.3". |
| 6 | Death: portal loot is lost in a boss portal; in the world surviving monsters heal | Met | `CombatService:OnCharacterDied`, `MonsterService:OnPlayerDied`. Test: AuditCombatLive "death: loot gathered inside a boss portal is lost; in the world the surviving monsters heal". The boss portal itself is milestone 8. |
| 7 | 10 regular monsters; all attack both the player and the beds, the AI chooses between them | Met | Tests: AuditMonsters "roster…", "every type fights…", "every type also goes for the garden…", "Act 1 types keep their mechanics…", and one test per new type; Combat "AI target choice…". |
| 8 | 5 elite monsters with their mechanics | Met | Knight shield: Combat "live combat…". Index Keeper cast: AuditMonsters "Act 1 types keep their mechanics…"; book drop: AuditAlchemyFlow. Moon Reaper night-only: same AuditMonsters test. Swarm Mother and Mold Gardener: their own AuditMonsters tests. |

"Done when":

- Every weapon and every reaction works in a fight — AuditCombat, AuditCombatLive.
- Monsters attack the player and the beds, elites with their mechanics — AuditMonsters (all 15 types against the player, all 15 against a bed, every mechanic).

## Findings and fixes

1. **Six roster types existed only as a config line** (four regular, two elite). Fixed: full config, 3D templates and behaviour were added; see "Changes".
2. **Test-run filter ran a second spec by accident.** Asking the test hook for `Combat.spec` also ran `AuditCombat.spec`, because the filter matched any name containing the text. That second run of `AuditCombat.spec` failed at its berserk activation check, most likely because the ability was still on its 22-second cooldown from the first run a few seconds earlier; this was the one failure of the baseline run (114 passed, 1 failed). Fixed in `TestRunner`: an exact spec name now selects exactly that spec; a partial name still selects every match. With each spec run once the failure does not occur. Not a game defect.
3. **Void Cloak rarely teleported in a live fight.** In the first live run it walked up to a standing player before its teleport was ready and never used it. Fixed: every strike now starts with a blink behind the target whenever the teleport is ready and the cloak is not already behind them.

Observations left unchanged:

- The Act 1 spawn list stays at 6 regular and 3 elite types. `Config.Monsters` records this as an approved decision ("Variant A"), so the six new types do not spawn on their own in Mushroomhaven. They can be spawned from the dev panel (its list now shows all 15) and through `MonsterService:Spawn`. Turning one on for Act 1 means adding its id to `Act1Regular` or `Act1Elite` and a spawn point in `MonsterService:PopulateOldGarden`.
- The monster loop wraps each AI step in `pcall`, so a runtime error in a step is swallowed without a log line. The new tests call the step function directly, so an error fails the test.

## How the six new types behave

All numbers are in `Config.Monsters`.

- **Mist Double.** Takes the look of the nearest player (a half-transparent copy of their character stands in for its fog body; the wisps at its feet remain as the tell) and one of that player's slotted mushroom abilities, which it casts every 6 s as an area hit of the same element, or as a self-heal if the ability only heals. Light damage is multiplied by 1.5.
- **Crystal Tick.** Within 7 studs it jumps on the player's back, cuts their walk speed by 45% and bites once a second. Six presses of G inside 2.5 s throw it 7 studs away and stun it for 1.5 s; it cannot latch again for 5 s. The HUD shows a button with the remaining presses, which also works as the control on a phone. Killing or stunning the tick frees the player.
- **Ash Hound.** Fast (speed 24). Drops a burning patch every 4 studs it runs; a patch lasts 4 s and burns players standing in it. A bed within 5 studs catches fire for 3 s and loses health every second.
- **Void Cloak.** 75% transparent. Blinks behind the target, becomes fully visible for 1 s, strikes, and fades again.
- **Swarm Mother.** Stands still and builds one nest every 5 s, up to 10. A nest is a separate destructible object that keeps one Spore Mosquito in the air. A destroyed nest is gone; she replaces it with one more build. Any damage interrupts the build and she attacks whoever hit her for 4 s. When she dies her nests go with her.
- **Mold Gardener.** Infects beds near him every 3 s. When a fight starts, a blight field appears where he stands and grows from 6 to 30 studs. A player inside takes 2 damage on the first second and 1 more for each further second (up to 12 stacks); leaving the field resets it. Staggering him stops the spread; killing him removes the field.

## Changes in this run

New scripts (full source in this repository under `studio-src/`, byte-identical to Studio at commit time):

| Studio path | Purpose |
| --- | --- |
| `ServerStorage.Modules.MonsterBehaviors` | Behaviour of the six new types and of the nest; hooks called by `MonsterService`. |
| `ServerStorage.Modules.MonsterRosterModels` | Builders for 7 templates (six types and the nest). |
| `ServerStorage.Tests.AuditMonsters.spec` | 10 tests covering all 15 types. |
| `ServerStorage.Tests.AuditCombatLive.spec` | 3 tests: weapon effects, reactions and death rules in a live fight. |

New instances: 7 models in `ServerStorage.Templates.Monsters` (`Monster_MistDouble`, `Monster_CrystalTick`, `Monster_AshHound`, `Monster_VoidCloak`, `Monster_SwarmMother`, `Monster_MoldGardener`, `Monster_SwarmNest`). The nine existing templates were not rebuilt.

Edits to existing scripts:

| Script | Edit |
| --- | --- |
| `ReplicatedStorage.Shared.Config.Monsters` | Full definitions for the six types; new `Summons.swarm_nest`; header comment on how to enable a type in Act 1. The 10 + 5 count is unchanged. |
| `ServerScriptService.Server.Services.MonsterService` | Requires `MonsterBehaviors` and calls its hooks on spawn, step, hit, kill, clear and once per loop tick; `defOf` also reads `Summons`; new `Remove(mob)` and `ShakeOff(player)`. Existing behaviour code was not rewritten. |
| `ServerScriptService.Server.Services.CombatService` | The `CombatAction` handler accepts `shake`. |
| `ServerStorage.Modules.CombatModels` | Registers the builders of `MonsterRosterModels`; exposes `MonsterBuilders`. |
| `StarterPlayerScripts.Controllers.CombatController` | G sends `shake`; shake button in the HUD; name plate resolves the nest's name. |
| `StarterPlayerScripts.Controllers.DevPanelController` | The monster list shows all 15 types, Act 1 types first. |
| `ReplicatedStorage.Shared.Locale.Strings` | Four new strings in English and Russian. |
| `ServerStorage.Tests.TestRunner` | Exact spec name wins over partial match (finding 2). |

Backup of every script as it was before these edits: `ServerStorage._MilestoneAuditBackup_20261114_M4-7_r2`.

## Tests and results

Play mode, memory data mode, every spec in `ServerStorage.Tests` run exactly once after the last change.

| Spec | Passed | Failed |
| --- | --- | --- |
| AuditMonsters.spec (new) | 10 | 0 |
| AuditCombatLive.spec (new) | 3 | 0 |
| AuditCombat.spec | 3 | 0 |
| Combat.spec | 6 | 0 |
| Config.spec | 8 | 0 |
| Formulas.spec | 21 | 0 |
| The other 13 specs (milestones 1–4, 6, 7) | 65 | 0 |
| Total, 19 specs | 116 | 0 |

Live checks in the ordinary monster loop, real time, same build:

- The six new types were spawned 18 studs from the player and left to the loop: the Mist Double put on the copy and cast, the Ash Hound left four fire patches, the Mold Gardener's field grew, the Crystal Tick latched after about a second and the walk speed dropped from 16 to 8.8.
- Void Cloak after finding 3: blink to directly behind the player, 1 s visible, strike.
- Client: with a tick on the player the shake button was visible and read "Crystal Tick! Mash G — 6 more". Six simulated G key presses counted down 5, 4, 3, 2, 1 and released the player. The Mist Double's copied character (19 parts) was present on the client.

## Not verified

- How the seven new models look on screen. The Studio screen capture returned an empty viewport on two attempts, so the models were checked only by part count, size and their presence on the client.
- Anything that needs more than one player: two players near one tick, a Mist Double choosing between players, several players in one blight field.
- A paid ability or pet (milestone 11) and the boss portal (milestone 8), which the death rule refers to.
- Balance of the new numbers. They are first values in config and were not tuned against a real playthrough.
