# Milestone 7 — Progression and Economy: audit report

Date: 2026-11-14. Plan reference: technical plan, milestone 7 (design document steps 6.1–6.5).
Project: Roblox Studio place "GUARDIAN TEST", audited and edited through Studio MCP. All play-mode checks ran with `GS_ForceMemoryData = true`, so no DataStore was read or written. The place was saved as cloud version 22 after the changes (saved, not published).

**Status: both "done when" criteria are met and tested; the milestone is not closed.** Three things are yours to decide and I did not decide them: the balance numbers (plan item 6 ends with your approval), a skill that does not do what the plan names (item 4), and the shop having no tools (item 5). They are listed under "Needs your decision".

## Requirements against the project

| # | Plan requirement | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Four currencies; earning and spending only on the server, with a journal | Met after a fix | `Config.Economy.Currencies` has Mushroom Coins, Spore Dust, Mycelium Crystals, Star Seals. One function changes a balance (`InventoryService.ApplyCurrency`); it refuses a negative balance and non-numbers and writes a journal line. The journal existed, but 15 of the 26 calls that pay or charge gave no source, so most income was recorded as "general" (finding 1). Tests: AuditProgression "currencies: every earn and spend is in the server journal…", Economy "live economy: currency ledger…", AuditEconomy "non-finite item and currency amounts are rejected…". |
| 2 | Nine upgrades; levels and prices in config | Met after fixes | All nine are in `Config.Economy.Upgrades` with price, growth and maximum level. Five described effects did not exist or did not match (findings 2–6). Tests: AuditProgression "upgrades: the nine of step 6.1…", "upgrades in the game…". |
| 3 | Eight Guardian ranks, growing from research, combat, farm work and quests | Met except quests | The eight ranks are in plan order. Experience came from harvests, kills, waves and Index discoveries; new monster types and new territories, named in step 6.2, gave nothing (finding 7). Quests do not exist yet — they are milestone 8; `EconomyService:AddXp` is the entry point for them. Tests: AuditProgression "ranks and skills…", "rank experience…", Economy "Guardian ranks: 8 tiers grant skill points automatically without duplicate payouts". |
| 4 | Three skill branches; the Alchemist opens the third table slot and gives hints by the three scenarios of step 6.3 | Partly met | Gardener, Fighter and Alchemist exist with 11 skills, one point per level. Third slot and the three hint cases work. Two skills differ from the plan: "more beds" does not add beds, and "new combos" adds damage but no alternative strike animations (decisions 1 and 2). Tests: AuditProgression "skills in the game…", AlchemyIndex "alchemist hints: matches all 3 scenarios of step 6.3 DD", AuditAlchemy "third slot requires alchemist unlock", "an explosion tells nothing about the recipe unless the alchemist hints skill is learned". |
| 5 | Shop: residents sell tools, recipes, seeds, materials and basic cosmetics for coins; story keys, boss spores, Index completion, raid titles and rare achievements are not sold | Partly met | A merchant stall stands in the village; ten goods: four spores, a recipe book, two materials, a bed, a healing potion, a cosmetic banner. No tool is on sale (decision 3). The server sells only what is on the list, so nothing forbidden can be bought, and Star Seal goods cannot be bought for coins. The rescued residents themselves are milestone 8. Tests: AuditProgression "shop: seeds, recipes, materials and a cosmetic for coins…", "refused operations change nothing…", Economy "shop & Star Seal Altar…". |
| 6 | Economy balance: simulate the first hours; you approve the numbers | Simulated; approval pending | `EconomySim` models three hours of solo play. Its results and every number it rests on are under "Numbers for your approval". Tests: Economy "3-hour economy simulation…", AuditProgression "balance model…". |

"Done when":

