# Milestone 9 — Lobby and co-op

**Status: built and tested in Studio with one player; not complete.** Both places are saved, not published: lobby version 6, game place version 33. Nothing in this milestone has been run with two real players or in the published game, and the plan itself puts those checks in the published test game (items 2 and 8). Several numbers and rules below are drafts that wait for your decision.

The two places, confirmed by place id before any edit:

| Role | Name in Studio | Place id |
| --- | --- | --- |
| Lobby | `Z1raelRam's Place: 11142026_1` | `106448766989936` |
| Game | `GUARDIAN TEST` | `129614341268000` |

## Baseline and safety

- Game place: backup `ServerStorage._MilestoneAuditBackup_20261121_M9` (96 scripts); rollback save: cloud version 30.
- Lobby: rollback save: cloud version 5 (the empty place, no scripts).
- Baseline of the game place: 23 specs, 148 passed, 1 failed. The failure was in `AuditMonsters.spec` and did not repeat in three more runs of that spec.
- All tests used `GS_ForceMemoryData = true`; no DataStore was read or written. The data schema and versions are unchanged.
- Not published, start place not changed (and not looked up), no assets uploaded.
- Game place version 31 is a throwaway save: it carried a test switch (`GS_LobbyStore`) for the Studio run described below. Version 32 is the same without it, and is the version every test above ran on. Version 33 rewords one comment in `TradeService`; no code changed.

## Decisions followed

- **Decision 2, variant A:** a lobby and one game place; the lobby keeps a list of game servers per party format. Formats and houses are the recorded ones: solo 20 houses, duo 10, trio 6, quartet 5.
- **Decision 5:** personal progress stays in the player's profile, shared progress in the team record of the host. Nothing in the data layout changed; house decorations went into the team record.
- **Decision 6:** English by default, Russian in the settings. Every new text exists in both.
- **Design doc 2.5:** idle check after 15 minutes, 30 seconds to answer.
- **Design doc 6.7:** reward bonus ×1 / ×1.1 / ×1.25 / ×1.5. It was already applied by `Rewards` before this milestone; the test only pins the numbers.

## Built

### Lobby place (all new: 17 scripts, 74,137 bytes, and a blockout of 87 parts)

- **Blockout** (`LobbyBuilder`): a glade with a plaza, a big mushroom, lanterns, eight spawn points. Blocks only.
- **Party** (`LobbyPartyService`, `LobbyController`): everyone arrives as a leader of a party of one. Invite, accept, decline, invitation expiry, kick, leave. When the leader leaves, the party is disbanded and every member is alone again. The leader picks the format; the panel shows the members and the format.
- **Setting out** (`MatchService`): only a party whose size equals its format leaves. The lobby looks for a server of that format with a free house, fullest first, and holds the house with one atomic update; if there is none it reserves a new server. Every member gets a ticket, then the party is teleported. If the server or the teleport is refused, the party stays, is told so, and the held house is released.
- **Way back:** a player whose team is still on a game server is offered a return to it on entering the lobby.
- **Shared with the game place:** `Matchmaking` (byte-identical in both places: 9,186 bytes, Adler-32 2281506119), party formats and place ids.

### Game place (9 new scripts and 2 new specs; 6 scripts edited, 60 lines added, 24 removed)

- **Tickets instead of TeleportData** (`LobbyLinkService`, `PartyService`, `PlayerService`): the server reads the arriving player's ticket from the store itself and takes the host and the format from it. TeleportData passes through the client and can be forged, so it is no longer trusted for either. A ticket is valid for one server and is used once. The first ticket sets the server's format and house layout.
- **No ticket:** outside Studio, on a server the lobby did not reserve, the player is sent to the lobby (design doc 1.3). If that fails, the player plays where they are, as before.
- **Report to the lobby:** every 30 seconds, and whenever a house is taken, the server reports its houses, free houses and players, and marks which absent members may come back.
- **Seats:** on a server from the lobby a team cannot be bigger than a house of that format holds.
- **Return to the lobby:** a button in the settings panel.
- **Idle check** (`AfkService`, `CoopController`): the server counts the time; the client only reports that there was input. Window "Don't sleep!" with the button "I'm awake" and a countdown.
- **Trade** (`TradeService`, `TradeController`): ask a Guardian nearby, both put items in, both confirm, one server step moves everything. Any change to an offer withdraws both confirmations. A player is in one trade at a time. If a move fails halfway, both bags are put back as they were.
- **House decoration** (`DecorService`): four spots in front of the house; a team member puts a cosmetic item up or takes it down; the item returns to the bag of whoever takes it down.
- **Call for help** (`DefenseService`): game servers are now reserved, so a helper needs the server's access code. The code stays on the servers and is not sent to clients; the helper is recognised by a ticket.

