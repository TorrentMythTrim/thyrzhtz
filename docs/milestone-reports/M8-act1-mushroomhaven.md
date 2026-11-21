# Milestone 8 — Act 1: Mushroomhaven: implementation report

Date: 2026-11-14. Plan reference: technical plan, milestone 8 (design document steps 7.1–7.4; decision: the reward for the Rotten Stump-Lord).
Project: Roblox Studio place "GUARDIAN TEST", inspected, edited and tested through Studio MCP. All play-mode checks ran with `GS_ForceMemoryData = true`, so no DataStore was read or written. The store names, the save schema versions and the memory attribute are exactly as found. The place was saved as cloud version 26 after the last change (saved, not published); version 25 is an earlier save of this run that lacks the last two edits.

**Status: built and tested as far as the plan is unambiguous; the milestone is not complete.** The quests, the restoration, the residents, the boss portal and the boss work and are covered by passing tests and a live walkthrough. It is not closed because: two decisions the plan leaves to you are not made (the boss reward and the elite of the Old Garden), plan item 9 is your own playthrough, "progress is saved" was checked in memory mode only, and the quest chain and every number are a draft that waits for your approval. Everything I did not decide is under "Needs your decision"; nothing there was chosen for you.

**The draft is live in the saved place, not only written down.** The plan gives the mechanisms and no content for them, and they cannot run or be tested empty, so the saved place contains a working draft: six quests (one per thing the map already has to repair: five ruins and the elder's house), two residents and two portal stages (the smallest number the plural in the plan allows), and my numbers for amounts, health and timing. None of it comes from the plan. It is all in one config module and listed under "Draft content and numbers for your approval"; treat it as a placeholder until you approve or replace it, and do not publish on the strength of it.

## Baseline

- Backup taken before any change: `ServerStorage._MilestoneAuditBackup_20261114_M8` (88 scripts, 840,367 bytes, each verified identical to its source), then the place was saved as cloud version 24 as a rollback point.
- Baseline run of all 21 specs before any change: 132 passed, 0 failed.
- What already existed for Act 1: the village blockout with five ruined houses, the elder's house with nine mould patches and five cracks, two portals labelled "inactive", the notice board and the stall; the Old Garden with its monsters and four wild mushroom spots; empty slots in the team record (`village`, `quests`, `acts`); the rule that loot found in a boss portal is lost on death. There was no elder, no quest, no way into a portal and no boss.

## Requirements against the project

| # | Plan requirement | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Village: ruined by mould, the residents fled, the elder stayed in the centre; his house is mouldy and cracked but stands; two portals that do not work | Met, with blockout models | The ruins, the elder's house and the portals are from milestone 2. Added: the elder, a figure on the plaza 16 studs from the centre with a "Talk" prompt. Both portals refuse entry until the team has opened them. Test: AuditAct1Quests "world". |
| 2 | Elder's quests: a chain that restores the village; quests are the base of a sortie; difficulty grows with team size | Met as a mechanism; the chain itself is a draft | `QuestService`: one quest at a time, taken and handed in next to the elder (the server checks the distance). Three kinds of objective: bring items, defeat monsters, free a resident. "Bring" amounts are multiplied by the team size (×1, ×2, ×3, ×4), fixed when the quest is taken; any member can bring a part. Tests: "elder", "kills", "rescue", "team size". With one player in Studio the team sizes 2–4 were set on the quest record, not played. |
| 3 | Restoration: the village changes as quests are done; the raid portal opens first, then the portal to the next land, which shows a placeholder until Act 2; the fully restored village gives the page of the ancestors | Met | Each finished quest is one step of six. Steps 1–5 replace a ruin with a whole house, step 6 takes the mould and cracks off the elder's house. The raid portal opens at step 3, the next-land portal at step 5; using it says "The next land will open with Act 2". Step 6 records the page of the ancestors on the team. Tests: "restoration". Live: after the first hand-in the client replaced `Ruin_1` with the whole house. |
| 4 | Rescued residents return to the village and trade in the shop of milestone 7 | Partly met | Two residents stand in cages of roots in the Old Garden. Freeing one records it on the team, removes the cage for that team and puts the resident behind the counter of the stall. The stall sells the same goods with or without them: the plan does not say what a resident adds to the shop (decision 4). Tests: "rescue", "residents and the stall". |
| 5 | Old Garden: wild mushrooms, monsters and the elite of the sub-zone; which elite lives there is decided together | Already in the project; the elite is not decided | Nothing changed here. The garden has had its monsters and wild mushrooms since milestone 5, with the Mycelium Knight as its permanent elite (`Config.Monsters.OldGardenBossElite`). AuditWorld.spec passes. |
| 6 | Boss portal: a way to the boss made of stages with loot and lore fragments | Met; the stages and the loot are a draft | `BossService`: each team gets its own run in its own arena. Two stage rooms, then the boss room. Clearing a stage adds its loot to the portal loot and shows a lore fragment; the loot reaches the bag only if the player leaves alive, and death loses it (design doc 4.5). Tests: AuditAct1Boss "portal", "stages", "leaving". |
| 7 | Rotten Stump-Lord: strikes with roots along straight lines, summons Rot Sprouts, opens the heart inside the trunk; to win, destroy three infected growths, then attack the heart | Met, with a blockout model; the numbers are a draft | The stump takes no damage while a growth stands; the third growth opens the trunk and shows the heart. A root strike is a warning strip on the floor and a blow 1.4 s later for whoever still stands on it. Sprouts arrive in pairs up to four alive. The stump cannot be stunned, put to sleep or pushed. Tests: "boss", "boss attacks", "victory". |
| 8 | Reward for the boss: you decide | Not done, on purpose | The boss gives nothing: no coins, dust, rank XP or item. The victory is recorded on the team (`acts.bossDefeated`, `acts.bossKills`) so a reward can be attached later. |
| 9 | End-to-end playtest: you play the whole act alone | Not done | Yours. What I ran instead is under "Live checks". |

"Done when":

- *A new player passes Act 1 from the start to the victory over the Rotten Stump-Lord.* Every step exists and is tested, and a scripted walkthrough went through the chain's first quest and a whole raid in a live session. Nobody has played it by hand from a new profile, so this is **not verified**.
- *The village is restored, the portals open.* Verified by tests and live.
- *Progress is saved.* Verified in memory mode only: a team record with quests, restoration, residents, portals, lore and the boss flag was saved, released and loaded again as a new copy through `DataService`. No real DataStore was touched, as instructed.

## How it is put together

- **Where progress lives.** Everything is in the team record, in the three tables the schema already had: `quests.active[id] = {size, progress, acceptedAt}`, `quests.completed[id]`, `village.restoration`, `village.rescued[id]`, `acts.bossPortal`, `acts.nextPortal`, `acts.lore[id]`, `acts.bossDefeated`, `acts.bossKills`, `acts.ancestorPage`. New keys appear on first use inside existing tables, as milestone 7 did with `stats.seenMonsters`; `DataSchema` and its versions are unchanged.
- **The village is drawn per team on the client.** Teams on one server are at different steps of the same village, so the server keeps the ruins and each client shows repaired houses, the clean elder's house, open portals, missing cages and residents at the stall for its own team. The server decides everything that matters: quest state, portal access, rescue.
- **The raid runs on the same server.** Each team's arena is built when the team enters and removed when the last member leaves. Arenas hang above the middle of the map, one above another (600 studs up, 140 apart, room for 20), inside the map's X and Z bounds, because the teleport ability clamps to those bounds.
- **The boss is an ordinary monster.** The stump and its growths are entries in `Config.Monsters.Summons`, so every weapon, ability, reaction and pet works on them and the client shows their health bars with no new code. Their behaviour is attached through a small extension point added to `MonsterBehaviors`.

## Implementation choices you may want to overrule

These are engineering readings of the plan, not design decisions; each is one line to change.

1. Only "bring" objectives grow with team size, which is what design doc 2.4 says literally. Kill counts do not.
2. The team size is taken when the quest is accepted (members online at that moment).
3. A resident freed before the quest that asks for it counts for that quest.
4. Kills inside the boss portal count for kill quests.
5. The next-land portal opens by restoration alone, as design doc 7.2 reads. See decision 5.
6. Leaving the portal alive at any moment keeps what was found; only death loses it.
7. If the bag is full on leaving, what did not fit stays in the portal loot for the next time instead of being lost.
8. The page of the ancestors is a record on the team, not an item in a bag.

## Needs your decision

1. **The reward for the Rotten Stump-Lord** (plan item 8; design doc 7.4 says "to be worked out"). Nothing is given. Related things that exist and are not connected: design doc 3.6 says mutation books drop from bosses; `Config.Mushrooms` has the Blight Heartcap with the Rotten Stump-Lord as its related boss; design doc 6.4 calls Star Seals the reward for raids.
2. **The elite of the Old Garden** (plan item 5). The Mycelium Knight has been there since milestone 5; I left it.
3. **Quest rewards.** Design doc 6.2 says rank also grows for quests and 3.6 says mutation books are given for quests, without amounts or which quest gives which book. The mechanism exists and is tested (`Act1.QuestXp`, `rewards.items` on a quest); the shipped values are 0 XP and no items.
4. **Residents and the stall.** Does the stall sell anything before the first resident is back? Does each resident add goods, and which? How many residents are there (draft: two) and what are they called (draft: "Villager")?
5. **Does the portal to the next land need the boss to be defeated?** Now it does not.
6. **Can the raid be repeated, and does every run give the stage loot again?** Now yes to both, and the boss can be fought again after a victory.
7. **What happens to a team's plot while the team is in the raid.** A defense wave can start on the plot while its owners are away. Nothing was done about it.

## Draft content and numbers for your approval

All of it is in `ReplicatedStorage.Shared.Config.Act1` and `Config.Monsters.Summons`; nothing below is in code.

| Quest | Objective (solo amounts) | Restores |
| --- | --- | --- |
| 1 First harvest | Bring 3 Red Fly Agaric | Ruin 1 |
| 2 Rot at the gate | Defeat 3 Rot Sprouts | Ruin 2 |
| 3 Someone in the garden | Free the first resident | Ruin 3; the raid portal opens |
| 4 Poison for the mould | Bring 2 Toxic Toadstool (grows wild in the Old Garden) | Ruin 4 |
| 5 The far corner | Free the second resident and defeat 2 Mold Slugs | Ruin 5; the next-land portal opens |
| 6 My own house | Bring 2 Mycelium Essence | The elder's house; the page of the ancestors |

- Team size multiplier for "bring": ×1, ×2, ×3, ×4.
- Residents: two, in cages at the south-west and south-east corners of the Old Garden.
- Boss portal: stage 1 is 3 Rot Sprouts and gives 1 Mycelium Essence; stage 2 is 2 Rot Sprouts and 2 Spore Mosquitoes and gives 2 Nutrient Compost. The team is returned to the village 10 s after the victory.
- Boss: 900 health; each of the three growths 120. Roots: every 6 s, 1.4 s of warning, a strip 60 studs long and 6 wide, 20 damage. Sprouts: 2 every 14 s, at most 4 alive.
- Texts: quest titles and texts in English and Russian are mine. The two lore fragments are sentences of design doc 1.2 (the Black Moon and the Grey Mould), not invented.
- One observation for balancing: a new player with 100 health who stands still in stage 1 is killed by the three Rot Sprouts in well under ten seconds. It happened in the live check.

## Changes in this run

New scripts (copies under `studio-src/`, byte-identical to Studio by length and Adler-32):

| Script | Lines | What it is |
| --- | ---: | --- |
| `ReplicatedStorage.Shared.Config.Act1` | 111 | The chain, restoration, residents, portal stages, boss numbers |
| `ReplicatedStorage.Shared.Locale.Act1Strings` | 124 | 53 texts in English and Russian |
| `ServerScriptService.Server.Services.QuestService` | 313 | Quests, restoration, residents, portal access |
| `ServerScriptService.Server.Services.BossService` | 490 | Boss portal runs and the boss |
| `ServerStorage.Modules.Act1Models` | 315 | Blockout models: elder, cages, whole houses, arena, stump, growth |
| `StarterPlayer.StarterPlayerScripts.Controllers.Act1Controller` | 318 | Elder's window, task line, the team's village, raid line |
| `ServerStorage.Tests.AuditAct1Quests.spec` | 354 | 10 tests |
| `ServerStorage.Tests.AuditAct1Boss.spec` | 318 | 7 tests |

Edited scripts: 38 lines added, none removed or changed. The exact lines are in `studio-src/changes-m8.diff`.

| Script | Added | Why |
| --- | ---: | --- |
| `Config.Monsters` | 11 | The stump and the growth as summons, with no reward |
| `Modules.Locale` | 6 | Adds the Act 1 texts to the common strings |
| `Modules.Net` | 2 | Two events: `Act1Action`, `Act1Event` |
| `Services.MonsterService` | 5 | Tells `QuestService` about each kill |
| `ServerStorage.Modules.MonsterBehaviors` | 14 | `Behaviors.Extend(id, hooks)`: another module can attach hooks to a monster id |

Instances added to the place: the elder in `Workspace.Map.Village`; a prompt on each portal; two cages in `Workspace.Act1.Captives`; `ReplicatedStorage.Act1Assets` (five whole houses and the resident figure); `Boss_RotStump` and `Boss_RotGrowth` in `ServerStorage.Templates.Monsters`. `Act1Models.Build()` rebuilds them; the server adds whatever is missing on start, so rebuilding the map with `MapBuilder.Map()` does not break Act 1.

Not changed: `DataSchema`, `Config.Game` (store names), the `GS_ForceMemoryData` attribute, every existing spec, the Old Garden.

## Tests and results

Play mode, memory data mode, a fresh session, every spec in `ServerStorage.Tests` run exactly once after the last change. The table is the final run, made in a new session immediately before the save of version 26; the session log showed "data mode memory" and no error.

| Spec | Passed | Failed |
| --- | ---: | ---: |
| AuditAct1Quests.spec (new) | 10 | 0 |
| AuditAct1Boss.spec (new) | 7 | 0 |
| The 21 specs that existed | 132 | 0 |
| Total, 23 specs, 21.6 s | 149 | 0 |

Runs after each step: quests and restoration — 10 passed; boss portal — 6 passed and 1 failed on the first run because a helper of the test itself went one room too far (the test was fixed, not the game), then 7 passed; with the client controller — all 23 specs, 149 passed; after the last edits (the server's distance check at the portals, the window moved up) — 149 passed again.

What the new tests cover:

- Quests: the chain refers only to items, monsters and residents that exist and has every text in both languages; the world has the elder, the prompts, the cages and a model for every repair, each whole house exactly where its ruin stands; team size multiplies "bring" amounts only; a quest is taken and handed in only next to the elder, items can come in parts, nothing more than needed is taken; kills count only for the named monster and only while the quest is taken; a resident is freed only at the cage and only once; portals refuse from a distance and while closed, the raid portal opens before the next-land one, and the page is given once; item and XP rewards work when configured and a full bag stops the hand-in without losing the quest; the stall sells before and after a rescue; save and reload in memory mode.
- Boss portal: stages and boss refer to things that exist and every arena lies inside the map bounds; the portal is closed until opened and a run starts at stage 1; clearing a stage gives its loot as portal loot, the lore once, and opens the way; the stump is immune until the third growth dies, then takes full damage, and cannot be stunned or moved; a root strike hurts a player on the strip after the warning and misses one who stepped aside; sprouts stop at the limit; victory sets the flag, puts the loot in the bag and returns the player to the village, and the raid can be entered again; death loses the loot and closes an empty run, leaving alive keeps it.

Live checks, one real player in a Studio play session, through the real prompts and remote events:

| Check | Result |
| --- | --- |
| Talk to the elder, accept, hand in the first quest | The window showed the quest and its amounts; after accepting, the task line appeared; after the hand-in the village showed 1/6 and the client had replaced `Ruin_1` (14 parts hidden, none colliding) with the whole house |
| Enter the raid through the portal prompt | The player stood in the arena 600 studs up, the client had the arena and three monsters, the raid line showed "stage 1 of 2" |
| A whole raid on the game's own loop (monsters removed from the server, nothing stepped by a test) | Stage 1 → stage 2 → boss with three growths → heart open → victory; 10 s later the player stood 9 studs from the raid portal with 1 Mycelium Essence and 2 Nutrient Compost in the bag, and the elder's window listed both lore fragments |
| Death in the raid | An idle character was killed in stage 1: the run closed, the arena was removed, the portal loot was empty, the player respawned at the house |
| Output log of every session | No error or warning from the new code. The only warning is the old one about asset 203785492 |
| Screen | The elder's window overlapped the health bar; it was moved up and checked again on a screenshot |

## Not verified, and what it would take

- **A playthrough by hand** (plan item 9): from a new profile to the dead boss, by you.
- **Save and reload against a real DataStore.** Needs a session with the memory attribute off, which reads and writes player records; this task must not.
- **The published game.** Nothing was published.
- **More than one player.** Team sizes 2–4 on a quest, several members in one raid, two teams seeing different villages on one server, many arenas at once: all need more players than Studio gives me. The code paths exist; only the solo ones ran.
- **The look.** Everything is blocks. The plan marks items 1, 3, 5 and 7 as Blender work; the bridge I work through has no Blender tools, and the project keeps final models for milestone 10. Whether the cages, the elder and the stump read well in the world was not judged beyond two screenshots.
- **Other screens.** The window and the task line were seen on one desktop size only. Phone layout and touch were not checked.
- **Balance.** The boss and the stages were not fought with real weapons at real health; tests kill with one blow.
- **A full bag on leaving the portal** (choice 7) and **joining a team-mate's run in progress** have code and no test.
- **Opening the elder's window from a distance.** A scripted client could ask for the window from farther than the prompt allows. It only shows the window; taking, handing in, freeing and entering are all checked for distance on the server.

## Blocked and incomplete

| What | Blocked by | What remains |
| --- | --- | --- |
| Boss reward | Decision 1 | Attach the reward where the victory is recorded |
| Old Garden elite | Decision 2 | Change one config line if it is not the Mycelium Knight |
| Quest rewards | Decision 3 | Fill `QuestXp` and `rewards` in `Config.Act1` |
| Residents in the shop | Decision 4 | Tie goods to residents, if that is what is wanted |
| Closing the milestone | Your playthrough, approval of the draft, a real save check | — |
