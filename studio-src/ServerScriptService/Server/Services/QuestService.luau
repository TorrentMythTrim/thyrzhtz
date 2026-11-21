-- Elder quests, village restoration and rescued residents (milestone 8, design doc 7.1–7.2, 1.5, 2.4).
-- All progress lives in the team record (quests, village, acts), so it is shared inside a team and independent
-- between teams. The chain and the numbers are in Config.Act1.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Locale = require(Shared.Modules.Locale)
local Act1 = require(Shared.Config.Act1)
local Items = require(Shared.Config.Items)

local QuestService = {Priority = 30}
local DataService, PartyService, PlayerService, InventoryService, EconomyService

local function langOf(player)
	local p = DataService:GetProfile(player)
	return p and p.settings and p.settings.language or Locale.Default
end

local function teamOf(player)
	local host = PartyService:GetHost(player)
	return host and DataService:GetTeam(host) or nil, host
end

local function isNear(player, pos)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and pos ~= nil and (root.Position - pos).Magnitude <= Act1.TalkDistance
end

-- The schema has the three tables; the keys milestone 8 keeps inside them appear on first use
local function prepare(team)
	team.quests = team.quests or {}
	team.quests.active = team.quests.active or {}
	team.quests.completed = team.quests.completed or {}
	team.village = team.village or {}
	team.village.rescued = team.village.rescued or {}
	team.village.restoration = tonumber(team.village.restoration) or 0
	team.acts = team.acts or {}
	return team
end

-- Portals follow the restoration level: the raid portal first, then the portal to the next land (design doc 7.2).
-- Returns the notices for what has just opened
function QuestService.SyncPortals(team)
	prepare(team)
	local R = Act1.Restoration
	local opened = {}
	if team.village.restoration >= R.BossPortalAt and not team.acts.bossPortal then
		team.acts.bossPortal = true
		table.insert(opened, "portal_raid_opened")
	end
	if team.village.restoration >= R.NextPortalAt and not team.acts.nextPortal then
		team.acts.nextPortal = true
		table.insert(opened, "portal_next_opened")
	end
	return opened
end

-- Where the team is in the chain: the quest, whether it is taken, each objective as have and need
function QuestService.Status(team)
	prepare(team)
	local quest, index = Act1.CurrentQuest(team)
	if not quest then return {finished = true} end
	local state = team.quests.active[quest.id]
	local objectives, ready = {}, state ~= nil
	for i in ipairs(quest.objectives) do
		local have, need = Act1.ObjectiveProgress(team, quest, i, state)
		objectives[i] = {have = have, need = need}
		if have < need then ready = false end
	end
	return {quest = quest, index = index, active = state ~= nil, objectives = objectives, ready = ready}
end

function QuestService.Resident(id)
	for _, resident in ipairs(Act1.Residents) do
		if resident.id == id then return resident end
	end
	return nil
end

-- Rescued residents are the ones who trade at the village stall (design doc 6.5)
function QuestService.Traders(team)
	local list = {}
	local rescued = team and team.village and team.village.rescued or {}
	for _, resident in ipairs(Act1.Residents) do
		if rescued[resident.id] then table.insert(list, resident.id) end
	end
	return list
end

function QuestService:ElderPosition()
	local map = workspace:FindFirstChild("Map")
	local village = map and map:FindFirstChild("Village")
	local elder = village and village:FindFirstChild("Elder")
	return elder and elder:GetPivot().Position or nil
end

function QuestService:CaptivePosition(residentId)
	local folder = workspace:FindFirstChild("Act1")
	local captives = folder and folder:FindFirstChild("Captives")
	local captive = captives and captives:FindFirstChild("Captive_" .. tostring(residentId))
	return captive and captive:GetPivot().Position or nil
end