The other parts of plan item 4 (shared garden, shared defence, the team raid, shared recipes) were built in earlier milestones on the team record. This milestone did not change them and did not check them with more than one player.

## Tests

| Where | Result |
| --- | --- |
| Lobby, `Lobby.spec` | 9 passed, 0 failed (three runs, the last one on saved version 6) |
| Game place, all 25 specs | 160 passed, 0 failed (before the last spec was added: 24 specs, 155 passed, 0 failed) |
| of which `AuditLobbyLink.spec` (new) | 6 passed |
| of which `AuditCoop.spec` (new) | 5 passed, run twice in one session |

What the new game-place specs cover:

- `AuditLobbyLink.spec`: place ids and texts in both languages; who is redirected; host and format come from the ticket and never from TeleportData; a wrong-server or missing ticket means a direct arrival; the report to the lobby; seat limits.
- `AuditCoop.spec`: the idle window appears at 15 minutes, input before it restarts the count, input while it is open does not close it, the button does, 30 seconds without an answer removes the player. A completed trade leaves the totals of both items unchanged (`5 0 | 0 3` → `3 1 | 2 2`); a declined, late, cancelled, short or half-failed trade changes neither bag; a second confirmation of a finished trade does nothing. A decoration leaves the bag, stands at its spot, is in the team record, and comes back.

Other players in these specs are stand-ins (tables), and time is passed in rather than waited for.

### One-player runs through both places in Studio

A Studio play session follows a teleport into the last saved version of the target place, so these ran across the two places, with one client:

1. **Lobby → game with a ticket in MemoryStore.** With the store switched to MemoryStore in both places, the lobby's own `MatchService:Launch` sent the one player as format `duo`. The party rule was bypassed on purpose for this run, so that the result differs from the solo default. The game server logged `[LobbyLink] server studio: format duo from the lobby` and `[House] раскладка duo: домов 10, мест в доме 2`. A probe on that server passed 3 of 3: arrival source `ticket`, format `duo`, seat limit 2; the ticket was gone after use; the server's entry in the lobby list showed 10 houses, 9 free, 1 player, no held houses, and the search the lobby uses found it.
2. **Game → lobby.** The "Return to the lobby" action saved the player, freed the house and arrived in the lobby place.
3. **Idle window on the real client.** With the player's last input back-dated, the server's own loop showed the window ("Don't sleep!", countdown, "I'm awake"); the awake action was accepted and the player stayed.
4. Earlier in the milestone, before the ticket change: a solo party set out from the lobby panel and arrived in the game place; the panel refused an incomplete party.

This is not a multiplayer test and not a test of the published game. In Studio a reserved server has no id of its own, so both sides used the fixed id `studio`.

## Decisions needed

None of these is recorded in the plans. Each is a draft I had to pick to make the feature work.

1. **Who may trade with whom.** Draft: any two Guardians on the server within 24 studs, not only team-mates.
2. **What cannot be traded.** Draft: the research book, the basket and the simple sickle. Coins and dust cannot be traded at all.
3. **Trade limits.** Draft: 8 different items per side, 20 seconds to answer a request.
4. **Decoration spots and items.** Draft: four fixed spots in front of the house; the only item is the existing `lantern_banner`. Any team member can take down what another put up and keeps it.
5. **A party smaller than its format.** Draft: it cannot set out, and the lobby never fills a party with strangers. I read design doc 2.2 as "the format is the size of the party"; say so if a duo may leave with one player.
6. **The leader leaves the party in the lobby.** Draft: the party is disbanded; leadership does not pass on.
7. **A player who opens the game place directly.** Draft: sent to the lobby; after 20 seconds without a teleport they play where they are.
8. **Coming back.** Draft: a member who dropped out, or was removed for being idle, can return to the team from the lobby while the team is still on its server.
9. **Lobby numbers.** Draft: invitation 30 s, 6 open invitations per leader, 3 teleport attempts, a party is locked for 45 s after setting out.
10. **The start place of the experience.** Not changed and not looked up. Design doc 1.3 says the game starts with the lobby; with draft 7 above either start place ends in the lobby, but only one of them does it without an extra teleport.
11. **Lobby and trade interface.** The plan lists Figma for item 1. There are no layouts; both interfaces are temporary.

