-- Server matching and the way to the game (milestone 9, decision 2, variant A): the lobby keeps a list of game
-- servers for every party format and sends a party where a house is free; when there is none, it reserves a new
-- server. Each member gets a ticket that the game server reads, so nothing important travels through the client.
-- A Studio play session can follow the teleport too: it continues in the last saved version of the game place.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Matchmaking = require(Shared.Modules.Matchmaking)
local GameCfg = require(Shared.Config.Game)
local LobbyCfg = require(Shared.Config.Lobby)

local MatchService = {Priority = 90}
local PartyService
local failures = {} -- [player] = teleports that did not start

-- The two calls that leave this server. Tests replace them
MatchService.Teleporter = {
	Reserve = function(placeId)
		return TeleportService:ReserveServer(placeId)
	end,
	Send = function(placeId, players, code, data)
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData(data)
		return TeleportService:TeleportAsync(placeId, players, options)
	end,
}

-- Studio keeps the server list in memory unless ServerStorage.GS_LobbyStore = "memorystore"; live servers use MemoryStore
function MatchService.StoreKind(isStudio, studioStore)
	if isStudio and studioStore ~= "memorystore" then return "local" end
	return "memorystore"
end

function MatchService:Init()
	PartyService = Loader.Get("LobbyPartyService")
	local kind = MatchService.StoreKind(RunService:IsStudio(), ServerStorage:GetAttribute("GS_LobbyStore"))
	Matchmaking.UseBackend(kind == "local" and Matchmaking.LocalBackend() or Matchmaking.MemoryStoreBackend())
	ReplicatedStorage:SetAttribute("LobbyStore", kind)
	print("[Match] server list: " .. kind)
end

local function send(players, code, data)
	local err
	for attempt = 1, LobbyCfg.TeleportAttempts do
		local ok, res = pcall(MatchService.Teleporter.Send, GameCfg.Places.Game, players, code, data)
		if ok then return true end
		err = res
		if attempt < LobbyCfg.TeleportAttempts then task.wait(LobbyCfg.TeleportRetrySeconds) end
	end
	warn("[Match] teleport failed: " .. tostring(err))
	return false, err
end

-- A server of the format with a house for this host: an existing one first, otherwise a new reserved server.
-- Returns the server id, its access code and whether it is new
function MatchService:FindServer(format, hostUserId)
	for _, candidate in ipairs(Matchmaking.FindOpen(format.id)) do
		local entry = Matchmaking.Claim(format.id, candidate.id, hostUserId)
		if entry then return candidate.id, entry.code, false end
	end
	local ok, code, serverId = pcall(MatchService.Teleporter.Reserve, GameCfg.Places.Game)
	if not ok or type(code) ~= "string" or type(serverId) ~= "string" then
		warn("[Match] cannot reserve a server: " .. tostring(code))
		return nil
	end
	serverId = Matchmaking.ReservedId(serverId)
	if not Matchmaking.Register(format.id, serverId, code, format.houses, hostUserId) then return nil end
	return serverId, code, true
end

-- Send a party to the game. members: the players; leader: the host of the team; format: an entry of Party.Formats
function MatchService:Launch(members, leader, format)
	local host = leader.UserId
	local serverId, code = self:FindServer(format, host)
	if not serverId then return false, "server" end
	local ids = {}
	for i, p in ipairs(members) do ids[i] = p.UserId end
	for _, p in ipairs(members) do
		local ticket = {
			host = host, hostName = leader.DisplayName or leader.Name, format = format.id,
			server = serverId, code = code, members = ids,
		}
		if not Matchmaking.PutTicket(p.UserId, ticket) then
			Matchmaking.Release(format.id, serverId, host)
			return false, "store"
		end
		Matchmaking.DropSession(p.UserId) -- the team this player was in before is left behind
	end
	-- TeleportData is for the log only: the game server takes the host and the format from the ticket
	local ok, err = send(members, code, {partyHost = host, format = format.id})
	if not ok then
		Matchmaking.Release(format.id, serverId, host)
		return false, "teleport", err
	end
	print(string.format("[Match] party of %d (host %d, %s) sent to server %s", #members, host, format.id, serverId))
	return true, serverId
end

-- A player whose team is still on a game server (they dropped out or were removed for being idle) can go back
function MatchService:Greet(player)
	local session = Matchmaking.GetSession(player.UserId)
	if session then PartyService:OfferRejoin(player, session) end
	return session
end

function MatchService:Rejoin(player)
	local s = Matchmaking.GetSession(player.UserId)
	if not s then return false, "gone" end
	local ticket = {
		host = s.host, hostName = s.hostName, format = s.format,
		server = s.server, code = s.code, members = s.members, rejoin = true,
	}
	if not Matchmaking.PutTicket(player.UserId, ticket) then return false, "store" end
	local ok, err = send({player}, s.code, {partyHost = s.host, format = s.format})
	if not ok then return false, "teleport", err end
	return true
end

function MatchService:Start()
	-- a teleport that was accepted but did not start: the same teleport once more, then the party is given back
	TeleportService.TeleportInitFailed:Connect(function(player, result, message, placeId, options)
		local n = (failures[player] or 0) + 1
		failures[player] = n
		warn(string.format("[Match] teleport of %s did not start (%s): %s", player.Name, tostring(result), tostring(message)))
		if n < LobbyCfg.TeleportAttempts and placeId == GameCfg.Places.Game and options then
			task.wait(LobbyCfg.TeleportRetrySeconds)
			if player.Parent and pcall(TeleportService.TeleportAsync, TeleportService, placeId, {player}, options) then return end
		end
		failures[player] = nil
		PartyService:Unlock(player, "lobby_launch_failed")
	end)
	Players.PlayerRemoving:Connect(function(player) failures[player] = nil end)
end

return MatchService
