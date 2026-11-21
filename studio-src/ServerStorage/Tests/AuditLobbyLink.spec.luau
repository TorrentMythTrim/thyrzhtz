-- Milestone 9 (2026-11-21): the link between the game place and the lobby
-- (technical plan, milestone 9, items 1-3; decision 2; design doc 1.3, 2.1, 2.4).
-- The server list and the tickets are a table here and the teleport is a recorder: no store is touched and nobody
-- is teleported. Other players are stand-ins (tables). What the tests change in the services is put back.
local RunService = game:GetService("RunService")

return function(it, expect, ctx)
	local GameCfg = require(ctx.shared.Config.Game)
	local Coop = require(ctx.shared.Config.Coop)
	local Party = require(ctx.shared.Config.Party)
	local Net = require(ctx.shared.Modules.Net)
	local Matchmaking = require(ctx.shared.Modules.Matchmaking)
	local CoopStrings = require(ctx.shared.Locale.CoopStrings)
	local Strings = require(ctx.shared.Locale.Strings)

	it("M9 config: the lobby place is set, the new events and texts exist in both languages", function()
		expect(GameCfg.Places.Lobby).toBe(106448766989936)
		expect(GameCfg.Places.Game).toBe(129614341268000)
		expect(Matchmaking.Version).toBe(1)
		for _, name in ipairs({"LobbyAction", "AfkPrompt", "AfkAction", "TradeAction", "TradeEvent"}) do
			expect(table.find(Net.Events, name) ~= nil).toBeTruthy()
		end
		local n = 0
		for key, text in pairs(CoopStrings.en) do
			n += 1
			expect(type(CoopStrings.ru[key])).toBe("string")
			expect(Strings.en[key]).toBe(text) -- Locale has added them to the common strings
		end
		for key in pairs(CoopStrings.ru) do expect(type(CoopStrings.en[key])).toBe("string") end
		expect(n > 0).toBeTruthy()
		-- design doc 6.7: the reward bonus by team size
		local m = Party.RewardMultiplier
		expect(m[1] == 1 and m[2] == 1.1 and m[3] == 1.25 and m[4] == 1.5).toBeTruthy()
	end)

	if not ctx.live then return end
	local Loader = require(ctx.shared.Modules.Loader)
	local LL, PS, DS = Loader.Get("LobbyLinkService"), Loader.Get("PartyService"), Loader.Get("DataService")
	local HS = Loader.Get("HouseService")
	local player = game:GetService("Players"):GetPlayers()[1]

	local function bot(id)
		local b = {UserId = id, Name = "AuditBot" .. id, DisplayName = "AuditBot", Parent = workspace, attrs = {}}
		function b:Kick(message) self.kicked = message or true end
		function b:SetAttribute(key, value) self.attrs[key] = value end
		function b:GetAttribute(key) return self.attrs[key] end
		return b
	end

	-- an empty server list and a recorder instead of the teleport; the state of the link is put back afterwards
	local function fixture(fn)
		local saved = {Matchmaking.Backend(), Matchmaking.Now, Matchmaking.Attempts, LL.Teleport, LL.Format, LL.Code, PS.SeatLimit, Coop.Lobby.RedirectWaitSeconds}
		local f = {t = 9000, bots = {}, sent = {}}
		function f.bot(id)
			local b = bot(id)
			table.insert(f.bots, b)
			return b
		end
		Matchmaking.UseBackend(Matchmaking.LocalBackend())
		Matchmaking.Now = function() return f.t end
		Matchmaking.Attempts = 1
		LL.Format, LL.Code, PS.SeatLimit = nil, nil, nil
		LL.Teleport = function(placeId, players)
			if f.failTeleport then error("teleport refused") end
			table.insert(f.sent, {place = placeId, players = players})
			if f.leaves then players[1].Parent = nil end
		end
		local ok, err = pcall(fn, f)
		for _, b in ipairs(f.bots) do
			PS:Leave(b)
			LL:Forget(b)
		end
		Matchmaking.UseBackend(saved[1])
		Matchmaking.Now, Matchmaking.Attempts, LL.Teleport = saved[2], saved[3], saved[4]
		LL.Format, LL.Code, PS.SeatLimit, Coop.Lobby.RedirectWaitSeconds = saved[5], saved[6], saved[7], saved[8]
		if not ok then error(err, 0) end
	end

	it("M9 rules: who is sent to the lobby and where the tickets are kept", function()
		local lobby = GameCfg.Places.Lobby
		expect(LL.ShouldRedirect(true, lobby, false, false)).toBe(true) -- a public live server, no ticket
		expect(LL.ShouldRedirect(true, lobby, true, false)).toBe(false) -- never in Studio
		expect(LL.ShouldRedirect(true, lobby, false, true)).toBe(false) -- only our own servers send players to a reserved one
		expect(LL.ShouldRedirect(false, lobby, false, false)).toBe(false) -- switched off in the config
		expect(LL.ShouldRedirect(true, 0, false, false)).toBe(false) -- no lobby place
		expect(LL.StoreKind(true, nil)).toBe("local")
		expect(LL.StoreKind(true, "memorystore")).toBe("memorystore")
		expect(LL.StoreKind(false, nil)).toBe("memorystore")
		expect(LL.ServerId).toBe(Matchmaking.ServerId())
		expect(RunService:IsStudio()).toBe(true)
	end)

	it("M9 arrival: the host and the format come from the ticket the server reads, never from TeleportData", function() fixture(function(f)
		-- no ticket: the player is the host of their own team; in Studio nobody is sent to the lobby
		local alone = f.bot(-9201)
		function alone:GetJoinData() return {TeleportData = {partyHost = 4242, format = "quartet"}} end
		local a = LL:Resolve(alone)
		expect(a.source).toBe("direct")
		expect(a.host).toBe(alone.UserId)
		expect(a.redirect).toBe(nil)
		expect(PS:ResolveHost(alone)).toBe(alone.UserId) -- the forged TeleportData is not read at all
		expect(PS:ResolveFormat(alone)).toBe(nil)
		-- a ticket for this server
		local guest = f.bot(-9202)
		expect(Matchmaking.PutTicket(guest.UserId, {host = -9203, hostName = "Host", format = "duo", server = LL.ServerId, code = "key", members = {-9203, guest.UserId}})).toBe(true)
		a = LL:Resolve(guest)
		expect(a.source).toBe("ticket")
		expect(a.host).toBe(-9203)
		expect(a.format).toBe("duo")
		expect(PS:ResolveHost(guest)).toBe(-9203)
		expect(PS:ResolveFormat(guest)).toBe("duo")
		expect(LL:Resolve(guest)).toBe(a) -- asked once, kept for the visit
		expect((Matchmaking.TakeTicket(guest.UserId, LL.ServerId))).toBe(nil) -- and the ticket is used up
		-- the first ticket says what this server is
		expect(LL.Format).toBe("duo")
		expect(LL:AccessCode()).toBe("key")
		expect(PS.SeatLimit).toBe(2)
		-- a ticket for another server, a ticket with an unknown format and an expired ticket do not count
		local stray = f.bot(-9204)
		Matchmaking.PutTicket(stray.UserId, {host = -9203, format = "duo", server = "some-other-server"})
		a = LL:Resolve(stray)
		expect(a.source).toBe("direct")
		expect(a.why).toBe("other_server")
		expect(a.host).toBe(stray.UserId)
		local odd = f.bot(-9205)
		Matchmaking.PutTicket(odd.UserId, {host = -9203, format = "septet", server = LL.ServerId})
		expect(LL:Resolve(odd).host).toBe(odd.UserId)
		local late = f.bot(-9206)
		Matchmaking.PutTicket(late.UserId, {host = -9203, format = "duo", server = LL.ServerId})
		f.t += Matchmaking.Ttl.Ticket + 1
		expect(LL:Resolve(late).host).toBe(late.UserId)
		-- a helper called to a wave on this server (design doc 5.4) is known by the ticket too
		local helper = f.bot(-9207)
		expect(LL:HelperTicket(helper, {hostUserId = -9203, serverId = LL.ServerId})).toBe(true)
		a = LL:Resolve(helper)
		expect(a.source).toBe("helper")
		expect(a.helpHost).toBe(-9203)
		expect(a.host).toBe(helper.UserId)
	end) end)

	it("M9 lobby and back: a player without a ticket is sent to the lobby and stays if that fails; the way back uses the lobby place", function() fixture(function(f)
		local b = f.bot(-9211)
		f.leaves = true
		expect(LL:Redirect(b)).toBe(true) -- left for the lobby
		expect(f.sent[1].place).toBe(GameCfg.Places.Lobby)
		expect(f.sent[1].players[1]).toBe(b)
		local c = f.bot(-9212)
		f.leaves, f.failTeleport = false, true
		expect(LL:Redirect(c)).toBe(false) -- the teleport was refused: the player plays here
		f.failTeleport = false
		Coop.Lobby.RedirectWaitSeconds = 0.6
		local t0 = os.clock()
		expect(LL:Redirect(c)).toBe(false) -- accepted, but the player is still here after the wait
		expect(os.clock() - t0 < 5).toBeTruthy()
		expect(LL:SendToLobby(c)).toBe(true)
		expect(f.sent[#f.sent].place).toBe(GameCfg.Places.Lobby)
	end) end)

	it("M9 report to the lobby: free houses, the players here and the members who may come back", function() fixture(function(f)
		local host = PS:GetHost(player)
		local format = HS:GetFormat()
		expect(LL:Beat()).toBe(false) -- no party from the lobby has arrived: nothing to report
		LL:Adopt({host = host, hostName = "Leader", format = format, code = "key", members = {host, -9221}})
		expect(LL:Beat()).toBe(true)
		local free, total = LL:FreeHouses()
		local owned = 0
		for _, plot in ipairs(workspace.Map.Plots:GetChildren()) do
			if (plot:GetAttribute("OwnerHost") or 0) ~= 0 then owned += 1 end
		end
		expect(total).toBe(#workspace.Map.Plots:GetChildren())
		expect(free).toBe(total - owned)
		expect(owned >= 1).toBeTruthy()
		local entry = Matchmaking.Backend().Get(Matchmaking.Maps.Servers .. format, LL.ServerId)
		expect(entry.houses).toBe(total)
		expect(entry.free).toBe(free)
		expect(entry.code).toBe("key")
		expect(entry.players).toBe(#game:GetService("Players"):GetPlayers())
		-- the lobby finds this server while it has a free house
		local open = Matchmaking.FindOpen(format)
		expect(#open).toBe(free > 0 and 1 or 0)
		-- the member who is not here can come back to the team; the one who is here needs no way back
		local session = Matchmaking.GetSession(-9221)
		expect(session.host).toBe(host)
		expect(session.server).toBe(LL.ServerId)
		expect(session.code).toBe("key")
		expect(session.format).toBe(format)
		expect(Matchmaking.GetSession(player.UserId)).toBe(nil)
	end) end)

	if DS:IsMemoryMode() then
		it("M9 seats: on a server from the lobby a team is not bigger than a house of the format holds", function() fixture(function(f)
			local hostId = -9231
			local first, second, owner = f.bot(-9232), f.bot(-9233), f.bot(hostId)
			PS.SeatLimit = 2 -- a duo server
			expect(PS:Join(first, hostId)).toBe(true)
			local ok, why = PS:Join(second, hostId)
			expect(ok).toBe(false)
			expect(why).toBe("full")
			expect(PS:Join(owner, hostId)).toBe(true) -- the host's own seat is always kept
			expect(PS:GetSize(owner)).toBe(2)
			PS.SeatLimit = nil -- no lobby: the general limit of four
			expect(PS:Join(second, hostId)).toBe(true)
			expect(PS:GetSize(owner)).toBe(3)
			-- shared progress: one team record for all of them (decision 5)
			expect(DS:GetTeam(PS:GetHost(first))).toBe(DS:GetTeam(hostId))
			expect(DS:GetTeam(hostId) ~= DS:GetTeam(PS:GetHost(player))).toBeTruthy()
		end) end)
	end
end
