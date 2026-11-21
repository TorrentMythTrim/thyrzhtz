# Milestone 6 — Weather and Defense: audit report

Date: 2026-11-14. Plan reference: technical plan, milestone 6 (design document steps 5.1–5.4).
Project: Roblox Studio place "GUARDIAN TEST", audited and edited through Studio MCP. All play-mode checks ran with `GS_ForceMemoryData = true`, so no DataStore was read or written. The place was saved as cloud version 21 after the changes (saved, not published).

**Status: not marked as passed — one "done when" criterion is blocked.** Every requirement that can be checked in Studio is met and tested. The third criterion, "the call for help reaches a player on another server", cannot be verified in Studio: it needs two live servers of the published test game, and this task must not publish. The code path exists and was read; it has not been run.

## Requirements against the project

| # | Plan requirement | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Seven weathers, one weather for the whole server, Eclipse not included | Met | `Config.Weather` (clear, rain, thunderstorm, fog, spore rain, snow, Blood Moon), `WeatherService` keeps one state and publishes it as an attribute of ReplicatedStorage, changes every 240–480 s. Tests: AuditWeatherLive "weather is one shared state cycling through the seven plan types…", AuditWorld "all seven weather states replicate…". Client check below. |
| 2 | Weather and farm: sunny bonus, water species faster in rain, snow slows ordinary plants and speeds Ice ×1.2, lightning can strike a bed and open storm mutations | Met | Tests: WeatherDefense "weather & farm: light x1.2 in clear, water x1.25 in rain, snow slows regular x0.85 and speeds ice x1.2", "storm mutation…", "live weather & defense: … lightning storm charge & shielded bed". |
| 3 | Weather and world: slugs in rain; shorter view, hidden trails and ghost enemies in fog; infected creatures stronger in spore rain; stronger monsters and special dungeons under a Blood Moon | Met after a fix, with one simplification | Rain spawns two Mold Slugs. Fog thickens the atmosphere on the client, lays a glowing trail to a chest and, **after this run's fix**, brings two Mist Doubles. Spore rain and Blood Moon raise monster damage ×1.3; spore rain drops rare spore pods. Blood Moon opens a crypt altar guarded by a Moon Reaper that gives rare spores and a mutation book — a single altar stands in for "special dungeons". Tests: AuditWeatherLive "weather changes a real fight…", "fog brings ghost enemies and a hidden trail…"; AuditWorld "… rain mobs, fog chest, Blood Moon altar appear…". |
| 4 | Waves on the village in spore rain, fog, thunderstorm, snow or Blood Moon with some chance; a warning that leaves time to prepare; difficulty follows party size | Met | `waveChance` is above zero for exactly those five weathers; `DefenseService:StartWave` notifies the team and waits `PrepSeconds = 30`; 5, 7, 9 and 11 monsters for 1–4 players, plus an elite for 3–4 players or a Blood Moon. Tests: AuditWeatherLive "waves come only with the five dangerous weathers, are announced before they arrive and scale with the party", AuditWorld "solo wave prepares, spawns configured attackers, rejects duplicate start, completes after all attackers die". |
| 5 | Preparation: mushroom turrets, gate, mushroom traps, weather totem whose matching rune returns the multipliers to ×1 and whose wrong rune works against the player | Met | Four turrets, two traps, gate with 250 HP, totem with five runes. Tests: WeatherDefense "weather totem (step 5.3 DD): matched rune resets to x1.0, wrong rune penalizes…", "live weather & defense: gate toggle, totem rune state…", "defense grades, turrets, traps & rewards config…". Live check below. |
| 6 | Call for help: players on the same server see it; if nobody can help it goes to another server | Implemented; only partly verifiable | `DefenseService:CallForHelp` alerts every player of another team on the server and publishes through MessagingService only when nobody local was notified; `RespondHelp` moves a local helper to the defender's gate or teleports a remote one to the defender's server; `PlayerService` places a helper who arrives by teleport. Tests: AuditHelp "help escalates only if zero local recipients exist", AuditWeatherLive "help call: refused without a wave, an unknown alert counts as expired, an arriving helper lands at the defender's gate". |
| 7 | Rewards for defense, connected after the owner's decision | Implemented | `Config.Defense.Rewards`, marked "approved for milestone 6": three grades, weather danger factor, trophies, 75% and one crystal for a helper. Test: WeatherDefense "defense grades… rewards config". The approval itself is taken from the config comment. |

"Done when":

