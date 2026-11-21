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
