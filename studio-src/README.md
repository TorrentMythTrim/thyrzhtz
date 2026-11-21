# studio-src

Copies of the scripts written during the milestone 4–7 audit of the Roblox Studio place "GUARDIAN TEST", and a record of every line changed in the scripts that were already there.

The place itself is the source of truth: the game is not built from this folder.

## New scripts

Each `.luau` file mirrors one script in Studio, with the Studio path as the folder path and `.luau` added to the name. At the time of each commit the file was byte-identical to the script in Studio (same length and checksum).

## Edited scripts

Scripts that already existed and were only edited are not copied here. Their changes are in `changes-since-backup.diff`: for each of the 19 edited scripts, the lines removed (`-`) and added (`+`) compared with the copy in `ServerStorage._MilestoneAuditBackup_20261114_M4-7_r2`, which was taken in Studio before the first change of this audit. `@@ -a +b @@` gives the line number in the backup copy and in the current script. Indentation is tabs, as in Studio.

The diff was computed in Studio after the milestone 7 changes (place version 22) and covers the whole audit: milestone 4 changed no existing script, so the lines belong to milestones 5, 6 and 7 — 314 added, 46 removed. The file here is byte-identical to that output (27,170 bytes, Adler-32 3241104382). The milestone reports under `docs/milestone-reports/` say which change belongs to which milestone and why.

It is a record for reading and review, not a patch that `git apply` understands.

## Milestone 8

The Act 1 scripts are copied the same way: eight new scripts, plus `MonsterBehaviors`, which already had a copy here and gained 14 lines. All were byte-identical to Studio at place version 26.

The five existing scripts edited for milestone 8 are in `changes-m8.diff`, in the same format, compared with `ServerStorage._MilestoneAuditBackup_20261114_M8`: 38 lines added, none removed. `changes-since-backup.diff` is unchanged and still ends at milestone 7.

## Milestone 9

The game-place scripts are copied the same way: nine new scripts and two new specs (`AuditLobbyLink.spec`, `AuditCoop.spec`), 81,256 bytes in all. All were byte-identical to Studio at game place version 33.

The six existing scripts edited for milestone 9 are in `changes-m9.diff`, in the same format, compared with `ServerStorage._MilestoneAuditBackup_20261121_M9`: 60 lines added, 24 removed (7,568 bytes, Adler-32 2462143991). The earlier diff files are unchanged.

The lobby is a second place of the same experience (`Z1raelRam's Place: 11142026_1`, place id 106448766989936). It had no scripts before milestone 9, so all 17 of its scripts are copied under `lobby-place/`, with the Studio path as the folder path: 74,137 bytes, byte-identical to Studio at lobby version 6. `Matchmaking` is the same file in both places, and the lobby's `TestRunner` is a copy of the one in the game place. The blockout of the lobby is built by `LobbyBuilder`; the built model is saved in the place and is not copied here.

Five of the six edited scripts are also copied in full for milestone 9, as they stood at game place version 33: `Modules/Locale`, `Modules/Net`, `Services/DefenseService`, `Services/PartyService` and `Services/PlayerService` (51,688 bytes, byte-identical to Studio). They are the whole scripts, so they contain the edits of milestones 5 to 8 as well. `Config.Game` is not copied: it lists the account and group ids that open the developer panel, which are kept out of this public repository. Its two changed lines are in `changes-m9.diff`.
