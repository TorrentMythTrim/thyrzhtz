-- Parties in the lobby (milestone 9, design doc 2.1): players gather a party of 1, 2, 3 or 4 Guardians here and
-- only then go to the game. Every player always has a party; alone, it is a solo party that the player leads.
-- The leader becomes the host of the team in the game, and the shared progress is the host's team record
-- (decision 5). The format is the size of the party (design doc 2.2), so a party sets out only when it is full.
-- The client sends intentions only; every rule is checked here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local PartyCfg = require(Shared.Config.Party)
local LobbyCfg = require(Shared.Config.Lobby)

local PartyService = {Priority = 80}
PartyService.Clock = os.clock -- tests move time by replacing this
local MatchService
local present = {} -- [player] = true: everyone in the lobby
local partyOf = {} -- [player] = party {leader, format, members, launching}
local invites = {} -- [invitee] = {[leader] = expiresAt}
local rejoin = {}  -- [player] = the team session the player can go back to
local queued = false

-- Tests use stand-in players (tables); they get no network messages
local function isReal(player)
	return typeof(player) == "Instance"
end

local function tell(player, key, ...)
	if isReal(player) and player.Parent then Net.Fire(player, "Notify", key, ...) end
end

local function refuse(player, reason)
	tell(player, "lobby_err_" .. reason)
	return false, reason
end

local function nameOf(player)
	return player.DisplayName or player.Name
end

local function soloParty(player)
	local party = {leader = player, format = PartyCfg.Formats[1].id, members = {player}, launching = false}
	partyOf[player] = party
	return party
end

function PartyService.Format(id)
	for _, f in ipairs(PartyCfg.Formats) do
		if f.id == id then return f end
	end
	return nil
end

function PartyService:Init()
	MatchService = Loader.Get("MatchService")
end

function PartyService:Get(player)
	return partyOf[player]
end

-- A player came into the lobby
function PartyService:Enter(player)
	if present[player] then return partyOf[player] end
	present[player] = true
	invites[player] = {}
	soloParty(player)
	self:Changed()
	return partyOf[player]
end

-- A player left the lobby: to the game or out of the experience
function PartyService:Exit(player)
	if not present[player] then return end
	self:Leave(player, true)
	present[player], partyOf[player], invites[player], rejoin[player] = nil, nil, nil, nil
	for _, set in pairs(invites) do set[player] = nil end
	self:Changed()
end

-- Leave the party. The leader is the host of the team, so a party without its leader is disbanded.
-- gone: the player is leaving the lobby and gets no party of their own
function PartyService:Leave(player, gone)
	local party = partyOf[player]
	if not party then return false, "unknown" end
	if party.launching and not gone then return refuse(player, "launching") end
	if #party.members == 1 then return false, "alone" end
	if party.launching then
		-- the party is on its way: its members leave the lobby one after another, nobody is told anything
		table.remove(party.members, table.find(party.members, player))
	elseif party.leader == player then
		for _, m in ipairs(party.members) do
			if m ~= player then
				soloParty(m)
				tell(m, "lobby_disbanded")
			end
		end
	else
		table.remove(party.members, table.find(party.members, player))
		for _, m in ipairs(party.members) do tell(m, "lobby_left", nameOf(player)) end
	end
	if not gone then soloParty(player) end
	self:Changed()
	return true
end

-- The leader chooses how many Guardians the party is for
function PartyService:SetFormat(player, formatId)
	local party, f = partyOf[player], PartyService.Format(formatId)
	if not (party and f) then return false, "unknown" end
	if party.leader ~= player then return refuse(player, "not_leader") end
	if party.launching then return refuse(player, "launching") end
	if #party.members > f.size then return refuse(player, "too_many") end
	party.format = f.id
	self:Changed()
	return true
end

function PartyService:Invite(player, target)
	local party = partyOf[player]
	if not party or party.leader ~= player then return refuse(player, "not_leader") end
	if party.launching then return refuse(player, "launching") end
	if not target or target == player or not present[target] then return refuse(player, "unknown") end
	if #party.members >= PartyService.Format(party.format).size then return refuse(player, "full") end
	if #partyOf[target].members > 1 then return refuse(player, "busy") end
	local now, waiting = PartyService.Clock(), 0
	for _, set in pairs(invites) do
		if set[player] and set[player] > now then waiting += 1 end
	end
	if waiting >= LobbyCfg.InvitesPerParty then return refuse(player, "too_many_invites") end
	invites[target][player] = now + LobbyCfg.InviteSeconds
	tell(target, "lobby_invited", nameOf(player))
	self:Changed()
	return true
end

-- The invited player accepts or declines the invitation of this leader
function PartyService:Answer(player, leader, accept)
	local set = invites[player]
	local expires = set and leader and set[leader]
	if not expires then return refuse(player, "expired") end
	local party = partyOf[leader]
	if not accept then
		set[leader] = nil
		tell(leader, "lobby_declined", nameOf(player))
		self:Changed()
		return true, "declined"
	end
	if expires <= PartyService.Clock() or not party or party.leader ~= leader then
		set[leader] = nil
		self:Changed()
		return refuse(player, "expired")
	end
	if party.launching then return refuse(player, "launching") end
	if #party.members >= PartyService.Format(party.format).size then return refuse(player, "full") end
	if #partyOf[player].members > 1 then return refuse(player, "leave_first") end
	invites[player] = {}
	for _, other in pairs(invites) do other[player] = nil end -- what the player sent as the leader of their own party
	for _, m in ipairs(party.members) do tell(m, "lobby_joined", nameOf(player)) end
	partyOf[player] = party
	table.insert(party.members, player)
	self:Changed()
	return true, "joined"