## Not verified, and what it would take

- **Two or more real players.** Inviting between real clients, a party of 2–4 arriving on one server in one house with one team record, the trade window between two clients, decoration by two team-mates, seat limits with real players. Needs several clients; all of it ran only with stand-ins.
- **The published game.** Real reserved servers and access codes, teleports between places, the redirect of a direct join (it never happens in Studio), several servers in the list, servers filling house by house, entries expiring in real time, retry after a teleport that did not start.
- **Call for help between reserved servers.** The access-code path and the helper ticket have code and a unit test, and no run between two servers.
- **The idle check in real time.** Nobody waited 15 minutes, and no real player was removed; the window's button was not clicked by hand (its remote was fired instead).
- **Distance checks.** Trade (24 studs) and decoration (16 studs) were tested with the distance check switched off.
- **Saving a trade to a real DataStore.** The two bags are two saved records. They change together in memory and are then written by two separate saves started at the same moment; a crash between the two writes was not tested and cannot be ruled out.
- **Real DataStore in general, phone layout and touch, more than one desktop size.**
- **The look.** Blocks in the lobby, temporary interface.

## Exact next tests

These need both places published to the test experience, which this task must not do.

1. One player: enter the lobby, set out as solo, arrive in a house. Server log of the game place should show `[LobbyLink] server <id>: format solo from the lobby`.
2. One player: open the game place directly. Expected: sent to the lobby.
3. Two players: invite, accept, choose duo, set out. Expected: one server, one house, one team; what one plants the other sees.
4. A second duo sets out. Expected: the same server, another house.
5. Three and four players: trio and quartet the same way; a fifth invitation is refused.
6. Trade between two players: complete one, cancel one, walk away during one. Count the items before and after.
7. Leave a team-mate on the server, drop out, re-enter the lobby. Expected: the offer to return, and the same house.
8. Stay idle 15 minutes. Expected: the window; without an answer, removal after 30 seconds.
9. Call for help answered from another server.
10. One run with `GS_ForceMemoryData` removed, to check saves, including a trade.

## Blocked and incomplete

| What | Blocked by | What remains |
| --- | --- | --- |
| Plan item 2, check in the published game | Publishing | Tests 1–5 above |
| Plan item 8, playtest of four | You and three players | — |
| Trade and decoration rules | Decisions 1–4 | Change `Config.Coop` |
| Lobby rules | Decisions 5–9 | Change `Config.Coop` / `Config.Lobby`; 5 and 6 are in `LobbyPartyService` |
| Final lobby and its interface | Layouts (milestone 10) | Replace the blockout and the temporary panels |
| Closing the milestone | The tests above and your approval of the drafts | — |

## Code in the repository

The places are the source of truth; the game is not built from the repository. Each copy below was checked against Studio by length and Adler-32 checksum after the final saves, and all match.

- **Game place, new:** the nine scripts and two specs are under `studio-src/`, at their Studio paths (81,256 bytes): `Config/Coop`, `Locale/CoopStrings`, `Modules/Matchmaking`, `Services/AfkService`, `Services/DecorService`, `Services/LobbyLinkService`, `Services/TradeService`, `Controllers/CoopController`, `Controllers/TradeController`, `Tests/AuditLobbyLink.spec`, `Tests/AuditCoop.spec`.
- **Game place, edited:** `studio-src/changes-m9.diff` records every line changed in the six edited scripts, compared with the backup above (7,568 bytes, Adler-32 2462143991). They are `Config.Game`, `Modules.Locale`, `Modules.Net`, `DefenseService`, `PartyService` and `PlayerService`.
- **Lobby:** all 17 scripts are under `studio-src/lobby-place/` (74,137 bytes). The built blockout model is in the place only; `LobbyBuilder` rebuilds it.