-- Take the current quest of the chain. ignoreDistance is for tests
function QuestService:Accept(player, ignoreDistance)
	local team, host = teamOf(player)
	if not team then return false, "no_team" end
	if not ignoreDistance and not isNear(player, self:ElderPosition()) then
		Net.Fire(player, "Notify", "quest_too_far")
		return false, "too_far"
	end
	local status = QuestService.Status(team)
	if status.finished then return false, "finished" end
	if status.active then return false, "active" end
	local progress = {}
	for i in ipairs(status.quest.objectives) do progress[i] = 0 end
	-- the team size is fixed when the quest is taken, so the amounts do not move while it is being done
	team.quests.active[status.quest.id] = {
		size = Act1.TeamSize(PartyService:GetSize(player)),
		progress = progress,
		acceptedAt = os.time(),
	}
	for _, p in ipairs(PartyService:GetMembers(host)) do
		Net.Fire(p, "Notify", "quest_accepted", Locale.T(langOf(p), "quest_" .. status.quest.id .. "_title"))
	end
	PlayerService:PushTeam(host)
	return true, status.quest.id
end

-- Hand the elder what the player carries for the "deliver" objectives. Any member can bring a part.
-- Returns how many items were taken
function QuestService:Deliver(player, ignoreDistance)
	local team, host = teamOf(player)
	if not team then return 0, "no_team" end
	if not ignoreDistance and not isNear(player, self:ElderPosition()) then
		Net.Fire(player, "Notify", "quest_too_far")
		return 0, "too_far"
	end
	local status = QuestService.Status(team)
	if not status.active then return 0, "not_active" end
	local state = team.quests.active[status.quest.id]
	local taken = 0
	for i, objective in ipairs(status.quest.objectives) do
		if objective.type == "deliver" then
			local left = status.objectives[i].need - status.objectives[i].have
			local give = math.min(left, InventoryService:Count(player, objective.item))
			if give > 0 and InventoryService:Take(player, objective.item, give) then
				state.progress[i] = (tonumber(state.progress[i]) or 0) + give
				taken += give
				Net.Fire(player, "Notify", "quest_delivered", Locale.Name(langOf(player), Items.Defs[objective.item].name), give)
			end
		end
	end
	if taken > 0 then PlayerService:PushTeam(host) end
	return taken
end

-- Hand the quest in: deliver what is carried and, if every objective is met, finish the quest.
-- A finished quest restores the village by one step
function QuestService:TurnIn(player, ignoreDistance)
	local team, host = teamOf(player)
	if not team then return false, "no_team" end
	local _, why = self:Deliver(player, ignoreDistance)
	if why == "too_far" or why == "not_active" then return false, why end
	local status = QuestService.Status(team)
	if not status.ready then
		Net.Fire(player, "Notify", "quest_not_ready")
		return false, "not_ready"
	end
	local quest = status.quest
	local rewardItems = quest.rewards and quest.rewards.items or {}
	if next(rewardItems) ~= nil and not InventoryService:CanExchange(player, {}, rewardItems) then
		Net.Fire(player, "Notify", "farm_bag_full")
		return false, "bag_full"
	end
	team.quests.active[quest.id] = nil
	team.quests.completed[quest.id] = os.time()
	for itemId, count in pairs(rewardItems) do
		if InventoryService:Give(player, itemId, count) then
			Net.Fire(player, "Notify", "item_given", Locale.Name(langOf(player), Items.Defs[itemId].name), count)
		end
	end
	local R = Act1.Restoration
	team.village.restoration = math.min(R.Max, team.village.restoration + 1)
	local opened = QuestService.SyncPortals(team)
	local page = false
	if team.village.restoration >= R.Max and not team.acts.ancestorPage then
		-- design doc 7.2: the page of the ancestors for the fully restored village
		team.acts.ancestorPage = os.time()
		page = true
	end
	for _, p in ipairs(PartyService:GetMembers(host)) do
		Net.Fire(p, "Notify", "quest_done", Locale.T(langOf(p), "quest_" .. quest.id .. "_title"))
		Net.Fire(p, "Notify", "village_restored_step", team.village.restoration, R.Max)
		for _, key in ipairs(opened) do Net.Fire(p, "Notify", key) end
		if page then Net.Fire(p, "Notify", "ancestor_page") end
		if Act1.QuestXp > 0 then EconomyService:AddXp(p, Act1.QuestXp) end
	end
	PlayerService:PushTeam(host)
	return true, quest.id
end

