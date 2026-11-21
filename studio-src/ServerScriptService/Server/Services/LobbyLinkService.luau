-- Link to the lobby (milestone 9, decision 2). The lobby sends a party here with a ticket for every member; this
-- service reads the ticket when a player arrives and tells the other services what it says: who the host is and
-- what format the server has. TeleportData is not trusted: it travels through the client and can be forged.
-- While teams from the lobby play here, the server tells the lobby how many houses are free and which members
-- may come back to their team.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Matchmaking = require(Shared.Modules.Matchmaking)
local Layout = require(Shared.Modules.Layout)
local GameCfg = require(Shared.Config.Game)
local Coop = require(Shared.Config.Coop)

local LobbyLink = {Priority = 95}
local PartyService
local arrivals = {}  -- [player] = {host, format, source, helpHost, redirect}
local resolving = {} -- [player] = true while the ticket is being read
local failed = {}    -- [player] = true: a teleport of this player did not start
local seats = {}     -- [hostUserId] = user ids of the team, from its tickets
local hostNames = {} -- [hostUserId] = name of the host, for the lobby
local beatQueued = false

LobbyLink.ServerId = nil -- what the lobby calls this server
LobbyLink.Reserved = false
LobbyLink.Format = nil   -- the format of this server, once a party from the lobby has arrived
LobbyLink.Code = nil     -- its access code, for those who are sent here later

-- The call that leaves this server. Tests replace it
LobbyLink.Teleport = function(placeId, players)
	return TeleportService:TeleportAsync(placeId, players)
end

-- Studio keeps tickets in memory unless ServerStorage.GS_LobbyStore = "memorystore"; live servers use MemoryStore
function LobbyLink.StoreKind(isStudio, studioStore)
	if isStudio and studioStore ~= "memorystore" then return "local" end
	return "memorystore"
end

-- A player who came without a ticket goes to the lobby first (design doc 1.3: the game starts with the lobby).
-- Not in Studio, and not on a reserved server: only our own servers send players to those
function LobbyLink.ShouldRedirect(enabled, lobbyPlaceId, isStudio, isReserved)
	return enabled == true and (tonumber(lobbyPlaceId) or 0) > 0 and not isStudio and not isReserved
end

function LobbyLink:Init()
	PartyService = Loader.Get("PartyService")
	local kind = LobbyLink.StoreKind(RunService:IsStudio(), ServerStorage:GetAttribute("GS_LobbyStore"))
	Matchmaking.UseBackend(kind == "local" and Matchmaking.LocalBackend() or Matchmaking.MemoryStoreBackend())
	ReplicatedStorage:SetAttribute("LobbyStore", kind)
	self.ServerId = Matchmaking.ServerId()
	self.Reserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- The first ticket says what this server is: its format and its access code. Every ticket names the team's seats
function LobbyLink:Adopt(ticket)
	local f = Layout.Format(ticket.format)
	if not self.Format then
		self.Format, self.Code = f.id, ticket.code
		-- a house holds as many Guardians as the format says, so a team on this server cannot be bigger
		PartyService.SeatLimit = f.size
		print(string.format("[LobbyLink] server %s: format %s from the lobby", tostring(self.ServerId), f.id))
	end
	local host, ids = tonumber(ticket.host), {}
	for _, id in ipairs(type(ticket.members) == "table" and ticket.members or {}) do
		if tonumber(id) then table.insert(ids, tonumber(id)) end
	end
	if #ids > 0 or not seats[host] then seats[host] = ids end
	hostNames[host] = ticket.hostName
end

-- How this player came here: with a ticket of a party, as a helper, or directly. Kept for the whole visit
function LobbyLink:Resolve(player)
	while resolving[player] do task.wait() end
	if arrivals[player] then return arrivals[player] end
	resolving[player] = true
	local a = {host = player.UserId, source = "direct"}
	local ok, err = pcall(function()
		local ticket, why = Matchmaking.TakeTicket(player.UserId, self.ServerId)
		a.why = why
		if ticket and ticket.kind == "helper" then
			a.source, a.helpHost = "helper", tonumber(ticket.helpHost)
		elseif ticket and tonumber(ticket.host) and Layout.Format(ticket.format) then
			a.source, a.host, a.format = "ticket", tonumber(ticket.host), ticket.format
			self:Adopt(ticket)
		elseif LobbyLink.ShouldRedirect(Coop.Lobby.RedirectDirectJoins, GameCfg.Places.Lobby, RunService:IsStudio(), self.Reserved) then
			a.redirect = true
		end
	end)
	if not ok then warn("[LobbyLink] ticket of " .. tostring(player.Name) .. ": " .. tostring(err)) end
	resolving[player] = nil
	arrivals[player] = a
	return a
