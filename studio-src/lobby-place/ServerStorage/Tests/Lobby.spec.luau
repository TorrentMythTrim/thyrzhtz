-- Milestone 9: parties in the lobby, the server list by party format and the way to the game
-- (technical plan, milestone 9, items 1-2; design doc 2.1, 2.2; decision 2).
-- Runs in a play session (ctx.live). Other players are stand-ins (tables), the two calls that leave the server are
-- replaced by a recorder and the server list is a table, so nothing is teleported and no store is touched.
return function(it, expect, ctx)
	local PartyCfg = require(ctx.shared.Config.Party)
	local GameCfg = require(ctx.shared.Config.Game)
	local LobbyCfg = require(ctx.shared.Config.Lobby)
	local Strings = require(ctx.shared.Locale.LobbyStrings)
	local Matchmaking = require(ctx.shared.Modules.Matchmaking)

	it("M9 config: the four party formats of the plan, two places and every lobby text in en and ru", function()
		local want = {{"solo", 1, 20}, {"duo", 2, 10}, {"trio", 3, 6}, {"quartet", 4, 5}}
		expect(#PartyCfg.Formats).toBe(#want)
		for i, w in ipairs(want) do
			local f = PartyCfg.Formats[i]
			expect(f.id).toBe(w[1])
			expect(f.size).toBe(w[2])
			expect(f.houses).toBe(w[3])
			-- one party per house, so a full server never holds more than the server limit (a trio server holds 18)
			expect(f.size * f.houses <= PartyCfg.ServerPlayers).toBeTruthy()
			expect(Matchmaking.FormatBySize(PartyCfg.Formats, w[2]).id).toBe(w[1])
			expect(type(Strings.en["format_" .. f.id])).toBe("string")
		end
		expect(PartyCfg.MaxSize).toBe(4)
		expect(GameCfg.Places.Lobby > 0 and GameCfg.Places.Game > 0 and GameCfg.Places.Lobby ~= GameCfg.Places.Game).toBeTruthy()
		for key in pairs(Strings.en) do expect(type(Strings.ru[key])).toBe("string") end
		for key in pairs(Strings.ru) do expect(type(Strings.en[key])).toBe("string") end
	end)

	it("M9 server list: houses are held and released, a full server is skipped, entries and tickets expire", function()
		local saved = {Matchmaking.Backend(), Matchmaking.Now}
		local t = 5000
		Matchmaking.Now = function() return t end
		Matchmaking.UseBackend(Matchmaking.LocalBackend())
		local ok, err = pcall(function()
			expect(#Matchmaking.FindOpen("trio")).toBe(0)
			local entry = Matchmaking.Register("trio", "A", "codeA", 6, 1)
			expect(Matchmaking.OpenHouses(entry)).toBe(5)
			for host = 2, 6 do expect(Matchmaking.Claim("trio", "A", host) ~= nil).toBeTruthy() end
			expect(Matchmaking.Claim("trio", "A", 7)).toBe(nil) -- six houses, six parties
			expect(Matchmaking.Claim("trio", "A", 3) ~= nil).toBeTruthy() -- the same party again keeps its house
			expect(#Matchmaking.FindOpen("trio")).toBe(0)
			Matchmaking.Release("trio", "A", 6)
			expect(Matchmaking.FindOpen("trio")[1].open).toBe(1)
			expect(#Matchmaking.FindOpen("duo")).toBe(0) -- another format has its own servers
			-- the game server reports: two parties arrived, their houses are taken and their claims end
			local after = Matchmaking.Heartbeat("trio", "A", "codeA", 6, 4, 6, {1, 2})
			expect(after.free).toBe(4)
			expect(Matchmaking.OpenHouses(after)).toBe(1) -- 4 free, 3 still on their way
			-- fuller servers come first
			Matchmaking.Register("trio", "B", "codeB", 6)
			local open = Matchmaking.FindOpen("trio")
			expect(open[1].id).toBe("A")
			expect(open[2].id).toBe("B")
			-- a claim that nobody used ends by itself
			t += Matchmaking.Ttl.Claim + 1
			expect(#Matchmaking.FindOpen("trio")).toBe(0) -- and so do servers that stopped reporting
			Matchmaking.Heartbeat("trio", "A", "codeA", 6, 4, 6, {})
			expect(Matchmaking.FindOpen("trio")[1].open).toBe(4)
			-- tickets: for one server, used once, gone after their time
			expect(Matchmaking.PutTicket(11, {host = 12, format = "trio", server = "A"})).toBe(true)
			local ticket, why = Matchmaking.TakeTicket(11, "B")
			expect(ticket).toBe(nil)
			expect(why).toBe("other_server")
			expect(Matchmaking.TakeTicket(11, "A").host).toBe(12)
			ticket, why = Matchmaking.TakeTicket(11, "A")
			expect(why).toBe("none")
			Matchmaking.PutTicket(11, {host = 12, format = "trio", server = "A"})
			t += Matchmaking.Ttl.Ticket + 1
			expect((Matchmaking.TakeTicket(11, "A"))).toBe(nil)
			expect(Matchmaking.ReservedId("")).toBe(Matchmaking.StudioServer)
			expect(Matchmaking.ReservedId("abc")).toBe("abc")
		end)
		Matchmaking.UseBackend(saved[1])
		Matchmaking.Now = saved[2]
		if not ok then error(err, 0) end
	end)

	if not ctx.live then return end
	local Loader = require(ctx.shared.Modules.Loader)
	local PS, MS = Loader.Get("LobbyPartyService"), Loader.Get("MatchService")

	-- stand-in players, a recorder instead of the teleport and a clock the test moves; everything is put back
	local function fixture(fn)
		local saved = {MS.Teleporter, Matchmaking.Backend(), Matchmaking.Now, PS.Clock, LobbyCfg.TeleportRetrySeconds, Matchmaking.Attempts}
		local f = {bots = {}, reserved = 0, sends = {}, t = 1000}
		function f.bot(i)
			local b = {UserId = -9100 - i, Name = "Bot" .. i, DisplayName = "Bot " .. i, Parent = workspace}
			table.insert(f.bots, b)
			PS:Enter(b)
			return b
		end
		-- a full party led by the first bot
		function f.party(first, size)
			local leader = f.bot(first)
			local format = Matchmaking.FormatBySize(PartyCfg.Formats, size)
			expect(PS:SetFormat(leader, format.id)).toBe(true)
			for i = 1, size - 1 do
				local guest = f.bot(first + i)
				expect(PS:Invite(leader, guest)).toBe(true)
				expect(PS:Answer(guest, leader, true)).toBe(true)
			end
			return leader, PS:Get(leader)
		end
		MS.Teleporter = {
			Reserve = function(placeId)
				if f.failReserve then error("reserve refused") end
				f.reserved += 1
				f.reservedPlace = placeId
				return "code" .. f.reserved, "server" .. f.reserved
			end,
			Send = function(placeId, players, code, data)
				if f.failSend then error("teleport refused") end
				table.insert(f.sends, {place = placeId, players = table.clone(players), code = code, data = data})
			end,
		}
		Matchmaking.UseBackend(Matchmaking.LocalBackend())
		Matchmaking.Now = function() return f.t end
		Matchmaking.Attempts = 1
		PS.Clock = function() return f.t end
		LobbyCfg.TeleportRetrySeconds = 0
		local ok, err = pcall(fn, f)
		for _, b in ipairs(f.bots) do PS:Exit(b) end
		MS.Teleporter = saved[1]
		Matchmaking.UseBackend(saved[2])
		Matchmaking.Now, PS.Clock, LobbyCfg.TeleportRetrySeconds, Matchmaking.Attempts = saved[3], saved[4], saved[5], saved[6]
		if not ok then error(err, 0) end
	end

	-- how `other` looks in the list of lobby players that `player` gets
	local function listed(player, other)
		for _, entry in ipairs(PS:Snapshot(player).players) do
			if entry.id == other.UserId then return entry end
		end
		return nil
	end

	it("M9 store: Studio keeps the server list in memory unless asked otherwise, live servers use MemoryStore", function()
		expect(MS.StoreKind(true, nil)).toBe("local")
		expect(MS.StoreKind(true, "memorystore")).toBe("memorystore")
		expect(MS.StoreKind(false, nil)).toBe("memorystore")
		expect(MS.StoreKind(false, "local")).toBe("memorystore")
	end)

	it("M9 party: everyone starts alone as a leader; invite, accept, decline, expiry, a full party, kick and leave", function() fixture(function(f)
		local a, b, c, d = f.bot(1), f.bot(2), f.bot(3), f.bot(4)
		local party = PS:Get(a)
		expect(party.leader).toBe(a)
		expect(party.format).toBe("solo")
		expect(#party.members).toBe(1)
		local ok, why = PS:Invite(a, b)
		expect(why).toBe("full") -- a solo party has one seat
		expect(PS:SetFormat(a, "duo")).toBe(true)
		ok, why = PS:SetFormat(a, "septet")
		expect(ok).toBe(false)
		expect(PS:Invite(a, b)).toBe(true)
		expect(PS:Snapshot(b).invites[1].id).toBe(a.UserId)
		expect(listed(a, b).invited).toBe(true)
		expect(listed(a, c).invited).toBe(false)
		ok, why = PS:Answer(b, a, false)
		expect(why).toBe("declined")
		expect(#PS:Get(a).members).toBe(1)
		-- an invitation nobody answered in time is gone
		expect(PS:Invite(a, b)).toBe(true)
		f.t += LobbyCfg.InviteSeconds + 1
		ok, why = PS:Answer(b, a, true)
		expect(ok).toBe(false)
		expect(why).toBe("expired")
		ok, why = PS:Answer(b, a, true)
		expect(why).toBe("expired") -- and there is nothing to accept twice
		-- accept: b is in a's party, which is now full
		expect(PS:Invite(a, b)).toBe(true)
		expect(PS:Invite(a, c)).toBe(true)
		expect(PS:Answer(b, a, true)).toBe(true)
		expect(PS:Get(b)).toBe(PS:Get(a))
		ok, why = PS:Answer(c, a, true)
		expect(why).toBe("full")
		ok, why = PS:Invite(b, d)
		expect(why).toBe("not_leader")
		ok, why = PS:SetFormat(b, "trio")
		expect(why).toBe("not_leader")
		ok, why = PS:SetFormat(a, "solo")
		expect(why).toBe("too_many") -- two Guardians do not fit a solo party
		-- somebody who is already in a party cannot be invited, and has to leave it before joining another
		expect(PS:SetFormat(c, "duo")).toBe(true)
		ok, why = PS:Invite(c, b)
		expect(why).toBe("busy")
		expect(PS:SetFormat(a, "trio")).toBe(true)
		expect(PS:Invite(c, d)).toBe(true)
		expect(PS:Answer(d, c, true)).toBe(true)
		expect(PS:Invite(a, c)).toBe(false)
		-- kick and leave give the player a party of their own again
		ok, why = PS:Kick(b, a)
		expect(why).toBe("not_leader")
		expect(PS:Kick(a, b)).toBe(true)
		expect(PS:Get(b).leader).toBe(b)
		expect(#PS:Get(a).members).toBe(1)
		expect(PS:Leave(d)).toBe(true)
		expect(PS:Get(d).leader).toBe(d)
		expect(#PS:Get(c).members).toBe(1)
		-- the leader is the host of the team: when the leader leaves, the party is disbanded
		expect(PS:Invite(c, d)).toBe(true)
		expect(PS:Answer(d, c, true)).toBe(true)
		expect(PS:Leave(c)).toBe(true)
		expect(PS:Get(d).leader).toBe(d)
		expect(#PS:Get(d).members).toBe(1)
		expect(PS:Get(c).leader).toBe(c)
	end) end)

	it("M9 set out: only a full party leaves; it gets a server of its format, a house and a ticket for every member", function() fixture(function(f)
		local leader = f.bot(1)
		expect(PS:SetFormat(leader, "quartet")).toBe(true)
		local guests = {f.bot(2), f.bot(3)}
		for _, g in ipairs(guests) do
			PS:Invite(leader, g)
			expect(PS:Answer(g, leader, true)).toBe(true)
		end
		local ok, why = PS:SetOut(leader)
		expect(ok).toBe(false)
		expect(why).toBe("not_full") -- three of four
		expect(f.reserved).toBe(0)
		ok, why = PS:SetOut(guests[1])
		expect(why).toBe("not_leader")
		local fourth = f.bot(4)
		PS:Invite(leader, fourth)
		expect(PS:Answer(fourth, leader, true)).toBe(true)
		expect(PS:SetOut(leader)).toBe(true)
		expect(f.reserved).toBe(1)
		expect(f.reservedPlace).toBe(GameCfg.Places.Game)
		expect(#f.sends).toBe(1)
		local sent = f.sends[1]
		expect(sent.place).toBe(GameCfg.Places.Game)
		expect(#sent.players).toBe(4)
		expect(sent.code).toBe("code1")
		-- the list has the new server with five houses, one of them held for this party
		local entry = Matchmaking.Backend().Get(Matchmaking.Maps.Servers .. "quartet", "server1")
		expect(entry.houses).toBe(5)
		expect(entry.code).toBe("code1")
		expect(Matchmaking.OpenHouses(entry)).toBe(4)
		for _, p in ipairs({leader, guests[1], guests[2], fourth}) do
			local ticket = Matchmaking.TakeTicket(p.UserId, "server1")
			expect(ticket.host).toBe(leader.UserId)
			expect(ticket.format).toBe("quartet")
			expect(#ticket.members).toBe(4)
			expect(ticket.code).toBe("code1")
		end
		-- while the party is on its way nothing about it can be changed
		expect(PS:Get(leader).launching).toBe(true)
		ok, why = PS:SetFormat(leader, "quartet")
		expect(why).toBe("launching")
		ok, why = PS:Kick(leader, fourth)
		expect(why).toBe("launching")
		ok, why = PS:Leave(fourth)
		expect(why).toBe("launching")
		ok, why = PS:SetOut(leader)
		expect(why).toBe("launching")
		-- its members leave the lobby one after another; those still here stay in the party
		PS:Exit(leader)
		expect(#PS:Get(fourth).members).toBe(3)
		expect(PS:Get(fourth).launching).toBe(true)
	end) end)

	it("M9 matching: parties of one format fill a server house by house, other formats and full servers get new ones", function() fixture(function(f)
		local duoA = f.party(1, 2)
		expect(PS:SetOut(duoA)).toBe(true)
		local duoB = f.party(3, 2)
		expect(PS:SetOut(duoB)).toBe(true)
		expect(f.reserved).toBe(1) -- the second duo goes to the server of the first
		expect(f.sends[2].code).toBe("code1")
		expect(Matchmaking.TakeTicket(duoB.UserId, "server1").host).toBe(duoB.UserId)
		local solo = f.bot(5)
		expect(PS:SetOut(solo)).toBe(true)
		expect(f.reserved).toBe(2) -- a solo player needs a solo server
		expect(f.sends[3].code).toBe("code2")
		expect(Matchmaking.Backend().Get(Matchmaking.Maps.Servers .. "solo", "server2").houses).toBe(20)
		-- the duo server reports that every house is taken: the next duo opens a new server
		Matchmaking.Heartbeat("duo", "server1", "code1", 10, 0, 20, {duoA.UserId, duoB.UserId})
		local duoC = f.party(6, 2)
		expect(PS:SetOut(duoC)).toBe(true)
		expect(f.reserved).toBe(3)
		expect(f.sends[4].code).toBe("code3")
		-- six trio parties fit one trio server (18 players), the seventh gets another
		local before = f.reserved
		for i = 1, 7 do
			local trio = f.party(10 + i * 3, 3)
			expect(PS:SetOut(trio)).toBe(true)
			expect(f.reserved).toBe(before + (i <= 6 and 1 or 2))
		end
	end) end)

	it("M9 failure: when the server or the teleport is refused, the party stays in the lobby and its house is free again", function() fixture(function(f)
		local first = f.party(1, 2)
		expect(PS:SetOut(first)).toBe(true)
		local leader = f.party(3, 2)
		f.failSend = true
		local ok, why = PS:SetOut(leader)
		expect(ok).toBe(false)
		expect(why).toBe("teleport")
		expect(PS:Get(leader).launching).toBe(false)
		expect(#PS:Get(leader).members).toBe(2)
		local entry = Matchmaking.Backend().Get(Matchmaking.Maps.Servers .. "duo", "server1")
		expect(Matchmaking.OpenHouses(entry)).toBe(9) -- only the first party holds a house
		f.failSend = false
		f.failReserve = true
		local solo = f.bot(5)
		ok, why = PS:SetOut(solo)
		expect(ok).toBe(false)
		expect(why).toBe("server")
		expect(PS:Get(solo).launching).toBe(false)
		f.failReserve = false
		expect(PS:SetOut(leader)).toBe(true) -- and the same party can try again
		expect(f.sends[#f.sends].code).toBe("code1")
	end) end)

	it("M9 return: a player whose team is still on a game server is offered the way back and gets a ticket to it", function() fixture(function(f)
		local bot = f.bot(1)
		expect(MS:Greet(bot)).toBe(nil)
		local ok, why = PS:Rejoin(bot)
		expect(ok).toBe(false)
		expect(why).toBe("gone")
		Matchmaking.PutSession(bot.UserId, {host = 777, hostName = "Host", format = "trio", server = "srv", code = "key", members = {777, bot.UserId}})
		expect(MS:Greet(bot).host).toBe(777)
		local offer = PS:Snapshot(bot).rejoin
		expect(offer.hostName).toBe("Host")
		expect(offer.format).toBe("trio")
		expect(PS:Rejoin(bot)).toBe(true)
		expect(f.sends[1].code).toBe("key")
		expect(f.sends[1].players[1]).toBe(bot)
		expect(f.reserved).toBe(0)
		local ticket = Matchmaking.TakeTicket(bot.UserId, "srv")
		expect(ticket.host).toBe(777)
		expect(ticket.rejoin).toBe(true)
		-- the team has left the game meanwhile: the offer is withdrawn
		local other = f.bot(2)
		Matchmaking.PutSession(other.UserId, {host = 778, hostName = "H", format = "duo", server = "s2", code = "k2", members = {}})
		MS:Greet(other)
		f.t += Matchmaking.Ttl.Session + 1
		ok, why = PS:Rejoin(other)
		expect(why).toBe("gone")
		expect(PS:Snapshot(other).rejoin).toBe(nil)
	end) end)

	it("M9 live: the player in this session has a solo party and sees the others in the lobby", function() fixture(function(f)
		local player = game:GetService("Players"):GetPlayers()[1]
		expect(player ~= nil).toBeTruthy()
		local snap = PS:Snapshot(player)
		expect(snap.party.leader).toBe(player.UserId)
		expect(#snap.party.members).toBe(1)
		local bot = f.bot(1)
		expect(listed(player, bot).size).toBe(1)
		expect(workspace:FindFirstChild("Lobby") ~= nil and workspace.Lobby:FindFirstChild("Spawn_1") ~= nil).toBeTruthy()
	end) end)
end