-- A resident found in the Old Garden goes back to the village (design doc 1.5)
function QuestService:Rescue(player, residentId, ignoreDistance)
	local team, host = teamOf(player)
	local resident = QuestService.Resident(residentId)
	if not (team and resident) then return false, "unknown" end
	prepare(team)
	if team.village.rescued[resident.id] then return false, "already" end
	if not ignoreDistance and not isNear(player, self:CaptivePosition(resident.id)) then return false, "too_far" end
	team.village.rescued[resident.id] = os.time()
	for _, p in ipairs(PartyService:GetMembers(host)) do
		Net.Fire(p, "Notify", "resident_rescued", Locale.Name(langOf(p), resident.name))
	end
	PlayerService:PushTeam(host)
	return true
end

-- Called by MonsterService for every monster a player kills
function QuestService:OnMonsterKilled(killer, mob)
	local team, host = teamOf(killer)
	if not team then return end
	local status = QuestService.Status(team)
	if not status.active then return end
	local state = team.quests.active[status.quest.id]
	local changed = false
	for i, objective in ipairs(status.quest.objectives) do
		if objective.type == "kill" and objective.monster == mob.id and status.objectives[i].have < status.objectives[i].need then
			state.progress[i] = (tonumber(state.progress[i]) or 0) + 1
			changed = true
		end
	end
	if changed then PlayerService:PushTeam(host) end
end

local PORTALS = {raid = "PortalRaid", next = "PortalNext"}

function QuestService:PortalPosition(kind)
	local map = workspace:FindFirstChild("Map")
	local village = map and map:FindFirstChild("Village")
	local portal = village and village:FindFirstChild(PORTALS[kind] or "")
	return portal and portal:GetPivot().Position or nil
end

-- kind "raid": the boss portal. kind "next": the portal to the next land; until Act 2 exists it only says so
-- (technical plan, milestone 8, item 3)
function QuestService:UsePortal(player, kind, ignoreDistance)
	local team = teamOf(player)
	if not team then return false, "no_team" end
	prepare(team)
	if not PORTALS[kind] then return false, "unknown" end
	if not ignoreDistance and not isNear(player, self:PortalPosition(kind)) then return false, "too_far" end
	if kind == "raid" then
		if not team.acts.bossPortal then
			Net.Fire(player, "Notify", "portal_closed")
			return false, "closed"
		end
		local ok, boss = pcall(Loader.Get, "BossService")
		if not ok then return false, "no_boss_service" end
		return boss:Enter(player)
	elseif kind == "next" then
		if not team.acts.nextPortal then
			Net.Fire(player, "Notify", "portal_closed")
			return false, "closed"
		end
		Net.Fire(player, "Notify", "portal_next_stub")
		return true, "stub"
	end
	return false, "unknown"
end

function QuestService:Init()
	DataService = Loader.Get("DataService")
	PartyService = Loader.Get("PartyService")
	PlayerService = Loader.Get("PlayerService")
	InventoryService = Loader.Get("InventoryService")
	EconomyService = Loader.Get("EconomyService")
	local ok, err = pcall(function() require(ServerStorage.Modules.Act1Models).Ensure() end)
	if not ok then warn("[Quest] Act 1 models: " .. tostring(err)) end
end

function QuestService:Start()
	local function hook(d)
		if not d:IsA("ProximityPrompt") then return end
		if d.Name == "ElderPrompt" then
			d.Triggered:Connect(function(player) Net.Fire(player, "Act1Event", "elder") end)
		elseif d.Name == "RaidPrompt" then
			d.Triggered:Connect(function(player) self:UsePortal(player, "raid") end)
		elseif d.Name == "NextPrompt" then
			d.Triggered:Connect(function(player) self:UsePortal(player, "next") end)
		elseif d.Name == "RescuePrompt" then
			d.Triggered:Connect(function(player)
				local captive = d:FindFirstAncestorWhichIsA("Model")
				self:Rescue(player, captive and captive:GetAttribute("Resident"))
			end)
		end
	end
	local map = workspace:FindFirstChild("Map")
	for _, container in ipairs({map and map:FindFirstChild("Village"), workspace:FindFirstChild("Act1")}) do
		for _, d in ipairs(container:GetDescendants()) do hook(d) end
	end
	Net.On("Act1Action", 5, function(player, action)
		if action == "accept" then
			self:Accept(player)
		elseif action == "turn_in" then
			self:TurnIn(player)
		end
	end)
end

return QuestService
