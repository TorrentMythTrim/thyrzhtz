# Milestone 2 — "Карта-заготовка и дома" (blockout map and houses): audit report

- Date: 2026-11-14
- Plan: `docs/game-plans/Gribnye_strazhi_tekhplan.pdf`, page 11 (milestone 2)
- Project: Roblox Studio place "GUARDIAN TEST", audited through the Studio MCP bridge
- Backup: `backup-manifest-2026-11-14.md` (place version 14); milestone 1 state is place version 15
- **Status: PASSED.** No gap was found in the game itself; one defect was found and fixed in the tests
- The change is saved to Roblox together with milestone 3 (version given in the milestone 3 report)

## 1. Requirements and checklist

| # | Requirement from the plan | What was checked | Result |
| --- | --- | --- | --- |
| 1 | Blockout of Mushroomhaven from simple blocks: player plots, ruined village with the elder's house and two portals, "Old Garden" sub-zone next to the village | `Workspace.Map` contents | Pass |
| 2 | Plot layouts for a 20-player server: 20 solo, 10 duo, 6 trio, 5 quartet houses; the server picks the layout by party format | `Shared.Modules.Layout` geometry for all four formats; live rebuild of every layout | Pass |
| 3 | House blank in four sizes, for 1, 2, 3 and 4 players | `ServerStorage.Templates.Plots.Plot_1..4` | Pass |
| 4 | A player or team gets a free house on join; the house is freed on leave | Live join, leave, 20 teams on one server | Pass |
| 5 | Starter kit: basket, simple sickle, 3 common spores, empty garden bed; the research book lies on a dusty table in the house, becomes an interface icon when picked up and takes no inventory slot | New profile in a live session; book picked up by walking to it and pressing the prompt key | Pass |
| 6 | Inventory and quick-access bar | Real key presses and the real remotes | Pass |
| Done when | The player enters the test game and gets a house with the starter kit; the village and the Old Garden can be reached on foot from the house | Character walked both routes with pathfinding | Pass |

## 2. Checks and results

### Map (static)

- `Workspace.Map`: `Ground`, `Village`, `OldGarden`, `Forest`, `Bounds`, `Plots` (edit-time preview of 20 plots).
- Village: `ElderHouse`, `PortalRaid`, `PortalNext`, five ruined houses, plaza, well, notice
  board, palisade with four gates, merchant stall. Place labels carry locale keys
  (village, elder, Old Garden, both portals).
- Old Garden: walls with a gate, four paths, fountain, greenhouse, shed, garden beds,
  12 trees, 18 bushes, 12 mould patches.

### Layouts (computed from `Layout.Plots`)

| Format | Houses | Seats per house | Overlapping plots | Corners outside map bounds | Overlap with Old Garden |
| --- | ---: | ---: | ---: | ---: | ---: |
| solo | 20 | 1 | 0 | 0 | 0 |
| duo | 10 | 2 | 0 | 0 | 0 |
| trio | 6 | 3 | 0 | 0 | 0 |
| quartet | 5 | 4 | 0 | 0 | 0 |

Every plot starts at least 6 studs outside the ring road. In a live session each format
was built in turn (20, 10, 6, 5 plots) and the player kept a house of the right capacity.

### House templates

| Template | Plot ground | House floor | Sleeping beds | Garden bed places | Spawn, table, research book with prompt, owner sign |
| --- | --- | --- | ---: | ---: | --- |
| Plot_1 | 42 × 56 | 16 × 12 | 1 | 3 | all present |
| Plot_2 | 58 × 66 | 22 × 14 | 2 | 4 | all present |
| Plot_3 | 72 × 78 | 28 × 17 | 3 | 6 | all present |
| Plot_4 | 86 × 90 | 34 × 20 | 4 | 7 | all present |

Ground sizes equal `Config.Map.Plots.Sizes`; floors are the configured house size minus
the 1-stud walls.

### Live session, new profile

- Join: the player got `Plot_01` (owner attribute equals the party host, capacity 1,
  owner sign filled) and stood 3.8 studs from the plot's spawn point.
