# DataStore configuration: what the four store names mean

Date: 2026-11-14. Scope: inspection of project configuration and code only.
No DataStore API was called for this note: no player record was read, written, listed, migrated or deleted, and no store name was changed.

## What each name refers to

The game keeps two kinds of saved record. A **player profile** holds one player's personal progress (currencies, inventory, gear, rank, skills, Index, settings, statistics) under the key `u_<UserId>`. A **team record** holds what a party shares (house, garden beds, village restoration, opened recipes, buildings) under the key `t_<hostUserId>`.

| Store name | What it is |
| --- | --- |
| `GS_Profiles_v1` | The original player-profile store. |
| `GS_Teams_v1` | The original team-record store. |
| `GS_AuditProfiles_20261111` | A separate player-profile store introduced for the audit of 11 November 2026. Same record format, different (initially empty) storage. |
| `GS_AuditTeams_20261111` | The matching separate team-record store from the same audit. |

## Which stores the game is set to use

`ReplicatedStorage.Shared.Config.Game` currently says:

```lua
Data = {
	ProfileStore = "GS_AuditProfiles_20261111",
	TeamStore = "GS_AuditTeams_20261111",
	...
}
```

`ServerScriptService.Server.Services.DataService` takes both names from this config and uses the same name for loading and for saving (`LoadProfile` and `LoadTeam` acquire the record from `Config.ProfileStore` / `Config.TeamStore`; every later save goes back to the store the record was loaded from). There is no second read path, no fallback to another store and no copy between stores anywhere in the code.

So the game as configured **reads from and writes to the two audit stores only**. `GS_Profiles_v1` and `GS_Teams_v1` are not referenced by any live script.

Two more things affect what actually happens:

- `ServerStorage` carries the attribute `GS_ForceMemoryData = true`. In Studio this makes `DataService` keep all data in memory for the session and return before its first DataStore call. The Studio output log confirms it: every recent session printed "data mode memory", session 1, 0 coins. On a live server the attribute is ignored and the audit stores are used.
- `DataService` also touches a store called `GS_Probe` (one read of the key `probe`) to detect whether DataStores are reachable. It holds no player data.

## What the existing material shows about saved progress

There are no written audit reports in this repository or in the place. The evidence is the configuration, the backup folders in `ServerStorage`, the test specs and the Studio log.

- The backup `_MilestoneAuditBackup_20261111` (state before the 11 November audit) has `GS_Profiles_v1` / `GS_Teams_v1` in its copy of the config. Both 14 November backups already have the audit names. The switch was made during the 11 November audit and never reverted.
- Progress saved before the switch is therefore still in the `_v1` stores. Nothing in the current build reads, overwrites or deletes it, but the game cannot see it either.
- Progress saved after the switch (published test game, or Studio with the memory attribute off) is in the audit stores.
- `ServerStorage.Tests.AuditData.spec` exercises session locking against the configured stores using test keys with negative ids and deletes them when it finishes. It runs only in a play session that is in DataStore mode, so it did not run in this audit.
- The Studio session lists DataStore handles named `GS_AuditProfiles_20261114` and `GS_AuditTeams_20261114`. No live script and no backup refers to those names. A handle only shows that the name was requested during this Studio session; it does not show that data exists there.
- `ServerStorage.Modules.DataSchema` versions the record format and upgrades older records when they are loaded (covered by `AlchemyIndex.spec` and `Data.spec`).

Whether either pair of stores holds meaningful progress, and how much, cannot be told without touching the stores, which was not done.

## Recommendation

Safest next step: change nothing yet, keep the Studio memory attribute on, and do not open this build to real players until the canonical store is decided. If real players reached the game before 11 November, their progress is in the `_v1` stores and a release with the current config would start them from zero.

The decision needs one fact that the configuration cannot give: how many keys each of the four stores holds. That is a read-only key count (`ListKeysAsync`, no record contents), and it still needs explicit approval because it touches the stores.

## Reversible plan, for approval only

Nothing below has been done.

1. Count keys in the four stores, read-only, without reading record contents.
2. Decide which pair is canonical.
   - Only the `_v1` pair holds real progress: go to step 3.
   - Only the audit pair holds progress worth keeping: leave the config alone and rename nothing.
   - Both hold progress worth keeping: go to step 4 before step 3.
3. Switch back: set `ProfileStore = "GS_Profiles_v1"` and `TeamStore = "GS_Teams_v1"` in `Config.Game`, save the place, and check one account in the published test game. Rollback is restoring those two lines; the current values are in the backup folder `_MilestoneAuditBackup_20261114_M4-7_r2`. The audit stores are left untouched.
4. One-time copy from the audit pair into the `_v1` pair, only for keys that do not exist in `_v1`, with a dry run that lists what would be copied before anything is written. The source is never deleted, and DataStore versioning keeps earlier versions of any written key for 30 days.
