- Fix 1: a counter of in-flight "save and unlock" operations per store/key; `acquire`
  waits for it (at most `Config.Data.ReleaseWaitSeconds`) before loading the same key.

  ```lua
  local releasing = {} -- [хранилище/ключ] = сколько сохранений со снятием блокировки ещё идёт
  -- in acquire(), before the load attempts:
  local id = storeName .. "/" .. key
  local waitFrom = os.clock()
  while releasing[id] and os.clock() - waitFrom < (Config.ReleaseWaitSeconds or 30) do task.wait(0.1) end
  -- in save():
  if release then releasing[id] = (releasing[id] or 0) + 1 end
  local ok, result, reason = pcall(saveInner, record, release)
  if release then releasing[id] = releasing[id] > 1 and releasing[id] - 1 or nil end
  ```

- Fix 2: memory mode only in Studio.

  ```lua
  function DataService.ShouldUseMemory(probeOk, isStudio)
      return not probeOk and isStudio == true
  end
  -- Init(): useMock = DataService.ShouldUseMemory(ok, RunService:IsStudio())
  -- on a live server a failed probe only warns; profile loads keep retrying and,
  -- if they fail, the player is removed with the existing "data_failed" message
  ```

- Fix 3: a new record is stamped with `Schema.ProfileVersion` / `Schema.TeamVersion`.
- New public `DataService:ReleaseProfile(player)` (the body of the `PlayerRemoving`
  handler, unchanged in behaviour) so the leave path can be tested.

### `ReplicatedStorage.Shared.Config.Game`

- Added `Data.ReleaseWaitSeconds = 30`.
- The data store names are unchanged from what the audit found (see limitations).

### `ServerScriptService.Server.Services.PartyService` (101 → 115 lines)

- Fix 4: `Join` returns `false, "full"` when the team already has `MaxSize - 1` guests.
  The host's own seat is always kept free, so a full team can never lock its host out.
  `PlayerService` already sends a refused player to their own team.

### `ServerScriptService.Server.Services.DevService` (415 → 421 lines)

- Fix 5: the access rule is now the pure function
  `DevService.IsAllowed(player, devConfig, isStudio)`; `isDev` calls it. Behaviour is the
  same, except that a failed or non-numeric group-rank lookup now denies access.

### New `ServerStorage.Tests.AuditData.spec` (190 lines)

Copy in this repository: `docs/audits/milestone-1/AuditData.spec.luau` (same bytes,
hash `7dd63b53`). Six tests:

1. memory mode is a Studio-only fallback;
2. dev panel access: listed accounts, group admins, Studio by setting, nobody else;
3. profile: saved on leave, loaded on rejoin, lock released, new record in the current schema;
4. session lock: a second server cannot open or overwrite a held record, a stale lock expires;
5. quick rejoin on the same server loads what was saved on leave (regression test for fix 1);
6. team record: shared inside a party of up to 4, independent between teams.

Tests 3–6 use the real DataStore, run only in a play session in "datastore" mode, use
separate `DataService` copies as "servers", write only test keys with negative ids and
delete them at the end.

### Script hashes after milestone 1

| Script | Lines | Bytes | Hash |
| --- | ---: | ---: | --- |
| ReplicatedStorage.Shared.Config.Game | 31 | 1571 | 040575e2 |
| ServerScriptService.Server.Services.DataService | 325 | 12393 | 55f579b2 |
| ServerScriptService.Server.Services.PartyService | 115 | 4419 | ddbd45ab |
| ServerScriptService.Server.Services.DevService | 421 | 18501 | 1bba9cd3 |
| ServerStorage.Tests.AuditData.spec | 190 | 8387 | 7dd63b53 |

## 4. Tests run and results

Play sessions used dedicated data stores (`GS_AuditProfiles_20261114`,
`GS_AuditTeams_20261114`) so the owner's saved test progress was never loaded or written.

| Test | Result |
| --- | --- |
| Full suite before any change (`GS_TestHook` → `run_tests`) | 92 passed, 0 failed, 9.7 s |
| Full suite after the fixes | **98 passed, 0 failed**, 43.5 s (the 4 DataStore tests take about 34 s) |
| Server start | "datastore" mode, all 16 services registered, 19 remotes, no loader warnings |
| Client start | `Loaded`, `IsDev`, `Plot` attributes set; HUD built; snapshot received |
| Request rate limit | 60 `DevCommand` calls sent in one frame over the real remote → exactly 6 handled (limit 6 per second) |
| Dev panel commands | `give_item`, `set_weather`, `growth_speed`, `wave`, `reset_profile`, `save` all succeed; 14 invalid inputs (unknown or non-text item id, zero, negative, NaN, infinite and huge counts, unknown weather, three out-of-range speeds, unknown currency, overdraft, unknown command) all refused with no state change |
| Save on demand | stored record: schema 4, values as set, lock held by the session |
| Save on leave and server stop | console: "профиль сохранён при выходе (ok)", "сохранения завершены за 1.9 с, в процессе: 0" (1.7 s in the second session); stored records unlocked |
| Progress after rejoin | session 1 set coins 123, 2 compost, hotbar slot 6, language `ru`, took the research book; session 2 loaded all of it, session counter 0 → 1, HUD in Russian |
| Autosave | with no manual save, profile and team records were rewritten 168 s after the watch started (interval 180 s), locks kept |
| Session lock, two simulated servers | second server gets "locked" and waits; after release it loads the saved value; an expired lock is taken over; the late save of the old holder returns `false` and changes nothing |
| Quick rejoin, before fix 1 | 2 of 3 rounds correct, 1 round lost the saved value |
| Quick rejoin, after fix 1 | 6 of 6 rounds correct in 12.4 s, no queue warnings; regression test passes |
| Console after the final session | no errors; one expected warning from the lock-expiry test |
| Leftover test data | none: all test keys removed and re-checked |

## 5. Remaining limitations

- **Published game not tested.** The plan's criterion names the published test game.
  Publishing is outside this task, so saving was verified in Studio play sessions
  against the test game's real DataStore. One rejoin in the published game is still
  needed to tick the criterion exactly as written.
- **Two servers were simulated** by two `DataService` instances inside one Studio
  server. They share nothing but the DataStore, but real cross-server timing is untested.
- **Data store names need an owner decision.** The config pointed at
  `GS_AuditProfiles_20261111` / `GS_AuditTeams_20261111`; the 11 November backup shows the
  earlier profile store `GS_Profiles_v1`. The names were left exactly as found. Pick the
  final names before release, because changing them switches every player to empty saves.
- **Party membership is taken from teleport data** (`partyHost`), which a modified client
  can forge. The size cap limits the damage; real validation belongs to the lobby in
  milestone 9.
- **Dev panel access** follows recorded decision 3 (listed account plus group admins)
  rather than "only your account", and `AllowInStudio = true` opens it to anyone who can
  play-test in Studio.
- **Interface location.** The plan's structure table puts the interface in `StarterGui`;
  the project builds it from client controllers into `PlayerGui` and `StarterGui` is
  empty. It works; it is a deviation in layout only and was not changed.
- **Suite duration.** The DataStore tests raise a full run from about 10 s to about 44 s.
  The bridge cuts calls at 85 s, so the suite should be started in the background and
  polled, as was done here.
- A Studio console warning "ContentId rbxassetid://203785492 … Asset type does not match
  requested type" appears on place load. No project script or scanned instance property
  references that id; it was not investigated further.