- Starter kit: basket 1, simple sickle 1, fly agaric spore 3, empty garden bed 1; quick
  bar slots 1–4 filled in that order; the sickle is the equipped weapon.
- Research book before pickup: all 5 parts visible on the table in the player's own
  house, prompt enabled with localized text, floating marker shown, HUD book icon
  hidden; the neighbouring house's book prompt is disabled.
- Pickup: the character walked through the door to the table and pressed the prompt
  key → `research_book = 1`, quick bar unchanged, used inventory slots unchanged, HUD
  book icon visible in the next session. A second pickup is refused.
- Quick bar and inventory: key `3` selected slot 3 on the server; key `B` opened the
  inventory panel; a `SetHotbar` request over the real remote put compost in slot 6 and
  the slot was still there after a rejoin (milestone 1 persistence run).
- Routes: house → village plaza (arrived 23 studs from the centre, plaza radius 34) →
  Old Garden (arrived inside the garden rectangle). Both walked by pathfinding with no
  teleport.
- Respawn: after the character died it reappeared 3.8 studs from the home spawn point.
- Leave: console shows the house being freed when the player leaves.

## 3. Issues found

1. **The test suite changed the player's saved profile.** `AuditHousing.spec` picked up
   the research book and never put it back, so after any test run the player owned the
   book for good and the "book on the table" start of the game could not be seen or
   tested again. Found when a brand-new profile had the book right after the first run.
2. **No test covered house allocation between teams** (different teams get different
   houses, a full server has none left, leaving frees a house).

No defect was found in `HouseService`, `InventoryService`, `Layout`, the map or the
plot templates.

## 4. Changes made

### `ServerStorage.Tests.AuditHousing.spec` (36 → 80 lines)

Copy in this repository: `docs/audits/milestone-2/AuditHousing.spec.luau` (same bytes,
hash `433f8694`; before the change the hash was `53ef7b26`).

- The book test now starts from "no book", also checks that the book uses no inventory
  slot and cannot be put on the quick bar, and always restores the previous book state.
- New test "each team gets its own free house, a full server has none left, leaving
  frees one": fills all 20 solo houses with stand-in teams, checks every house is
  different and owned by the right team, that the 21st team gets none, that a freed
  house is handed out again, and that the real player's house is untouched afterwards.
- The two existing tests (layouts, release and reassign) are unchanged.

## 5. Tests run and results

| Test | Result |
| --- | --- |
| Layout geometry for 4 formats | 0 overlaps, 0 corners out of bounds, 0 garden overlaps |
| Templates `Plot_1..4` | all required parts present, sizes match the config |
| Full suite before the change | 98 passed, 0 failed — but the profile gained the book |
| Full suite after the change | **99 passed, 0 failed**, 43.9 s; items and quick bar identical before and after; 1 of 20 houses owned |
| Walk house → village → Old Garden | reached both |
| Book pickup through the real prompt | succeeded, no slot used |
| Respawn | at the home spawn |

## 6. Remaining limitations

- **One real player.** Studio play mode has a single client, so allocation between
  teams was tested with stand-in team ids on the live `HouseService`, not with several
  connected players.
- **Layout by party format** is chosen when the first team arrives (from teleport data)
  or from `Config.Map.DefaultFormat`. Sending each party to a server of its own format
  is the lobby's job in milestone 9; until then every player is a solo team.
- **Trio servers seat 18** (6 houses × 3) while the server limit is 20, as in the design
  document's table. A 19th and 20th player would get the existing "no free house"
  message; the lobby should cap trio servers at 18.
- **House blanks are built from parts in Studio** by `ServerStorage.Modules.MapBuilder`,
  not in Blender as the plan's tool tag says. This is fine for a blockout; final models
  belong to milestone 10.
- **Figma mock-up.** The inventory and quick bar exist and work; whether they match the
  Figma draft could not be checked (no Figma access in this task).
- A house's capacity is not checked against the size of the team that receives it;
  this also depends on the lobby (milestone 9).