| Criterion | Result |
| --- | --- |
| Currencies are earned and spent without losses and duplicates | Met. A sequence of 11 operations across all four currencies (three upgrades, shop purchase, sale, press, forge, sell-all, two Star Seal purchases, a monster kill; 13 journal lines) ends with every balance equal to the start plus the journal, each line carrying the running balance. 15 refused operations change no currency, no item and write no line. A full bag, an oversized payout and a second forge of the same weapon charge nothing. A real client sent eight requests through the game's remote: the two valid ones were charged exactly (100 → 52 coins), the six invalid ones changed nothing. |
| Upgrades, ranks and skills are saved and affect the game | Met in memory mode. A profile and a team record with all nine upgrade levels, a rank, skill levels, skill points and the journal were saved, released, loaded again as new copies through `DataService`, and the loaded values gave the same levels, the same rank and no second payout of rank points. Effects are tested in the game for five upgrades (sickle, basket, armor, press, totems) and eight skills, and as functions for three more upgrades (garden, table, house); house healing was also measured live. What was only read in code is under "Not verified". The same path against a real DataStore was not run in this task. |

## Findings and fixes

1. **Most income was journaled without a source.** Kill rewards, wave rewards, helper rewards, the fog chest, the Spore Carrier stash, Index milestone rewards and the developer panel all wrote "general". Fixed: each now names its source (`kill:<type>`, `wave_reward:<grade>`, `wave_helper`, `fog_chest`, `carrier_stash`, `index_milestone:<id>`, `dev_panel`).
2. **Defense Totems promised "+50 gate HP per level" and gave none.** The gate always had 250. Fixed: the gate's maximum is 250 + 50 per totem level, applied within a fraction of a second of the purchase, and repair and reset use the new maximum.
3. **The Garden promised "less soil wear" and gave none.** Fixed: each garden level above the first cuts soil loss at harvest by 5% (12 at level 1, 7 at level 10). The number is new and is yours to approve.
4. **The Alchemy Table promised a chance of an extra spore and gave none.** Fixed: each table level above the first adds 8% chance of one more spore on a successful mix (40% at level 6). New number, yours to approve.
5. **The House healed at half the described rate.** The text says +3 HP per second per level; the loop gave 3 HP every 2 seconds. Fixed to match the text. Measured live at level 1: +6 every 2 seconds.
6. **Forge levels 4–6 cost coins and did nothing.** Recipes need forge levels 1–3. Fixed: the maximum is 3, and "& empowers gear" is removed from the English description (the Russian one never had it). A team that already holds level 4–6 keeps it; nothing is refunded or taken.
7. **Two research sources of rank experience from step 6.2 were missing.** Fixed: the first kill of each monster type pays 15 experience (45 for an elite), and the first visit to a territory pays 40. Each pays once per profile. The only territory today is the Old Garden; later ones are one line each in `Config.Economy.Territories`. Summons such as the Swarm Nest do not count as types. New numbers, yours to approve; 0 turns a reward off.
8. **Three operations took before they gave, or did not check the result.** No loss was reproduced, but the code allowed one if a step failed: the press took the mushroom before crediting dust, the forge did not check its two charges, and the shop and the Star Seal altar did not check that the item was delivered. Fixed: the press returns the mushroom, the forge returns the coins, and the shop and altar refund.

## Needs your decision

1. **Skill "more beds" (Gardener).** The plan says "more beds". The skill gives +5% chance of a bonus spore at harvest and is shown as "Bountiful Beds". Beds are limited by the spots built on a plot, so adding beds means changing the plot layout. Left as is.
2. **Skill "new combos" (Fighter).** The plan says alternative strike animations with extra damage. The skill adds 12% per level to the combo finisher and to poise damage; there are no alternative animations. Left as is.
3. **No tool in the shop.** The game has two tools, the basket and the sickle; both are given at the start and improved through upgrades. I did not invent a tool to sell.
4. **The server does not check where the player stands** when buying, selling, pressing or forging. The window opens anywhere with the K and M keys, so this looks intended, but the plan's anti-cheat section says the server checks distance. Say whether trading away from the stall is allowed.
5. **The cosmetic banner can be bought and then only sits in the bag.** House decoration is milestone 9.
6. **The journal keeps the last 40 operations per player.** A kill writes two lines, a wave three or four, so 40 is a few minutes of play. Raising `LedgerMaxEntries` costs a little save space.
7. **The Star Seal altar sells the Empty Spore Manuscript**, which opens a primordial recipe. The config marks the four altar goods as approved; I left them.

