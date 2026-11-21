
### Rarer grows longer

Three beds side by side at ×10 speed, day, clear weather:

| Species (rarity) | Measured per second | Expected per second |
| --- | ---: | ---: |
| Sun Honey Fungus (uncommon) | 0.06776 | 0.06667 |
| Void Galactic (mythic) | 0.00282 | 0.00278 |
| Red Fly Agaric (common), on a bed worn by six harvests | 0.08412 | 0.13889 × bed factor 0.60 = 0.083 |

### Bed state without numbers

Every preset produced its own geometry on the live bed and nothing with digits:
cracks 11 / 23 parts, mould 20 / 70 parts plus mould on the crop itself (8 / 25 parts),
flies 4 / 15, stars 4 / 9 (weak / strong). Back to normal removes all signs.

### Mutations

- All eight factors of the plan are in `Mutation.Factors` and each one changes the
  chance (`Farm.spec`); soil quality and nutrition are two extra factors.
- Dev panel simulation, 20 000 plantings on the current bed: 5.11 % observed against
  5.17 % from the config (difference under one standard deviation).

### Growth and harvest survive leaving

| Check | Result |
| --- | --- |
| Leave and return on the same server, 4.5 s away | team record unloaded while away; progress of three beds identical to 4 decimals before and after; growth resumed afterwards |
| Stop the server, wait 96 s, start again | bed 3 stored at 0.06691, loaded at 0.06831 after 6.4 s of server uptime; growth while away would have added 0.0267 — it did not, as decision 4 requires |
| Ready crops and bed visuals after restart | restored from the save (ready flag, species, crop model) |
| Harvest saved | six harvested mushrooms were in the stored profile and in the inventory of the next session |

## 3. Issues found

No defect was found in `FarmService`, the growth, mutation, day/night and bed-look
formulas or the configs. Two server rules had no automated test:

1. using a bed on another team's plot;
2. the tools needed to harvest (sickle in hand, basket in the bag) and a full bag.

All of them behave correctly; the tests were missing.

## 4. Changes made

### `ServerStorage.Tests.AuditFarm.spec` (48 → 89 lines)

The three existing tests are untouched. Two tests were appended; the added block is in
this repository as `docs/audits/milestone-3/AuditFarm.spec.additions.luau` (same bytes,
hash `21e6c232`):

- "a bed on another plot cannot be used and nothing is consumed";
- "harvest needs a sickle in hand and a basket in the bag; a full bag keeps the crop on
  the bed" (then one slot is freed and the harvest succeeds).

Both run inside the existing fixture, which restores the profile, the team record and
the character position afterwards.

### Script hashes at the end of the audit

| Script | Lines | Bytes | Hash |
| --- | ---: | ---: | --- |
| ReplicatedStorage.Shared.Config.Game | 31 | 1571 | 040575e2 |
| ServerScriptService.Server.Services.DataService | 325 | 12393 | 55f579b2 |
| ServerScriptService.Server.Services.PartyService | 115 | 4419 | ddbd45ab |
| ServerScriptService.Server.Services.DevService | 421 | 18501 | 1bba9cd3 |
| ServerStorage.Tests.AuditData.spec (new) | 190 | 8387 | 7dd63b53 |
| ServerStorage.Tests.AuditHousing.spec | 80 | 3295 | 433f8694 |
| ServerStorage.Tests.AuditFarm.spec | 89 | 5223 | 3d1696ee |

Every other script still matches `backup-manifest-2026-11-14.md`.

## 5. Tests run and results

| Test | Result |
| --- | --- |
| Full suite after the change | **101 passed, 0 failed**, 42.4 s; inventory identical before and after the run |
| `Farm.spec` (cycle, Moon, conditions, save round trip, bed look, mutation factors, two simulations, bed stats, crop mould) | all pass |
| `AuditFarm.spec` (5 tests, 2 new) | all pass |
| Live checks in section 2 | all as expected |
| Console of every session | no errors; no farm or loader warnings |

## 6. Remaining limitations

- **Published game not tested**, as for milestone 1: everything ran in Studio play
  sessions against the test game's real DataStore.
- **Health and infection do not change inside milestone 3.** Harvesting wears soil and
  nutrition and compost restores them, but cracks and mould appear only through the dev
  panel presets or the later systems (monsters, lightning). The signs themselves work.
- "Infection of the territory" from the plan is modelled as the infection of the bed.
- The status board above a planted bed shows growth as a percentage. The four bed
  parameters have no numbers or bars, which is what the plan asks; the percentage is
  extra information about the crop.
- The three growth stages are one model scaled to 35 %, 65 % and 100 % of its height,
  not three separate models (asset pipeline, page 7). Fine for blanks; revisit with the
  final art in milestone 10.
- With one-hour days and nights a night-only or day-only mushroom can wait up to about
  61 minutes before it starts growing. This follows the recorded decision on the cycle.
- A new player owns three fly agaric spores; spores of the other species were given
  through the dev panel for these checks. Their normal sources belong to later milestones.
- A bed harvested six times without compost grew at about 60 % speed. This is how
  `Config.Farm.BedEffects` is set; worth a look when balancing.
- One player in Studio: co-op farming on a shared plot was not exercised with real players.

## 7. State of the project at the end of the audit

- Place saved to Roblox as **version 16** (rollback points: version 14 before the audit,
  version 15 after milestone 1). Nothing was published and no asset was uploaded.
- The in-place script backup `ServerStorage._MilestoneAuditBackup_20261114` was left in
  the place; it can be deleted once the changes are accepted.
- The audit's own save data (stores `GS_AuditProfiles_20261114` and
  `GS_AuditTeams_20261114`, plus the test keys with negative ids) was removed.
- `Config.Game.Data` store names are exactly as found: `GS_AuditProfiles_20261111` and
  `GS_AuditTeams_20261111`. A final start on these stores loaded the existing profile
  and saved it on exit without errors.
- **Decision needed on the data stores.** The 11 November backup of the config names
  `GS_Profiles_v1` and `GS_Teams_v1`. Both still hold the Studio account's record,
  created on 8 November and last written on 11 November, the day the config was switched
  to the audit stores. Everything played since then is in the audit stores, whose profile
  also carries test entries from that audit. Decide which pair is the real one before
  release; switching back makes the 8–11 November progress reappear and hides the
  progress made since.