| Criterion | Result |
| --- | --- |
| Weather changes and visibly affects farm and combat | Met. Tests above; on the client the atmosphere density went 0.36 (clear) → 0.62 (fog) → 0.38 (snow) → 0.44 (Blood Moon) as the server changed the weather. |
| A wave arrives with a warning and can be beaten solo | Met for an ordinary wave. A scripted solo player holding only the starter sickle — no block, potion, turret, trap or totem — cleared a clear-weather solo wave in 11 s with 25 of 100 HP left. The same script died in 6 s to a Blood Moon wave (six monsters including the Moon Reaper, damage ×1.3); whether a prepared starter player beats that one was not tested. |
| The call for help reaches a player on another server | **Blocked.** Needs two servers of the published test game. |

## Findings and fixes

1. **Fog had no ghost enemies.** The plan lists them for fog; the project spawned only the trail and the chest. Fixed: fog now brings Mist Doubles (two by default) that stand along the hidden trail. The number and the type are one line in `Config.Weather` (`fog.ghosts`); `count = 0` turns them off. This uses a type outside the approved Act 1 spawn list, on purpose: it is a weather event, like the Blood Moon's Moon Reaper.
2. **Weather monsters piled up.** Monsters spawned by a weather were never removed, and setting the same weather again spawned them again, so every rain added two more slugs to the ones nobody had killed. Fixed: when the weather is set, monsters of the previous weather that nobody is fighting are removed. One that a player has engaged stays until the fight ends.
3. **The Blood Moon's Moon Reaper vanished by day.** The reaper leaves when it is not night, and weather is rolled independently of the time of day, so a daytime Blood Moon lost both its altar guard and the elite of its wave on the first AI step unless a player had already hit them. Fixed: under a Blood Moon the reaper stays regardless of the time of day and leaves when the weather turns.

Observations left unchanged:

- "Special dungeons" under a Blood Moon are one altar with a guard, not an instanced dungeon.
- The help call is limited to 3 per session (`FreeCallsPerSession`); the plan names the number of calls as a monetisation point for milestone 11.
- The wave elite and the wave pool use only Act 1 types.

## Changes in this run

| Script | Edit |
| --- | --- |
| `ServerScriptService.Server.Services.WeatherService` | `Set` removes unengaged monsters of zone "weather" before spawning the new weather's features; the fog branch spawns the configured ghosts. |
| `ReplicatedStorage.Shared.Config.Weather` | `fog.ghosts = {id = "mist_double", count = 2}`. |
| `ServerScriptService.Server.Services.MonsterService` | The night-only check lets the Moon Reaper stay while the weather is Blood Moon. |
| `ServerStorage.Tests.AuditMonsters.spec` | The Moon Reaper expectation allows for a Blood Moon (source updated in `studio-src/`). |
| `ServerStorage.Tests.AuditWeatherLive.spec` | New, 6 tests. Source: `studio-src/ServerStorage/Tests/AuditWeatherLive.spec.luau`. |

## Tests and results

Play mode, memory data mode, every spec in `ServerStorage.Tests` run exactly once after the last change.

| Spec | Passed | Failed |
| --- | --- | --- |
| AuditWeatherLive.spec (new) | 6 | 0 |
| WeatherDefense.spec | 5 | 0 |
| AuditWorld.spec | 4 | 0 |
| AuditHelp.spec | 1 | 0 |
| The other 16 specs (milestones 1–5, 7, shared) | 106 | 0 |
| Total, 20 specs | 122 | 0 |

Live checks in the same build:

- Preparation: during the 30-second warning a Thunder Turret was placed (one Thunder Hedgehog consumed) and a Spore Mine was set. When the wave arrived the turret hit a monster standing 6 studs away four times in 6 simulated seconds (72 damage), the mine went off under it (59 damage and poison), and the turret was removed when the wave ended.
- Solo wave fights by the scripted player, as described under "Done when".
- Client: weather attribute and atmosphere followed the server through fog, snow, Blood Moon and thunderstorm and back to clear.

## Not verified, and what it would take

- **Help call across servers** (third "done when" criterion): publish the build to the test game, start a wave on one server with nobody else on it, call for help, and accept the alert from a second server. Not done because this task must not publish.
- **Help call on the same server**: needs a second player in the session. The alert and the local teleport were read in code; the teleport to the gate was run with the single test player.
- **Blood Moon wave solo** with block, potions, turrets or the matching totem rune.
- **How fog and the other weathers look.** The atmosphere numbers changed on the client; nobody looked at the screen.
