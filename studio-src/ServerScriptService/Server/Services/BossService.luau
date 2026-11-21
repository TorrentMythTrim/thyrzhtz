-- Boss portal of Act 1 (milestone 8, design doc 1.3, 1.5, 4.5, 7.4): every team gets its own run — stage rooms
-- with loot and lore, then the Rotten Stump-Lord. The stump and its growths are ordinary MonsterService mobs
-- (Monsters.Summons), so every weapon and ability works on them; what they do is attached with
-- MonsterBehaviors.Extend and driven from here. The numbers are in Config.Act1.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Locale = require(Shared.Modules.Locale)
local Act1 = require(Shared.Config.Act1)
local Items = require(Shared.Config.Items)
local Behaviors = require(ServerStorage.Modules.MonsterBehaviors)
local Models = require(ServerStorage.Modules.Act1Models)

local BossService = {Priority = 29}
local DataService, PartyService, PlayerService, InventoryService, MonsterService, CombatService
local rng = Random.new()
local runs = {} -- [hostUserId] = run
local slots = {} -- [slot] = hostUserId
local RAID_ATTRIBUTES = {"RaidState", "RaidStage", "RaidStages", "RaidGrowths"}

local function langOf(player)
	local p = DataService:GetProfile(player)
	return p and p.settings and p.settings.language or Locale.Default
end