## Numbers for your approval

Simulation: three hours, solo, seed 2026, with the current config.

| | Rank | Experience | Coins | Dust | Crystals | Upgrade levels (sickle, basket, armor, garden, house, table, press, forge, totems) |
| --- | --- | --- | --- | --- | --- | --- |
| Hour 1 | 3 Pathfinder | 2,668 | 68 | 15 | 0 | 5, 6, 3, 3, 2, 2, 3, 2, 1 |
| Hour 2 | 4 Keeper | 5,484 | 43 | 280 | 3 | 6, 8, 5, 5, 3, 3, 4, 3, 1 |
| Hour 3 | 5 Spore Master | 8,318 | 374 | 235 | 2 | 7, 9, 6, 6, 4, 4, 5, 3, 2 |

Spore Press built at minute 14, Forge at minute 18, first forged weapon at minute 39. After three hours the upgrade levels add up to 46 of a possible 68.

What this run changed in those results: exploration experience adds 220 by hour 1 and 265 in total, and the rank at each hour mark is the same as without it. With the forge capped at 3, the coins that went into forge level 4 go into the basket (level 9 instead of 8 at hour 3).

What the simulation assumes, not measured from play: 1.4 kills a minute at 5.5 coins, 3.5 dust and 14 experience each; a wave every 18 minutes paying 95 coins, 55 dust, 1 crystal and 80 experience; 45–60% of the harvest sold. It does not model shop purchases other than beds, skills or Star Seals.

Prices per level, from `Config.Economy`:

| Upgrade | Currency | Price of each next level |
| --- | --- | --- |
| Sickle | dust | 35, 54, 84, 130, 202, 313, 485, 752, 1166 |
| Basket | coins | 40, 60, 90, 135, 203, 304, 456, 683, 1025 |
| Armor | dust | 55, 85, 132, 205, 317, 492, 763, 1182, 1832 |
| Spore Press | dust | 45, 72, 115, 184, 295, 472 |
| Forge | coins | 90, 149, 245 |
| Garden | coins | 80, 132, 218, 359, 593, 978, 1614, 2664, 4395 |
| Alchemy Table | dust | 110, 182, 299, 494, 815 |
| House | coins | 180, 306, 520, 884, 1503, 2556, 4345 |
| Defense Totems | crystals | 3, 5, 7, 10, 15 |

Rank thresholds: 0, 350, 1,100, 2,800, 6,500, 14,000, 28,000, 55,000 experience; skill points per rank: 0, 2, 2, 2, 3, 3, 3, 4.

Numbers added in this run, all in `Config.Economy`: soil wear −5% per garden level, extra spore +8% per table level, gate +50 HP per totem level (the number the description already gave), house healing 3 HP per second per level (same), exploration experience 15 / 45 / 40.

## Changes in this run

