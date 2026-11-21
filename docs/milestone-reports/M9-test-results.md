# Milestone 9 — test results

Run in Roblox Studio on 2026-11-21 with one player. Data was in memory mode (`GS_ForceMemoryData = true`): no DataStore was read or written. Nothing here was run with a second real player or in the published game; the [report](M9-lobby-and-coop.md) lists what that leaves unverified.

## Game place (place id 129614341268000)

| Run | State of the place | Specs | Passed | Failed |
| --- | --- | --- | --- | --- |
| Baseline, before any change | saved as version 30 | 23 | 148 | 1 |
| With the lobby link | before `AuditCoop.spec` existed | 24 | 155 | 0 |
| With all milestone 9 work | before the final saves | 25 | 160 | 0 |
| Final | version 33 | 25 | 160 | 0 |

The baseline failure was in `AuditMonsters.spec`. Run alone, that spec then passed three times in a row, and it passed 10 of 10 in each of the three later full runs. It is an existing intermittent failure and not part of this milestone.

### Final run, per spec (version 33)

| Spec | Passed |
| --- | --- |
| `AlchemyIndex.spec` | 6 of 6 |
| `AuditAct1Boss.spec` | 7 of 7 |
| `AuditAct1Quests.spec` | 10 of 10 |
| `AuditAlchemy.spec` | 7 of 7 |
| `AuditAlchemyFlow.spec` | 4 of 4 |
| `AuditCombat.spec` | 3 of 3 |
| `AuditCombatLive.spec` | 3 of 3 |
| `AuditCoop.spec` (new) | 5 of 5 |
| `AuditData.spec` | 2 of 2 |
| `AuditEconomy.spec` | 6 of 6 |
| `AuditFarm.spec` | 5 of 5 |
| `AuditHelp.spec` | 1 of 1 |
| `AuditHousing.spec` | 4 of 4 |
| `AuditLobbyLink.spec` (new) | 6 of 6 |
| `AuditMonsters.spec` | 10 of 10 |
| `AuditProgression.spec` | 10 of 10 |
| `AuditWeatherLive.spec` | 6 of 6 |
| `AuditWorld.spec` | 4 of 4 |
| `Combat.spec` | 6 of 6 |
| `Config.spec` | 8 of 8 |
| `Data.spec` | 3 of 3 |
| `Economy.spec` | 6 of 6 |
| `Farm.spec` | 12 of 12 |
| `Formulas.spec` | 21 of 21 |
| `WeatherDefense.spec` | 5 of 5 |
| **Total** | **160 of 160** |

### The new tests

`AuditLobbyLink.spec`:

1. M9 config: the lobby place is set, the new events and texts exist in both languages
2. M9 rules: who is sent to the lobby and where the tickets are kept
3. M9 arrival: the host and the format come from the ticket the server reads, never from TeleportData
4. M9 lobby and back: a player without a ticket is sent to the lobby and stays if that fails; the way back uses the lobby place
5. M9 report to the lobby: free houses, the players here and the members who may come back
6. M9 seats: on a server from the lobby a team is not bigger than a house of the format holds

`AuditCoop.spec`:

1. M9 co-op numbers: the idle times of the design document; every blocked or decorative item exists
2. M9 idle check: the window after 15 minutes without input, 30 seconds to answer, then the player is removed
3. M9 decoration: a member of the team puts a decoration up at its house and takes it back; it is in the team record
4. M9 trade: both players confirm, then one operation moves the items; nothing is lost or doubled
5. M9 trade: a trade that is declined, late, cancelled or cannot be completed leaves both bags as they were

In these specs the other players are stand-ins (tables), the teleport is a recorder, the server list is a table, and time is passed in rather than waited for. Test 6 of the first spec and tests 4 and 5 of the second run only in memory mode.

## Lobby (place id 106448766989936)

`Lobby.spec`: 9 passed, 0 failed, in each of three runs. The last run was on saved version 6.

1. M9 config: the four party formats of the plan, two places and every lobby text in en and ru
2. M9 server list: houses are held and released, a full server is skipped, entries and tickets expire
3. M9 store: Studio keeps the server list in memory unless asked otherwise, live servers use MemoryStore
4. M9 party: everyone starts alone as a leader; invite, accept, decline, expiry, a full party, kick and leave
5. M9 set out: only a full party leaves; it gets a server of its format, a house and a ticket for every member
6. M9 matching: parties of one format fill a server house by house, other formats and full servers get new ones
7. M9 failure: when the server or the teleport is refused, the party stays in the lobby and its house is free again
8. M9 return: a player whose team is still on a game server is offered the way back and gets a ticket to it
9. M9 live: the player in this session has a solo party and sees the others in the lobby

## One-player runs across the two places

A Studio play session follows a teleport into the last saved version of the target place. These used that, with one client.

**Lobby to game, with the ticket in MemoryStore.** Both places were switched to MemoryStore for this run (`GS_LobbyStore = "memorystore"`; the switch was removed afterwards and is not in the final versions). The lobby's `MatchService:Launch` sent the one player as format `duo`; the party-size rule was bypassed on purpose so that the result would differ from the solo default. Server log, with the account id removed:

```
[Match] server list: memorystore
[Match] party of 1 (host <user id>, duo) sent to server studio
[LobbyLink] server studio: format duo from the lobby
[House] раскладка duo: домов 10, мест в доме 2
```

On the game server the session then had 10 plots, one of them owned by the player. A three-test probe on that server passed 3 of 3:

- arrival source `ticket`, format `duo`, host the player, seat limit 2, a team record loaded;
- the ticket was gone after use (a second read gave "none");
- the server's entry in the lobby list had 10 houses, 9 free, 1 player and no held houses, the search the lobby uses found it, and the player had no return session.

In Studio a reserved server has no id of its own, so both sides used the fixed id `studio`.

**Game to lobby.** The "Return to the lobby" action was fired on that game server. Server log:

```
[Data] <player>: профиль сохранён при выходе (ok)
[House] дом Plot_01 свободен
```

The session then reported the lobby's place id with one player. The lobby's saved version at that moment was still the empty version 5, so the lobby's own scripts did not run on that arrival.

**Idle window on the real client.** With the player's last input back-dated on the server, the server's own loop showed the window: title "Don't sleep!", a countdown, the button "I'm awake". The awake action was sent through its remote, not by a click; afterwards the server no longer had the player marked as prompted and the player was still on the server.

**Before the ticket change.** A solo party set out from the lobby panel and arrived in the game place, and the panel refused an incomplete party. That run predates the tickets and says nothing about them.
