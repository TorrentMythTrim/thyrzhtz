-- Вход и выход игрока: профиль, стартовый набор, команда, дом, отправка состояния клиенту
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)

local PlayerService = {Priority = 80}
local DataService, PartyService, InventoryService, HouseService, DefenseService, LobbyLink
local queued = {}

function PlayerService:Init()
	DataService = Loader.Get("DataService")
	PartyService = Loader.Get("PartyService")
	InventoryService = Loader.Get("InventoryService")
	HouseService = Loader.Get("HouseService")
	DefenseService = Loader.Get("DefenseService")
	LobbyLink = Loader.Get("LobbyLinkService")
end

-- Отправить клиенту актуальное состояние (не чаще раза за кадр)
function PlayerService:Push(player)
	if queued[player] then return end
	queued[player] = true
	task.defer(function()
		queued[player] = nil
		if not player.Parent then return end
		local profile = DataService:GetProfile(player)
		if not profile then return end
		local host = PartyService:GetHost(player)
		Net.Fire(player, "Snapshot", {
			profile = profile,
			team = host and DataService:GetTeam(host) or nil,
			host = host or 0,
			hostName = PartyService:GetHostName(player),
			partySize = PartyService:GetSize(player),
		})
	end)
end

function PlayerService:PushTeam(hostUserId)
	for _, p in ipairs(PartyService:GetMembers(hostUserId)) do self:Push(p) end
end

local function onPlayerAdded(player)
	-- Веха 9: игра начинается с лобби (шаг 1.3 ДД). Сервер читает билет лобби; игрок без билета уходит в лобби.
	-- Профиль ещё не загружен, поэтому его блокировка не мешает загрузке на следующем сервере
	local arrival = LobbyLink:Resolve(player)
	if arrival.redirect and LobbyLink:Redirect(player) then return end
	local profile = DataService:LoadProfile(player)
	if not profile then return end
	InventoryService:EnsureStarterKit(player)
	InventoryService:EnsureHotbar(player)
	local ok, reason = PartyService:Join(player, PartyService:ResolveHost(player))
	if not ok and player.Parent and PartyService:ResolveHost(player) ~= player.UserId then
		ok, reason = PartyService:Join(player, player.UserId) -- запись хоста недоступна: играем в своей
	end
	if not ok then
		if player.Parent then player:Kick("Team data unavailable: " .. tostring(reason)) end
		return
	end
	HouseService:Settle(player)
	LobbyLink:QueueBeat() -- веха 9: лобби узнаёт, что дом занят
	-- Если игрок прилетел с другого сервера по «Зову о помощи» (шаг 5.4 ДД), переносим к защищающемуся участку.
	-- Веха 9: о помощнике сообщает его билет, а не TeleportData
	local helpHost = arrival.helpHost
	if helpHost and helpHost ~= PartyService:GetHost(player) and DefenseService then
		task.spawn(function()
			task.wait(0.3)
			if player.Parent then DefenseService:TeleportHelperToHost(player, helpHost) end
		end)
	end
	player:SetAttribute("Loaded", true)
	PlayerService:Push(player)
	print(string.format("[Player] %s загружен: сессия %d, монеты %d, хост %d, дом %s, режим данных %s",
		player.Name, profile.stats.sessions, profile.currencies.coins, PartyService:GetHost(player), tostring(player:GetAttribute("Plot")),
		DataService:IsMemoryMode() and "memory" or "datastore"))
end

function PlayerService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end
	Players.PlayerRemoving:Connect(function(player)
		queued[player] = nil
		PartyService:Leave(player)
	end)
end

return PlayerService