| Script | Edit |
| --- | --- |
| `ReplicatedStorage.Shared.Config.Economy` | Forge maximum 6 → 3 and its English description; new `UpgradeEffects`, `ExplorationXp`, `Territories`. |
| `ReplicatedStorage.Shared.Formulas.Growth` | `SoilWearMultiplier`; `ApplyHarvestWear` takes the multiplier. |
| `ServerScriptService.Server.Services.FarmService` | Harvest passes the garden level's wear multiplier. |
| `ServerScriptService.Server.Services.AlchemyService` | `BonusSporeChance`; a successful mix can give one more spore. |
| `ServerScriptService.Server.Services.DefenseService` | Gate maximum follows the totem level; journal sources for wave and helper rewards. |
| `ServerScriptService.Server.Services.EconomyService` | `Explore`, `CheckTerritories`, `HouseHealPerTick`; refunds in press, forge, shop and altar; house healing rate. |
| `ServerScriptService.Server.Services.MonsterService` | Journal sources for kills and the stash; first kill of a type reports to `Explore`. |
| `WeatherService`, `IndexService`, `DevService` | Journal sources. |
| `ReplicatedStorage.Shared.Locale.Strings` | Two notifications, English and Russian. |
| `ReplicatedStorage.Shared.Modules.EconomySim` | Counts exploration experience. |
| `ServerStorage.Tests.AuditProgression.spec` | New, 10 tests. Source: `studio-src/ServerStorage/Tests/AuditProgression.spec.luau`. |

The exact lines changed in every script that existed before the audit are in `studio-src/changes-since-backup.diff`. It covers milestones 5, 6 and 7: 19 scripts, 314 lines added, 46 removed, compared with the backup `ServerStorage._MilestoneAuditBackup_20261114_M4-7_r2`. The file is byte-identical to the comparison made in Studio (27,170 bytes, same checksum).

Saved data: two keys can now appear inside a profile's `stats` — `seenMonsters` and `seenTerritories`. They are created the first time they are needed, like the other counters there. The schema version, the store names (`GS_AuditProfiles_20261111`, `GS_AuditTeams_20261111`) and existing records are untouched, and `GS_ForceMemoryData` is still `true` in Studio. A player with earlier progress still gets each first-kill and first-visit reward once, because nothing recorded those before.

## Tests and results

Play mode, memory data mode, a fresh session, every spec in `ServerStorage.Tests` run exactly once after the last change.

| Spec | Passed | Failed |
| --- | --- | --- |
| AuditProgression.spec (new) | 10 | 0 |
| Economy.spec | 6 | 0 |
| AuditEconomy.spec | 6 | 0 |
| The other 18 specs (milestones 1–6, shared) | 110 | 0 |
| Total, 21 specs | 132 | 0 |

Before this run the suite had 20 specs and 122 tests, all passing.

Live checks in the same build:

- Purchases through the real client: with 100 coins, the client asked the server for a spore (8 coins) and a basket upgrade (40). Balance 52, one more spore, journal lines `shop_buy` and `upgrade:basket:2`. The same client then asked for a forbidden book, an unknown action, a sale with a non-number count, a Star Seal pet without seals, a forge without a forge, and a purchase with a table instead of an item name. Nothing changed.
- House healing: health set to 40 next to the level-1 house rose by 6 every 2 seconds.
- Territory: standing inside the Old Garden for under 3 seconds recorded it and paid 40 experience through the background loop.
- No script error in the output during the session.

## Not verified, and what it would take

- **Save and reload against a real DataStore.** The test used `DataService` in memory mode. The DataStore tests of milestone 1 are skipped in memory mode, and this task does not touch the stores.
- **Effects read in code but not asserted**: garden growth speed, the "faster growth" skill on a planted bed, the bonus spore of "more beds", the potion bonus of "stronger potions", armor damage reduction (covered by an earlier combat spec, not by this one).
- **The extra spore and the reduced soil wear in a real mix and a real harvest.** The chance and the multiplier are tested as functions; harvests and mixes in the suite ran the new lines at level 1 only.
- **Journal sources other than kills**: wave, helper, fog chest, stash, Index milestone and developer panel are one added argument each; only the kill and the developer panel were seen in a journal.
- **The windows.** Upgrade, skill, shop and altar screens and the two new notifications were not looked at on screen.
- **A second player.** Shared upgrades bought by another team member, and rewards split in a party.
- **Balance in real play.** The numbers above come from the simulation.
