# Milestone 4 — Alchemy and Index: audit report

Date: 2026-11-14. Plan reference: technical plan, milestone 4 (design document steps 3.5–3.7).
Project: Roblox Studio place "GUARDIAN TEST", audited through Studio MCP. All play-mode checks ran with `GS_ForceMemoryData = true`, so no DataStore was read or written.

**Status: passed.** Every requirement and both "done when" criteria are met and covered by passing tests. Two items were checked by reading code or by observing the client rather than by an automated assertion; they are listed under "Not verified".

## Baseline

- Backup taken before any change of this run: `ServerStorage._MilestoneAuditBackup_20261114_M4-7_r2` (81 scripts, verified identical to their sources), then the place was saved as cloud version 18 as a rollback point.
- When this run started, four scripts already differed from the earlier backup `_MilestoneAuditBackup_20261114_M4-7` (place version 16). Those changes are part of the baseline, not of this run. The ones that concern milestone 4:
  - `AlchemyService`: the lock cross on the third slot is shown only while the slot is locked; an explosion no longer tells the client that the ingredient set was right unless the Alchemist hints skill is learned (`rightSetWrongOrder` was sent unconditionally before).
  - `TestRunner` and `DevService`: the test hook accepts a spec-name filter or a folder of specs.
- Baseline test run of all 16 specs: 114 passed, 1 failed. The failure is in `AuditCombat.spec` (milestone 5) and only on its second run in the same session; it is handled in the milestone 5 report.

## Requirements against the project

| # | Plan requirement | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Alchemy table with 3 slots for mushrooms, spores and resources; two open at first, the third from the Alchemist branch | Met | `Recipes.StartSlots = 2`, `MaxSlots = 3`; `AlchemyService:UnlockedSlots` reads `skills.alchemist.third_slot`; only item kinds mushroom, spore and reagent are accepted. Tests: AuditAlchemy "duplicate ingredients… third slot requires alchemist unlock", "third slot of the table shows its lock only while it is locked". |
| 2 | A recipe is a set of ingredients and their order; identical ingredients are allowed; recipes are stored and checked only on the server, the client does not know them | Met | Recipes live in `ServerStorage.Config.Recipes` (8 recipes, including "mushroom + mushroom" and "mushroom + mushroom + mushroom"). A scan of every script under ReplicatedStorage, StarterPlayer, StarterGui and ReplicatedFirst found no recipe id and no reference to the recipe config. The client snapshot carries only `team.recipes.details`, which holds opened recipes. Tests: AlchemyIndex "security: recipes live only in ServerStorage", AuditAlchemyFlow "done-when" (exactly one recipe visible after one book). |
| 3 | Wrong order: explosion animation and loss of 10% of resources. Right order: a new mutation | Met | `AlchemyService:Mix` and `ComputeBurn`. Tests: AuditAlchemy "wrong order burns 10 percent…" (30 → 27, 20 → 18), "successful server mix consumes exact ordered inputs…", AlchemyIndex "explosion burn". Client observation in play mode: after a wrong-order mix the client created the neon explosion ball with smoke; after the right order it created the result mushroom with sparkles. |
| 4 | Mutation books open recipes; they drop from bosses and the elite Index Keeper and are given for quests; paid books in milestone 11 | Met for the sources that exist before milestone 8 | `AlchemyService:ReadBook` opens the next unknown recipe of the book and consumes one copy; a book whose recipes are all known is not consumed. The Index Keeper drops one book from its pool on death (`MonsterService:OnMonsterKilled`). Index milestone "m10" also grants a book. Tests: AuditAlchemy "mutation book unlocks one recipe…", AuditAlchemyFlow "Index Keeper drops one mutation book", "a book opens its recipes one at a time…", AlchemyIndex "books: every mutation book maps to valid server recipes". Boss and quest sources belong to milestone 8, paid books to milestone 11. |
| 5 | Index card: appearance, habitat, recipe, element, mutation chance, related monster, related boss, discovery history; inapplicable fields are hidden | Met | `IndexService.RecordInProfile` stores base, variations, gold, first time, how and count. `IndexController` fills FieldVisual, FieldHabitat, FieldMutChance, FieldRecipe, FieldMonster, FieldBoss, FieldHistory and a 3D preview, and sets `Visible` from whether the data exists (lines 374–404). Test: AuditAlchemyFlow "every server recipe mixes… complete Index card data" checks name, element, mutation chance, appearance template, client preview, related monster and Index entry for all 8 results. |
| 6 | Index rewards, connected after the owner's decision | Implemented | `Config.Index` is marked "approved Variant A": instant spore dust and rank XP per rarity, 50% for a variation, crystals for a gold card, five milestones. Tests: AlchemyIndex "index Variant A…", "index milestones & schema v2 migration". The approval itself is taken from the config comment. |

"Done when":

- A mutation can be produced from a book recipe, and the wrong order costs 10% of the resources — verified by AuditAlchemyFlow "done-when" (book → opened recipe → mix → wrong order).
- A new mushroom appears in the Index with a card — verified by the same test (entry with `how = "alchemy"`, count 1, first time) and by the card-data test.

## Findings

No defect was found in milestone 4 during this run. Observations left unchanged because they are design choices, not deviations from the plan:

- The explosion burns 10% of the player's whole stock of each distinct ingredient placed on the table, with a minimum of one item. A stack of 1–4 items therefore loses one item, which is more than 10%. Table upgrades lower the rate to 4% at most, and a Star Catalyst prevents the loss.
- The history line of the card shows how the mushroom was obtained and how many times. The first-discovery time is stored in the profile but not displayed.

## Changes in this run

- Added `ServerStorage.Tests.AuditAlchemyFlow.spec` (4 tests). Source: `studio-src/ServerStorage/Tests/AuditAlchemyFlow.spec.luau`.
- No game code was changed for this milestone.

## Tests and results

Play mode, memory data mode, each spec run exactly once.

| Spec | Passed | Failed |
| --- | --- | --- |
| AlchemyIndex.spec | 6 | 0 |
| AuditAlchemy.spec | 7 | 0 |
| AuditAlchemyFlow.spec (new) | 4 | 0 |
| Config.spec | 8 | 0 |
| Formulas.spec | 21 | 0 |
| Total | 46 | 0 |

Manual check in the same build: a real mix request at the table (distance check on) with the wrong order returned "explosion" and left 27 of 30 mushrooms; the right order returned the new species. The client created the explosion effect and the result mushroom.

## Not verified

- The Index window was not opened and looked at on screen. The card fields and their visibility rules were verified by reading `IndexController` and by confirming that the window, the detail card and the 3D preview exist in the player's GUI.
- Book drops from bosses and books as quest rewards do not exist yet (milestone 8), and paid books belong to milestone 11.