end

-- The player has left, or a test is done with its stand-in
function LobbyLink:Forget(player)
	arrivals[player], resolving[player], failed[player] = nil, nil, nil
end

function LobbyLink:SendToLobby(player)
	local ok, err = pcall(LobbyLink.Teleport, GameCfg.Places.Lobby, {player})
	if not ok then warn("[LobbyLink] teleport to the lobby failed: " .. tostring(err)) end
	return ok
end

-- Send a player who came without a ticket to the lobby. Returns true when the player has left;
-- false when the teleport did not work, and then the player plays here as a team of one
function LobbyLink:Redirect(player)
	local sent = self:SendToLobby(player)
	local t0 = os.clock()
	while sent and player.Parent and not failed[player] and os.clock() - t0 < Coop.Lobby.RedirectWaitSeconds do
		task.wait(0.5)
	end
	failed[player] = nil
	if sent and not player.Parent then return true end
	warn("[LobbyLink] " .. tostring(player.Name) .. " could not be sent to the lobby and plays here")
	if arrivals[player] then arrivals[player].redirect = nil end
	return false
end

-- Houses that no team has, and all houses
function LobbyLink:FreeHouses()
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	local free, total = 0, 0
	for _, plot in ipairs(plots and plots:GetChildren() or {}) do
		total += 1
		if (plot:GetAttribute("OwnerHost") or 0) == 0 then free += 1 end
	end
	return free, total
end

-- Tell the lobby how many houses are free here and which members of the teams playing here may come back
function LobbyLink:Beat()
	if not self.Format then return false end
	local free, total = self:FreeHouses()
	local hosts = {}
	for host in pairs(seats) do
		if #PartyService:GetMembers(host) > 0 then table.insert(hosts, host) end
	end
	Matchmaking.Heartbeat(self.Format, self.ServerId, self.Code, total, free, #Players:GetPlayers(), hosts)
	for _, host in ipairs(hosts) do
		for _, id in ipairs(seats[host]) do
			if not Players:GetPlayerByUserId(id) then
				Matchmaking.PutSession(id, {
					host = host, hostName = hostNames[host], format = self.Format,
					server = self.ServerId, code = self.Code, members = seats[host],
				})
			end
		end
	end
	return true
end

-- Something changed (a team came or went): report soon, but not for every player separately
function LobbyLink:QueueBeat()
	if beatQueued or not self.Format then return end
	beatQueued = true
	task.delay(1, function()
		beatQueued = false
		pcall(self.Beat, self)
	end)
end

function LobbyLink:AccessCode()
	return self.Code
end

-- A helper called to a wave on another server (design doc 5.4). The ticket tells that server who is coming
function LobbyLink:HelperTicket(helper, alert)
	return Matchmaking.PutTicket(helper.UserId, {kind = "helper", helpHost = alert.hostUserId, server = alert.serverId or alert.jobId})
end

function LobbyLink:Start()
	Players.PlayerRemoving:Connect(function(player)
		self:Forget(player)
		self:QueueBeat()
	end)
	-- nobody of the team is left: its members have nowhere to come back to
	PartyService.TeamEmptied.Event:Connect(function(host)
		for _, id in ipairs(seats[host] or {}) do task.spawn(Matchmaking.DropSession, id) end
		seats[host], hostNames[host] = nil, nil
		self:QueueBeat()
	end)
	TeleportService.TeleportInitFailed:Connect(function(player) failed[player] = true end)
	Net.On("LobbyAction", 1, function(player, action)
		if action == "return" and not self:SendToLobby(player) then
			Net.Fire(player, "Notify", "lobby_return_failed")
		end
	end)
	game:BindToClose(function()
		if self.Format then Matchmaking.Unregister(self.Format, self.ServerId) end
	end)
	while true do
		task.wait(Coop.Lobby.HeartbeatSeconds)
		pcall(self.Beat, self)
	end
end

return LobbyLink