local function alive(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return player.Parent ~= nil and hum ~= nil and hum.Health > 0
end

local function lootText(lang, loot)
	local parts = {}
	for itemId, count in pairs(loot) do
		local def = Items.Defs[itemId]
		table.insert(parts, (def and Locale.Name(lang, def.name) or itemId) .. " x" .. count)
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function portalsFolder()
	local act = workspace:FindFirstChild("Act1")
	if not act then
		act = Instance.new("Folder")
		act.Name = "Act1"
		act.Parent = workspace
	end
	local folder = act:FindFirstChild("Portals")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Portals"
		folder.Parent = act
	end
	return folder
end

-- In front of the raid portal in the village
local function villageExit()
	local map = workspace:FindFirstChild("Map")
	local village = map and map:FindFirstChild("Village")
	local portal = village and village:FindFirstChild("PortalRaid")
	local surface = portal and portal:FindFirstChild("Surface")
	if surface then return surface.CFrame * CFrame.new(0, -5, -9) end
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	return (spawn and spawn.CFrame or CFrame.new()) + Vector3.new(0, 4, 0)
end

-- A point of a room: x across the room, fraction of the way from its near wall to its far wall
local function roomPoint(run, room, x, fraction)
	return (run.origin * CFrame.new(x, 0, room.z0 + (room.z1 - room.z0) * fraction)).Position
end

-- Is the point inside the strip that starts at origin, runs along dir for length and is width wide? Height is ignored
function BossService.InLine(point, origin, dir, length, width)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then return false end
	flat = flat.Unit
	local rel = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	local along = rel:Dot(flat)
	if along < 0 or along > length then return false end
	return (rel - flat * along).Magnitude <= width / 2
end

-- Arenas hang one above another over the middle of the map, inside its X and Z bounds
function BossService.Origin(slot)
	local P = Act1.Portal
	local _, depth = Models.ArenaLayout()
	return CFrame.new(P.Center.X, P.BaseHeight + P.HeightStep * (slot - 1), P.Center.Y - depth / 2)
end

function BossService:GetRun(hostUserId)
	return runs[hostUserId]
end

function BossService:RunOf(player)
	for _, run in pairs(runs) do
		if run.players[player] then return run end
	end
	return nil
end

function BossService:AliveInZone(run, id)
	local n = 0
	for _, mob in ipairs(MonsterService:GetAll()) do
		if mob.zone == run.zone and (id == nil or mob.id == id) then n += 1 end
	end
	return n
end

-- What the client shows on its raid line
function BossService:SyncPlayers(run)
	local state = "stage"
	if run.state == "won" then
		state = "won"
	elseif run.boss then
		state = run.heartOpen and "heart" or "boss"
	end
	for player in pairs(run.players) do
		player:SetAttribute("RaidState", state)
		player:SetAttribute("RaidStage", run.stage)
		player:SetAttribute("RaidStages", #Act1.Portal.Stages)
		player:SetAttribute("RaidGrowths", run.growthsLeft or Act1.Boss.Growths)
	end
end

function BossService:Teleport(player, cf)
	if not player.Character then return false end
	if workspace.StreamingEnabled then
		pcall(player.RequestStreamAroundAsync, player, cf.Position, 5)
	end
	local char = player.Character
	if not (char and char.Parent) then return false end
	char:PivotTo(cf)
	return true
end

function BossService:SetHeart(run, open)
	run.heartOpen = open
	local m = run.boss and run.boss.model
	if not (m and m.Parent) then return end
	m:SetAttribute("HeartOpen", open)
	local heart, cover = m:FindFirstChild("Heart"), m:FindFirstChild("HeartCover")
	if heart then heart.Transparency = open and 0 or 1 end
	for _, d in ipairs(cover and cover:GetChildren() or {}) do
		if d:IsA("BasePart") then d.Transparency = open and 1 or 0 end
	end
end

function BossService:SpawnBoss(run, room)
	local B = Act1.Boss
	local center = roomPoint(run, room, 0, 0.6)
	local boss = MonsterService:Spawn(B.Id, center, {zone = run.zone, leash = 9999})
	if not boss then
		warn("[Boss] no template for " .. B.Id)
		return false
	end
	boss.x.run = run
	boss.x.home = boss.model:GetPivot()
	run.boss = boss
	run.growths = {}
	for i = 1, B.Growths do
		-- one behind the stump, the others in front of it to the left and to the right
		local a = math.rad(90 + (i - 1) * 360 / B.Growths)
		local g = MonsterService:Spawn(B.GrowthId, center + Vector3.new(math.cos(a) * 20, 0, math.sin(a) * 20), {zone = run.zone, leash = 9999})
		if g then
			g.x.home = g.model:GetPivot()
			table.insert(run.growths, g)
		end
	end
	run.growthsLeft = #run.growths
	run.nextRoot = run.clock + B.Root.Interval
	run.nextSummon = run.clock + B.Summon.Interval
	self:SetHeart(run, #run.growths == 0)
	return true
end

function BossService:SpawnStage(run)
	local room = run.rooms[run.stage]
	if room.boss then
		self:SpawnBoss(run, room)
	else
		local n = 0
		for _, entry in ipairs(Act1.Portal.Stages[run.stage].monsters) do
			for _ = 1, entry[2] do
				local pos = roomPoint(run, room, (n % 4 - 1.5) * 9, 0.55 + 0.14 * math.floor(n / 4))
				n += 1
				if not MonsterService:Spawn(entry[1], pos, {zone = run.zone, leash = 60}) then
					warn("[Boss] cannot spawn " .. tostring(entry[1]))
				end
			end
		end
	end
	self:SyncPlayers(run)
end

function BossService:CreateRun(hostUserId)
	local slot
	for i = 1, Act1.Portal.MaxRuns do
		if not slots[i] then
			slot = i
			break
		end
	end
	if not slot then return nil end
	local run = {
		host = hostUserId, slot = slot, zone = "portal_" .. hostUserId, origin = BossService.Origin(slot),
		rooms = Models.ArenaLayout(), stage = 1, state = "fight", clock = os.clock(),
		players = {}, lines = {}, growths = {}, warnAt = {},
	}
	run.model = Models.Arena(run.origin, "Portal_" .. hostUserId)
	run.model.Parent = portalsFolder()
	local leave = run.model:FindFirstChild("LeavePrompt", true)
	if leave then
		leave.Triggered:Connect(function(player) self:Leave(player, "exit") end)
	end
	slots[slot] = hostUserId
	runs[hostUserId] = run
	self:SpawnStage(run)
	return run
end

function BossService:Close(run)
	if runs[run.host] ~= run then return end
	runs[run.host] = nil
	slots[run.slot] = nil
	for player in pairs(run.players) do
		for _, name in ipairs(RAID_ATTRIBUTES) do player:SetAttribute(name, nil) end
		player:SetAttribute("InBossPortal", nil)
	end
	run.players = {}
	MonsterService:ClearAll(run.zone)
	if run.model then run.model:Destroy() end
end

-- The team's raid portal is open: go in. Members of one team share a run and join it at its current stage
function BossService:Enter(player)
	local host = PartyService:GetHost(player)
	local team = host and DataService:GetTeam(host)
	if not (team and team.acts and team.acts.bossPortal) then return false, "closed" end
	if not alive(player) then return false, "dead" end
	if self:RunOf(player) then return false, "inside" end
	local run = runs[host]
	if run and run.state == "won" then return false, "closing" end
	if not run then
		run = self:CreateRun(host)
		if not run then
			Net.Fire(player, "Notify", "raid_busy")
			return false, "busy"
		end
	end
	run.players[player] = true
	player:SetAttribute("InBossPortal", true)
	self:SyncPlayers(run)
	local at = roomPoint(run, run.rooms[run.stage], 0, 0) + Vector3.new(0, 4, 5)
	self:Teleport(player, CFrame.lookAt(at, at + Vector3.zAxis))
	return true
end

-- reason "exit": walked out or won — the portal loot goes to the bag. Anything else (death, left the game):
-- what was found inside is lost (design doc 4.5). The run closes when nobody is left in it
function BossService:Leave(player, reason)
	local run = self:RunOf(player)
	if not run then return false end
	run.players[player] = nil
	for _, name in ipairs(RAID_ATTRIBUTES) do player:SetAttribute(name, nil) end
	local loot = CombatService:GetPortalLoot(player)
	if reason == "exit" and player.Parent then
		local got, left = {}, false
		for itemId, count in pairs(loot or {}) do
			if InventoryService:Give(player, itemId, count) then
				got[itemId] = count
				loot[itemId] = nil
			else
				left = true -- no room: it stays in the portal loot for the next time
			end
		end
		if next(got) ~= nil then Net.Fire(player, "Notify", "raid_loot_banked", lootText(langOf(player), got)) end
		if left then Net.Fire(player, "Notify", "farm_bag_full") end
		player:SetAttribute("InBossPortal", nil)
		self:Teleport(player, villageExit())
		Net.Fire(player, "Notify", "raid_left")
		PlayerService:Push(player)
	else
		if loot then table.clear(loot) end
		-- CombatService reads the attribute when the character dies, so it is cleared a moment later
		task.delay(1.5, function()
			if player.Parent and not self:RunOf(player) then player:SetAttribute("InBossPortal", nil) end
		end)
	end
	if next(run.players) == nil then
		self:Close(run)
	else
		self:SyncPlayers(run)
	end
	return true
end

function BossService:ClearStage(run)
	local stage = Act1.Portal.Stages[run.stage]
	local loot = stage.loot or {}
	for player in pairs(run.players) do
		for itemId, count in pairs(loot) do CombatService:AddPortalLoot(player, itemId, count) end
		Net.Fire(player, "Notify", "raid_stage_clear", lootText(langOf(player), loot))
	end
	local team = DataService:GetTeam(run.host)
	if stage.lore and team then
		team.acts.lore = team.acts.lore or {}
		if not team.acts.lore[stage.lore] then
			team.acts.lore[stage.lore] = os.time()
			for player in pairs(run.players) do Net.Fire(player, "Act1Event", "lore", stage.lore) end
			PlayerService:PushTeam(run.host)
		end
	end
	local barrier = run.model:FindFirstChild("Barrier_" .. run.stage)
	if barrier then barrier:Destroy() end
	run.stage += 1
	self:SpawnStage(run)
end

-- Roots along a straight line from the stump at the target: a warning strip first, the blow after Telegraph seconds
function BossService:CastRoot(run, now, target)
	local R = Act1.Boss.Root
	local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local from = run.boss.x.home.Position
	local dir = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	dir = dir.Magnitude > 1e-3 and dir.Unit or Vector3.new(0, 0, -1)
	local mid = from + dir * (R.Length / 2) + Vector3.new(0, 0.2, 0)
	local mark = Instance.new("Part")
	mark.Name = "RootWarning"
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.Size = Vector3.new(R.Width, 0.3, R.Length)
	mark.CFrame = CFrame.lookAt(mid, mid + dir)
	mark.Color = Color3.fromRGB(190, 60, 50)
	mark.Material = Enum.Material.Neon
	mark.Transparency = 0.55
	mark.Parent = run.model
	local line = {from = from, dir = dir, hitAt = now + R.Telegraph, mark = mark}
	table.insert(run.lines, line)
	return line
end

function BossService:Win(run, now)
	run.state = "won"
	run.exitAt = now + Act1.Portal.ExitSeconds
	for _, line in ipairs(run.lines) do line.mark:Destroy() end
	run.lines = {}
	MonsterService:ClearAll(run.zone)
	local team = DataService:GetTeam(run.host)
	if team then
		team.acts.bossDefeated = team.acts.bossDefeated or os.time()
		team.acts.bossKills = (tonumber(team.acts.bossKills) or 0) + 1
	end
	-- nothing is given for the victory itself: the boss reward is an open decision (technical plan, milestone 8, item 8)
	for player in pairs(run.players) do Net.Fire(player, "Notify", "raid_won") end
	self:SyncPlayers(run)
	PlayerService:PushTeam(run.host)
end

-- One step of a run. now is passed in so that tests can move time themselves
function BossService:StepRun(run, now)
	run.clock = now
	for player in pairs(run.players) do
		if not player.Parent then
			self:Leave(player, "gone")
		elseif not alive(player) then
			self:Leave(player, "death")
		end
	end
	if runs[run.host] ~= run then return end
	if run.state == "won" then
		if now >= run.exitAt then
			for player in pairs(run.players) do self:Leave(player, "exit") end
		end
		return
	end
	if not run.rooms[run.stage].boss then
		if self:AliveInZone(run) == 0 then self:ClearStage(run) end
		return
	end
	local boss = run.boss
	if not boss then return end
	if boss.hp <= 0 then
		self:Win(run, now)
		return
	end
	local B = Act1.Boss
	-- the stump and its growths stand where they are and cannot be stunned, put to sleep or pushed away
	local standing = {boss}
	for _, g in ipairs(run.growths) do
		if g.hp > 0 then table.insert(standing, g) end
	end
	for _, mob in ipairs(standing) do
		mob.stunUntil, mob.sleepUntil, mob.staggerUntil, mob.bindUntil = 0, 0, 0, 0
		if mob.model and mob.model.Parent and (mob.model:GetPivot().Position - mob.x.home.Position).Magnitude > 0.05 then
			mob.model:PivotTo(mob.x.home)
		end
	end
	local left = #standing - 1
	if left ~= run.growthsLeft then
		run.growthsLeft = left
		if left == 0 and not run.heartOpen then
			self:SetHeart(run, true)
			for player in pairs(run.players) do Net.Fire(player, "Notify", "raid_heart_open") end
		end
		self:SyncPlayers(run)
	end
	if now >= run.nextRoot then
		run.nextRoot = now + B.Root.Interval
		local targets = {}
		for player in pairs(run.players) do
			if alive(player) then table.insert(targets, player) end
		end
		if #targets > 0 then self:CastRoot(run, now, targets[rng:NextInteger(1, #targets)]) end
	end
	for i = #run.lines, 1, -1 do
		local line = run.lines[i]
		if now >= line.hitAt then
			table.remove(run.lines, i)
			for player in pairs(run.players) do
				local root = alive(player) and player.Character:FindFirstChild("HumanoidRootPart")
				if root and BossService.InLine(root.Position, line.from, line.dir, B.Root.Length, B.Root.Width) then
					CombatService:DamagePlayer(player, B.Root.Damage, nil)
				end
			end
			line.mark.Color = Color3.fromRGB(86, 62, 44)
			line.mark.Material = Enum.Material.Wood
			line.mark.Transparency = 0
			line.mark.Size = Vector3.new(B.Root.Width / 2, 2.4, B.Root.Length)
			Debris:AddItem(line.mark, 0.6)
		end
	end
	if now >= run.nextSummon then
		run.nextSummon = now + B.Summon.Interval
		local room = run.rooms[run.stage]
		for _ = 1, math.min(B.Summon.Count, B.Summon.MaxAlive - self:AliveInZone(run, B.SproutId)) do
			local pos = roomPoint(run, room, rng:NextNumber(-24, 24), 0.25)
			MonsterService:Spawn(B.SproutId, pos, {zone = run.zone, leash = 90})
		end
	end
end

function BossService:Init()
	DataService = Loader.Get("DataService")
	PartyService = Loader.Get("PartyService")
	PlayerService = Loader.Get("PlayerService")
	InventoryService = Loader.Get("InventoryService")
	MonsterService = Loader.Get("MonsterService")
	CombatService = Loader.Get("CombatService")
	pcall(Models.Ensure)
	Behaviors.Extend(Act1.Boss.Id, {
		Step = function() return true end,
		-- design doc 7.4: the heart can be hit only after the three growths are destroyed
		HitMultiplier = function(mob, hit)
			local run = mob.x and mob.x.run
			if not run or run.heartOpen then return 1 end
			local attacker = hit.attacker
			if attacker and attacker.Parent and os.clock() >= (run.warnAt[attacker] or 0) then
				run.warnAt[attacker] = os.clock() + 4
				Net.Fire(attacker, "Notify", "raid_shielded")
			end
			return 0
		end,
	})
	Behaviors.Extend(Act1.Boss.GrowthId, {Step = function() return true end})
end

function BossService:Start()
	Players.PlayerRemoving:Connect(function(player) self:Leave(player, "gone") end)
	while true do
		task.wait(0.2)
		local now = os.clock()
		for _, run in pairs(table.clone(runs)) do
			-- run.manual: a test drives this run with its own clock
			if not run.manual then
				local ok, err = pcall(self.StepRun, self, run, now)
				if not ok then warn("[Boss] " .. tostring(err)) end
			end
		end
	end
end

return BossService