end

function PartyService:Kick(player, target)
	local party = partyOf[player]
	if not party or party.leader ~= player then return refuse(player, "not_leader") end
	if party.launching then return refuse(player, "launching") end
	if not target or target == player or partyOf[target] ~= party then return refuse(player, "unknown") end
	table.remove(party.members, table.find(party.members, target))
	soloParty(target)
	tell(target, "lobby_kicked")
	self:Changed()
	return true
end

-- The party did not leave after all. If its leader has already gone, the others get parties of their own
function PartyService:Unlock(player, key)
	local party = partyOf[player]
	if not (party and party.launching) then return false end
	party.launching = false
	local keep = present[party.leader] and partyOf[party.leader] == party
	for _, m in ipairs(table.clone(party.members)) do
		if not keep then soloParty(m) end
		tell(m, key)
	end
	self:Changed()
	return true
end

-- The leader sends the party to the game. The server it goes to has the format of the party
function PartyService:SetOut(player)
	local party = partyOf[player]
	if not party or party.leader ~= player then return refuse(player, "not_leader") end
	if party.launching then return refuse(player, "launching") end
	local f = PartyService.Format(party.format)
	if #party.members ~= f.size then
		tell(player, "lobby_need_full", #party.members, f.size)
		return false, "not_full"
	end
	party.launching = true
	self:Changed()
	local ok, reason = MatchService:Launch(table.clone(party.members), player, f)
	if not ok then
		self:Unlock(player, "lobby_launch_failed")
		return false, reason
	end
	-- the members leave the lobby one by one; whoever is still here after a while gets the party back
	task.delay(LobbyCfg.LaunchLockSeconds, function()
		for _, m in ipairs(party.members) do
			if present[m] and partyOf[m] == party then
				self:Unlock(m, "lobby_launch_failed")
				break
			end
		end
	end)
	return true
end

-- MatchService found the team this player was playing with: it is still on a game server
function PartyService:OfferRejoin(player, session)
	if not present[player] then return end
	rejoin[player] = session
	self:Changed()
end

function PartyService:Rejoin(player)
	local party = partyOf[player]
	if not (party and rejoin[player]) then return false, "gone" end
	if #party.members > 1 then return refuse(player, "leave_first") end
	if party.launching then return refuse(player, "launching") end
	party.launching = true
	self:Changed()
	local ok, reason = MatchService:Rejoin(player)
	if not ok then
		party.launching = false
		if reason == "gone" then
			rejoin[player] = nil
			tell(player, "lobby_rejoin_gone")
		else
			tell(player, "lobby_launch_failed")
		end
		self:Changed()
	end
	return ok, reason
end

-- What one player sees: their party, the invitations they got and the others in the lobby
function PartyService:Snapshot(player)
	local party = partyOf[player]
	if not party then return nil end
	local now = PartyService.Clock()
	local members = {}
	for i, m in ipairs(party.members) do members[i] = {id = m.UserId, name = nameOf(m)} end
	local got = {}
	for leader, expires in pairs(invites[player] or {}) do
		if expires > now and partyOf[leader] then
			table.insert(got, {id = leader.UserId, name = nameOf(leader), format = partyOf[leader].format})
		end
	end
	table.sort(got, function(a, b) return a.id < b.id end)
	local others = {}
	for other in pairs(present) do
		if other ~= player and partyOf[other] ~= party then
			table.insert(others, {
				id = other.UserId, name = nameOf(other), size = #partyOf[other].members,
				invited = (invites[other][player] or 0) > now,
			})
		end
	end
	table.sort(others, function(a, b) return a.id < b.id end)
	local session = rejoin[player]
	return {
		party = {leader = party.leader.UserId, format = party.format, members = members, launching = party.launching},
		invites = got,
		players = others,
		rejoin = session and {hostName = tostring(session.hostName or session.host), format = session.format} or nil,
	}
end

-- Send everyone their view of the lobby, at most once a frame
function PartyService:Changed()
	if queued then return end
	queued = true
	task.defer(function()
		queued = false
		for player in pairs(present) do
			if isReal(player) and player.Parent then Net.Fire(player, "LobbyState", self:Snapshot(player)) end
		end
	end)
end

function PartyService:Start()
	local function entered(player)
		self:Enter(player)
		MatchService:Greet(player)
	end
	Players.PlayerAdded:Connect(entered)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(entered, p) end
	Players.PlayerRemoving:Connect(function(player) self:Exit(player) end)

	local function byId(id)
		return Players:GetPlayerByUserId(tonumber(id) or 0)
	end
	Net.On("LobbyAction", 6, function(player, action, a)
		if not present[player] then return end
		if action == "format" then
			self:SetFormat(player, a)
		elseif action == "invite" then
			self:Invite(player, byId(a))
		elseif action == "accept" or action == "decline" then
			self:Answer(player, byId(a), action == "accept")
		elseif action == "leave" then
			self:Leave(player)
		elseif action == "kick" then
			self:Kick(player, byId(a))
		elseif action == "start" then
			self:SetOut(player)
		elseif action == "rejoin" then
			self:Rejoin(player)
		elseif action == "refresh" then
			Net.Fire(player, "LobbyState", self:Snapshot(player))
		end
	end)

	-- invitations that nobody answered go away
	while true do
		task.wait(1)
		local now, changed = PartyService.Clock(), false
		for _, set in pairs(invites) do
			for leader, expires in pairs(set) do
				if expires <= now then
					set[leader] = nil
					changed = true
				end
			end
		end
		if changed then self:Changed() end
	end
end

return PartyService
