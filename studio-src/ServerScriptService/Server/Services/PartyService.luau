-- Команды (решение 5). Без лобби (тест в Studio) каждый игрок — сам себе хост.
-- Веха 9: хоста и формат пати сообщает билет лобби, который сервер читает сам (LobbyLinkService).
-- Личное хранится в профиле игрока, общее — в записи команды хоста.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loader = require(ReplicatedStorage.Shared.Modules.Loader)
local PartyConfig = require(ReplicatedStorage.Shared.Config.Party)

local PartyService = {Priority = 90}
local DataService, LobbyLink
local hostOf = {}  -- [Player] = hostUserId
local members = {} -- [hostUserId] = {[Player] = true}
-- Событие «на сервере не осталось никого из команды» (аргумент — hostUserId). Его слушает HouseService
PartyService.TeamEmptied = Instance.new("BindableEvent")

function PartyService:Init()
	DataService = Loader.Get("DataService")
	local ok, link = pcall(Loader.Get, "LobbyLinkService")
	LobbyLink = ok and link or nil
end

-- Веха 9: TeleportData приходит через клиент и подделывается, поэтому хоста сообщает билет лобби,
-- который сервер прочитал сам. Без билета игрок — сам себе хост
function PartyService:ResolveHost(player)
	local arrival = LobbyLink and LobbyLink:Resolve(player)
	return arrival and arrival.host or player.UserId
end

-- Формат пати из билета лобби. Без лобби — nil, и сервер берёт формат по умолчанию
function PartyService:ResolveFormat(player)
	local arrival = LobbyLink and LobbyLink:Resolve(player)
	return arrival and arrival.format or nil
end

-- Сколько участников команды сейчас на сервере, не считая хоста: место хоста в его команде всегда свободно
local function guestCount(hostUserId)
	local n = 0
	for p in pairs(members[hostUserId] or {}) do
		if p.UserId ~= hostUserId then n += 1 end
	end
	return n
end

function PartyService:Join(player, hostUserId)
	self:Leave(player)
	local team, reason = DataService:LoadTeam(hostUserId)
	if not team then return false, reason end
	if not player.Parent then
		if not members[hostUserId] then
			task.spawn(function() DataService:ReleaseTeam(hostUserId) end)
		end
		return false, "left"
	end
	-- В команде не больше Party.MaxSize игроков (шаг 2.1 ДД). Лишний игрок получает отказ и играет в своей команде.
	-- Веха 9: на сервере из лобби предел — число мест в доме формата (SeatLimit ставит LobbyLinkService)
	if player.UserId ~= hostUserId and guestCount(hostUserId) >= (PartyService.SeatLimit or PartyConfig.MaxSize) - 1 then
		return false, "full"
	end
	hostOf[player] = hostUserId
	members[hostUserId] = members[hostUserId] or {}
	members[hostUserId][player] = true
	local key = tostring(player.UserId)
	local m = team.members[key] or {joined = os.time()}
	m.lastSeen = os.time()
	m.name = player.DisplayName
	team.members[key] = m
	local profile = DataService:GetProfile(player)
	if profile then profile.lastHost = hostUserId end
	player:SetAttribute("PartyHost", hostUserId)
	return true
end

-- Игрок вышел из команды: если на сервере никого из неё не осталось, запись сохраняется и освобождается
function PartyService:Leave(player)
	local host = hostOf[player]
	if not host then return end
	hostOf[player] = nil
	local set = members[host]
	if set then
		set[player] = nil
		if next(set) == nil then
			members[host] = nil
			task.spawn(function() DataService:ReleaseTeam(host) end)
			PartyService.TeamEmptied:Fire(host)
		end
	end
end

function PartyService:GetHost(player)
	return hostOf[player]
end

function PartyService:GetMembers(hostUserId)
	local list = {}
	for p in pairs(members[hostUserId] or {}) do table.insert(list, p) end
	return list
end

function PartyService:GetSize(player)
	local host = hostOf[player]
	return host and #self:GetMembers(host) or 1
end

function PartyService:GetHostName(player)
	local host = hostOf[player]
	if not host then return "" end
	local hp = Players:GetPlayerByUserId(host)
	if hp then return hp.DisplayName end
	local team = DataService:GetTeam(host)
	local m = team and team.members[tostring(host)]
	return m and m.name or tostring(host)
end

return PartyService
