-- Оборона деревни (шаги 5.2–5.4 ДД, веха 6):
-- 30 с подготовки, волны монстров под размер пати, двустворчатые ворота, 4 гриба-турели,
-- 2 ловушки, 5-рунный погодный тотем со штрафом за неверную руну, 3 грейда наград и кросс-серверный Зов о помощи.
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Locale = require(Shared.Modules.Locale)
local DefenseCfg = require(Shared.Config.Defense)
local EconomyCfg = require(Shared.Config.Economy)
local WeatherCfg = require(Shared.Config.Weather)
local Mushrooms = require(Shared.Config.Mushrooms)
local Items = require(Shared.Config.Items)
local Rewards = require(Shared.Formulas.Rewards)
local MushroomSize = require(Shared.Modules.MushroomSize)

local DefenseService = {Priority = 55}
local DataService, PartyService, PlayerService, InventoryService, WeatherService, HouseService, MonsterService, CombatService
local LobbyLink -- веха 9: код доступа этого сервера и билеты помощников
local rng = Random.new()

local plotDef = {}   -- [plotModel] = {gateClosed, gateHp, runeId, turrets = {[i]={def,model,nextShot}}, traps = {[i]={def,model}}}
local waves = {}     -- [hostUserId] = {phase = "prep"|"active", prepLeft, weather, initialCrops, mobs = {[uid]=mob}, helpers = {[Player]=dmg}}
local helpCalls = {} -- [alertId] = {id, hostUserId, hostName, weather, placeId, jobId, expiresAt}
local callsUsed = {} -- [Player] = count

local function langOf(player)
	local p = DataService:GetProfile(player)
	return p and p.settings and p.settings.language or Locale.Default or "en"
end

local function findRune(runeId)
	for i, r in ipairs(DefenseCfg.Totem.Runes) do
		if r.id == runeId then return r, i end
	end
	return DefenseCfg.Totem.Runes[1], 1
end

-- Чистая формула погодного тотема (шаг 5.3 ДД):
-- верная руна -> возвращает монстров и игрока к ×1.0;
-- неверная включённая руна -> работает наоборот (монстры ×1.25, игрок ×0.8);
-- выключенный тотем -> действуют обычные множители текущей погоды.
function DefenseService.TotemMultipliers(weatherId, runeId)
	local w = WeatherCfg.Types[weatherId] or {}
	local rawMonster = w.monsterDamage or 1
	local rawPlayer = w.playerDamage or 1
	if not runeId or runeId == "off" then
		return {player = rawPlayer, monster = rawMonster, state = "off", totem = false}
	end
	local rune = findRune(runeId)
	if rune and rune.weather == weatherId then
		return {player = 1, monster = 1, state = "matched", totem = true}
	end
	return {
		player = DefenseCfg.Totem.WrongPlayerMultiplier,
		monster = DefenseCfg.Totem.WrongMonsterMultiplier,
		state = "wrong",
		totem = false,
	}
end

-- Чистая оценка грейда обороны (Бронза / Серебро / Золото)
function DefenseService.ComputeGrade(initialCrops, remainingCrops, gateBroken, avgBedHealth)
	local lostCrops = math.max(0, (initialCrops or 0) - (remainingCrops or 0))
	if lostCrops == 0 and not gateBroken and (avgBedHealth or 100) >= 60 then
		return "gold"
	elseif lostCrops <= 1 and (avgBedHealth or 100) >= 35 then
		return "silver"
	end
	return "bronze"
end

-- Прочность ворот с учётом уровня Защитных тотемов команды (веха 7: +TotemGateHpPerLevel за уровень)
local function gateMaxHp(plotModel)
	local host = plotModel and plotModel:GetAttribute("OwnerHost") or 0
	local team = host ~= 0 and DataService and DataService:GetTeam(host) or nil
	local lvl = team and team.buildings and tonumber(team.buildings.totems) or 0
	return DefenseCfg.Gate.MaxHP + EconomyCfg.UpgradeEffects.TotemGateHpPerLevel * math.max(0, lvl)
end

-- Уровень тотемов вырос — ворота сразу получают прибавку; предел стал меньше (участок сменил команду) — прочность не выше нового предела
local function refreshGateMax(plotModel, st)
	local newMax = gateMaxHp(plotModel)
	local oldMax = st.gateMax or DefenseCfg.Gate.MaxHP
	if newMax ~= oldMax then
		if st.gateHp > 0 then st.gateHp = math.clamp(st.gateHp + (newMax - oldMax), 1, newMax) end
		st.gateMax = newMax
	end
	return newMax
end

local function ensurePlotState(plotModel)
	local st = plotDef[plotModel]
	if not st then
		st = {
			gateClosed = false,
			gateHp = gateMaxHp(plotModel),
			gateMax = gateMaxHp(plotModel),
			runeId = "off",
			turrets = {},
			traps = {},
		}
		plotDef[plotModel] = st
	end
	return st
end

local function countTeamCrops(team)
	local n, totalH, bedsN = 0, 0, 0
	for _, b in pairs(team and team.garden and team.garden.beds or {}) do
		bedsN += 1
		totalH += (b.health or 100)
		if b.species then n += 1 end
	end
	return n, (bedsN > 0 and (totalH / bedsN) or 100)
end

function DefenseService:SyncGateVisual(plotModel)
	local st = ensurePlotState(plotModel)
	local defFolder = plotModel:FindFirstChild("Defense")
	local gate = defFolder and defFolder:FindFirstChild("PlotGate")
	if not gate then return end
	local closed = st.gateClosed and st.gateHp > 0
	local pivot = plotModel:GetPivot()
	for _, nm in ipairs({"LeafL", "LeafR"}) do
		local leaf = gate:FindFirstChild(nm)
		if leaf and leaf:IsA("BasePart") then
			local rel = leaf:GetAttribute(closed and "ClosedRel" or "OpenRel")
			if typeof(rel) == "CFrame" then leaf.CFrame = pivot * rel end
			leaf.CanCollide = closed
			leaf.Transparency = st.gateHp <= 0 and 0.65 or 0
		end
	end
	gate:SetAttribute("Closed", closed)
	gate:SetAttribute("HP", math.max(0, math.floor(st.gateHp + 0.5)))
	gate:SetAttribute("MaxHP", st.gateMax or DefenseCfg.Gate.MaxHP)
end

function DefenseService:SyncTotemVisual(plotModel)
	local st = ensurePlotState(plotModel)
	local defFolder = plotModel:FindFirstChild("Defense")
	local totem = defFolder and defFolder:FindFirstChild("WeatherTotem")
	if not totem then return end
	local rune = findRune(st.runeId)
	local mults = DefenseService.TotemMultipliers(WeatherService:Get(), st.runeId)
	local orb = totem:FindFirstChild("RuneOrb")
	local light = orb and orb:FindFirstChild("RuneLight")
	if orb and orb:IsA("BasePart") then
		if mults.state == "wrong" then
			orb.Color = Color3.fromRGB(235, 58, 52)
			orb.Material = Enum.Material.Neon
		elseif mults.state == "matched" then
			orb.Color = rune.color
			orb.Material = Enum.Material.Neon
		else
			orb.Color = rune.color
			orb.Material = st.runeId == "off" and Enum.Material.Slate or Enum.Material.Neon
		end
	end
	if light then
		light.Color = orb and orb.Color or rune.color
		light.Brightness = st.runeId == "off" and 0 or 1.4
	end
	totem:SetAttribute("Rune", st.runeId)
	totem:SetAttribute("TotemState", mults.state)
end

function DefenseService:HasMatchingTotem(hostUserId, weatherId)
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if not plots then return false end
	for _, pm in ipairs(plots:GetChildren()) do
		if pm:GetAttribute("OwnerHost") == hostUserId then
			local st = ensurePlotState(pm)
			local r = findRune(st.runeId)
			return r ~= nil and r.weather == weatherId
		end
	end
	return false
end

-- Множители урона в точке pos с учётом ближайшего Погодного тотема в радиусе 45 стадов
function DefenseService:CombatMultipliersAt(pos)
	local weatherId = WeatherService and WeatherService:Get() or "clear"
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if plots and typeof(pos) == "Vector3" then
		for _, pm in ipairs(plots:GetChildren()) do
			if (pm:GetAttribute("OwnerHost") or 0) ~= 0 then
				local defFolder = pm:FindFirstChild("Defense")
				local totem = defFolder and defFolder:FindFirstChild("WeatherTotem")
				local host = pm:GetAttribute("OwnerHost") or 0
				local team = host ~= 0 and DataService:GetTeam(host) or nil
				local tLvl = team and team.buildings and tonumber(team.buildings.totems) or 0
				local radius = DefenseCfg.Totem.Radius + tLvl * 4
				if totem and (totem:GetPivot().Position - pos).Magnitude <= radius then
					local st = ensurePlotState(pm)
					return DefenseService.TotemMultipliers(weatherId, st.runeId)
				end
			end
		end
	end
	return DefenseService.TotemMultipliers(weatherId, "off")
end

-- Ворота: открыть / закрыть или починить Каменным трутовиком
function DefenseService:InteractGate(player, plotModel)
	local host = PartyService:GetHost(player)
	if not (host and plotModel and plotModel:GetAttribute("OwnerHost") == host) then
		Net.Fire(player, "Notify", "farm_not_yours")
		return false
	end
	local st = ensurePlotState(plotModel)
	local heldId = CombatService:HeldItem(player)
	if heldId == DefenseCfg.Gate.RepairItem and st.gateHp < (st.gateMax or DefenseCfg.Gate.MaxHP) then
		if InventoryService:Take(player, heldId, 1) then
			st.gateHp = math.min(st.gateMax or DefenseCfg.Gate.MaxHP, st.gateHp + DefenseCfg.Gate.RepairAmount)
			self:SyncGateVisual(plotModel)
			Net.Fire(player, "Notify", "gate_repaired", math.floor(st.gateHp))
			PlayerService:Push(player)
			return true
		end
	end
	if st.gateHp <= 0 then
		if not waves[host] then
			st.gateHp = DefenseCfg.Gate.MaxHP
		else
			Net.Fire(player, "Notify", "gate_broken_repair")
			return false
		end
	end
	st.gateClosed = not st.gateClosed
	self:SyncGateVisual(plotModel)
	Net.Fire(player, "Notify", st.gateClosed and "gate_closed" or "gate_opened")
	return true
end

-- Погодный тотем: переключить руну по кругу (или выставить конкретную runeId)
function DefenseService:SetTotemRune(player, plotModel, specificRuneId)
	local host = PartyService:GetHost(player)
	if not (host and plotModel and plotModel:GetAttribute("OwnerHost") == host) then
		Net.Fire(player, "Notify", "farm_not_yours")
		return false
	end
	local st = ensurePlotState(plotModel)
	local _, curIdx = findRune(st.runeId)
	local nextRune = specificRuneId and findRune(specificRuneId) or DefenseCfg.Totem.Runes[curIdx % #DefenseCfg.Totem.Runes + 1]
	st.runeId = nextRune.id
	self:SyncTotemVisual(plotModel)
	local mults = DefenseService.TotemMultipliers(WeatherService:Get(), st.runeId)
	local lang = langOf(player)
	if mults.state == "matched" then
		Net.Fire(player, "Notify", "totem_matched", Locale.Name(lang, nextRune.name))
	elseif mults.state == "wrong" then
		Net.Fire(player, "Notify", "totem_wrong", Locale.Name(lang, nextRune.name))
	else
		Net.Fire(player, "Notify", "totem_off")
	end
	return true, st.runeId, mults.state
end

-- Поставить Гриб-турель на постамент TurretSpot_i
function DefenseService:PlaceTurret(player, spotPart)
	local defFolder = spotPart and spotPart.Parent
	local plotModel = defFolder and defFolder.Parent
	local idx = spotPart and tonumber(spotPart.Name:match("^TurretSpot_(%d+)$"))
	local host = PartyService:GetHost(player)
	if not (idx and host and plotModel and plotModel:GetAttribute("OwnerHost") == host) then
		Net.Fire(player, "Notify", "farm_not_yours")
		return false
	end
	local st = ensurePlotState(plotModel)
	local heldId = CombatService:HeldItem(player)
	local chosenDef = nil
	for _, tId in ipairs(DefenseCfg.TurretOrder) do
		local td = DefenseCfg.Turrets[tId]
		if heldId == td.item then
			chosenDef = td
			break
		end
	end
	if not chosenDef then
		for _, tId in ipairs(DefenseCfg.TurretOrder) do
			local td = DefenseCfg.Turrets[tId]
			if InventoryService:Count(player, td.item) > 0 then
				chosenDef = td
				break
			end
		end
	end
	if not chosenDef or not InventoryService:Take(player, chosenDef.item, 1) then
		Net.Fire(player, "Notify", "turret_need_mushroom")
		return false
	end
	if st.turrets[idx] and st.turrets[idx].model then
		st.turrets[idx].model:Destroy()
	end
	local sp = Mushrooms.Species[chosenDef.species]
	local tmpl = sp and ServerStorage.Templates.Mushrooms:FindFirstChild(sp.model)
	if not tmpl then return false end
	local m = MushroomSize.Spawn(tmpl, "placed", spotPart.CFrame * CFrame.new(0, 0.2, 0), defFolder)
	m.Name = "Turret_" .. idx
	spotPart:SetAttribute("TurretId", chosenDef.id)
	st.turrets[idx] = {def = chosenDef, model = m, nextShot = 0, owner = player}
	Net.Fire(player, "Notify", "turret_placed", Locale.Name(langOf(player), chosenDef.name))
	PlayerService:Push(player)
	return true, chosenDef.id
end

-- Посадить Гриб-ловушку на точку TrapSpot_i
function DefenseService:PlaceTrap(player, spotPart)
	local defFolder = spotPart and spotPart.Parent
	local plotModel = defFolder and defFolder.Parent
	local idx = spotPart and tonumber(spotPart.Name:match("^TrapSpot_(%d+)$"))
	local host = PartyService:GetHost(player)
	if not (idx and host and plotModel and plotModel:GetAttribute("OwnerHost") == host) then
		Net.Fire(player, "Notify", "farm_not_yours")
		return false
	end
	local st = ensurePlotState(plotModel)
	if st.traps[idx] then return false end
	local heldId = CombatService:HeldItem(player)
	local chosenTrap, usedItem = nil, nil
	for _, trapKey in ipairs({"spore_mine", "snare"}) do
		local tr = DefenseCfg.Traps[trapKey]
		if table.find(tr.items, heldId) and InventoryService:Count(player, heldId) > 0 then
			chosenTrap, usedItem = tr, heldId
			break
		end
	end
	if not chosenTrap then
		for _, trapKey in ipairs({"spore_mine", "snare"}) do
			local tr = DefenseCfg.Traps[trapKey]
			for _, itId in ipairs(tr.items) do
				if InventoryService:Count(player, itId) > 0 then
					chosenTrap, usedItem = tr, itId
					break
				end
			end
			if chosenTrap then break end
		end
	end
	if not (chosenTrap and usedItem and InventoryService:Take(player, usedItem, 1)) then
		Net.Fire(player, "Notify", "trap_need_item")
		return false
	end
	local sp = Mushrooms.Species[chosenTrap.species]
	local tmpl = sp and ServerStorage.Templates.Mushrooms:FindFirstChild(sp.model)
	local m = tmpl and MushroomSize.Spawn(tmpl, "hand", spotPart.CFrame * CFrame.new(0, 0.1, 0), defFolder) or nil
	if m then m.Name = "Trap_" .. idx end
	spotPart:SetAttribute("TrapId", chosenTrap.id)
	st.traps[idx] = {def = chosenTrap, model = m, spot = spotPart, owner = player}
	Net.Fire(player, "Notify", "trap_placed", Locale.Name(langOf(player), chosenTrap.name))
	PlayerService:Push(player)
	return true, chosenTrap.id
end

function DefenseService:PlotOfHost(hostUserId)
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if not plots then return nil end
	for _, pm in ipairs(plots:GetChildren()) do
		if pm:GetAttribute("OwnerHost") == hostUserId then return pm end
	end
	return nil
end

function DefenseService:PushWaveState(hostUserId)
	local w = waves[hostUserId]
	local payload = w and {
		active = true,
		phase = w.phase,
		prepLeft = math.max(0, math.ceil(w.prepLeft or 0)),
		remaining = w.remaining or 0,
		total = w.total or 0,
		weather = w.weather,
	} or {active = false}
	for _, m in ipairs(PartyService:GetMembers(hostUserId)) do
		Net.Fire(m, "WaveState", payload)
	end
	if w then
		for helper in pairs(w.helpers) do
			if helper.Parent then Net.Fire(helper, "WaveState", payload) end
		end
	end
end

-- Запуск волны на участок команды: 30 с подготовки -> спавн волны под размер пати
function DefenseService:StartWave(hostUserId, prepOverride)
	if waves[hostUserId] then return false, "already_active" end
	local plotModel = self:PlotOfHost(hostUserId)
	local team = DataService:GetTeam(hostUserId)
	if not (plotModel and team) then return false, "no_plot" end
	local list = PartyService:GetMembers(hostUserId)
	if #list == 0 then return false, "no_members" end

	local w = {
		host = hostUserId,
		plot = plotModel,
		phase = "prep",
		prepLeft = prepOverride ~= nil and prepOverride or DefenseCfg.PrepSeconds,
		weather = WeatherService:Get(),
		initialCrops = 0,
		mobs = {},
		total = 0,
		remaining = 0,
		helpers = {},
	}
	waves[hostUserId] = w
	for _, p in ipairs(list) do
		Net.Fire(p, "Notify", "wave_incoming")
	end
	self:PushWaveState(hostUserId)
	return true
end

function DefenseService:SpawnWaveMonsters(w)
	local plotModel = w.plot
	if not (plotModel and plotModel.Parent) then
		waves[w.host] = nil
		return
	end
	local team = DataService:GetTeam(w.host)
	w.initialCrops = select(1, countTeamCrops(team))
	w.phase = "active"

	local pSize = math.clamp(#PartyService:GetMembers(w.host), 1, 4)
	local scale = DefenseCfg.PartyMobScale[pSize] or 1
	local count = math.max(3, math.floor(DefenseCfg.BaseMobCount * scale + 0.5))
	local pool = {"rot_sprout", "spore_mosquito", "mold_slug", "fly_agaric_bandit"}
	local pivot = plotModel:GetPivot()

	for i = 1, count do
		local id = pool[(i - 1) % #pool + 1]
		local spread = (i - (count + 1) / 2) * 4.2
		-- спавним перед воротами участка со стороны кольцевой дороги (−Z участка)
		local spawnCf = pivot * CFrame.new(spread, 0.3, -24 - (i % 2) * 5)
		local mob = MonsterService:Spawn(id, Vector3.new(spawnCf.Position.X, 0.3, spawnCf.Position.Z), {
			zone = "wave_" .. w.host,
			leash = 140,
		})
		if mob then
			mob.waveHost = w.host
			w.mobs[mob.uid] = mob
			w.total += 1
		end
	end
	-- В Кровавую Луну или для пати 3–4 игроков к волне присоединяется элитник
	if w.weather == "blood_moon" or pSize >= 3 then
		local eliteId = w.weather == "blood_moon" and "moon_reaper" or "mycelium_knight"
		local ePos = (pivot * CFrame.new(0, 0.3, -30)).Position
		local emob = MonsterService:Spawn(eliteId, Vector3.new(ePos.X, 0.3, ePos.Z), {zone = "wave_" .. w.host, leash = 140})
		if emob then
			emob.waveHost = w.host
			w.mobs[emob.uid] = emob
			w.total += 1
		end
	end
	w.remaining = w.total
	self:PushWaveState(w.host)
end

-- Завершение волны и выдача наград по грейду (Бронза / Серебро / Золото) + награда помощникам (75% + 1 кристалл)
function DefenseService:FinishWave(w)
	waves[w.host] = nil
	local team = DataService:GetTeam(w.host)
	local st = ensurePlotState(w.plot)
	local remCrops, avgHealth = countTeamCrops(team)
	local grade = DefenseService.ComputeGrade(w.initialCrops, remCrops, st.gateHp <= 0, avgHealth)
	local gDef = DefenseCfg.Rewards.Grades[grade]
	local danger = DefenseCfg.Rewards.WeatherDanger[w.weather] or 1
	local members = PartyService:GetMembers(w.host)
	local pSize = math.clamp(#members, 1, 4)

	local baseCoins = math.floor(gDef.coins * danger + 0.5)
	local baseDust = math.floor(gDef.sporeDust * danger + 0.5)
	local baseXp = math.floor(gDef.xp * danger + 0.5)
	local trophyId = gDef.trophy and DefenseCfg.Rewards.WeatherTrophy[w.weather] or nil

	for _, member in ipairs(members) do
		local coins = Rewards.Apply(baseCoins, pSize)
		local dust = Rewards.Apply(baseDust, pSize)
		InventoryService:AddCurrency(member, "coins", coins, "wave_reward:" .. grade)
		InventoryService:AddCurrency(member, "sporeDust", dust, "wave_reward:" .. grade)
		if (gDef.crystals or 0) > 0 then
			InventoryService:AddCurrency(member, "crystals", gDef.crystals, "wave_reward:" .. grade)
		end
		if w.weather == "blood_moon" and grade == "gold" and gDef.bloodMoonStarSeal then
			InventoryService:AddCurrency(member, "starSeals", gDef.bloodMoonStarSeal, "wave_reward:blood_moon_gold")
			if rng:NextNumber() < (gDef.bloodMoonBookChance or 0.35) then
				InventoryService:Give(member, "book_void_spores", 1)
			end
		end
		if trophyId and Items.Defs[trophyId] then
			InventoryService:Give(member, trophyId, 1)
		end
		local prof = DataService:GetProfile(member)
		if prof then
			prof.rank = prof.rank or {xp = 0}
			prof.rank.xp = (prof.rank.xp or 0) + baseXp
			prof.stats.wavesCleared = (prof.stats.wavesCleared or 0) + 1
		end
		Net.Fire(member, "Notify", "wave_victory_" .. grade, coins, dust)
		PlayerService:Push(member)
	end

	-- Награда пришедшим по Зову о помощи спасателям (хозяин ничего не теряет)
	for helper, dealt in pairs(w.helpers) do
		if helper.Parent and dealt > 0 and PartyService:GetHost(helper) ~= w.host then
			local hCoins = math.floor(baseCoins * DefenseCfg.Rewards.HelperShare + 0.5)
			local hDust = math.floor(baseDust * DefenseCfg.Rewards.HelperShare + 0.5)
			local hXp = math.floor(baseXp * DefenseCfg.Rewards.HelperShare + 0.5)
			InventoryService:AddCurrency(helper, "coins", hCoins, "wave_helper")
			InventoryService:AddCurrency(helper, "sporeDust", hDust, "wave_helper")
			InventoryService:AddCurrency(helper, "crystals", DefenseCfg.Rewards.HelperBonusCrystals, "wave_helper")
			local hp = DataService:GetProfile(helper)
			if hp then
				hp.rank = hp.rank or {xp = 0}
				hp.rank.xp = (hp.rank.xp or 0) + hXp
				hp.stats.helpedDefenses = (hp.stats.helpedDefenses or 0) + 1
			end
			Net.Fire(helper, "Notify", "wave_helper_reward", hCoins, hDust, DefenseCfg.Rewards.HelperBonusCrystals)
			PlayerService:Push(helper)
		end
	end

	-- Снимаем временные турели закончившейся волны и восстанавливаем ворота
	for idx, tur in pairs(st.turrets) do
		if tur.model then tur.model:Destroy() end
		st.turrets[idx] = nil
		local defF = w.plot:FindFirstChild("Defense")
		local sp = defF and defF:FindFirstChild("TurretSpot_" .. idx)
		if sp then sp:SetAttribute("TurretId", nil) end
	end
	if st.gateHp <= 0 then st.gateHp = DefenseCfg.Gate.MaxHP end
	self:SyncGateVisual(w.plot)
	self:PushWaveState(w.host)
end

-- Учёт вклада помощника при нанесении урона монстру чужой волны
function DefenseService:RecordHelperHit(attacker, mob, dmg)
	if not (attacker and mob and mob.waveHost and dmg > 0) then return end
	local w = waves[mob.waveHost]
	if w and PartyService:GetHost(attacker) ~= mob.waveHost then
		w.helpers[attacker] = (w.helpers[attacker] or 0) + dmg
	end
end

-- Шаг всех турелей, ловушек и активных волн
function DefenseService:Step(dt, now)
	-- 1) Турели и ловушки на всех занятых участках
	for plotModel, st in pairs(plotDef) do
		if plotModel.Parent and st.gateMax ~= gateMaxHp(plotModel) then
			refreshGateMax(plotModel, st)
			self:SyncGateVisual(plotModel)
		end
		if not plotModel.Parent or (plotModel:GetAttribute("OwnerHost") or 0) == 0 then
			plotDef[plotModel] = nil
		else
			local ownerHost = plotModel:GetAttribute("OwnerHost") or 0
			local ownerTeam = ownerHost ~= 0 and DataService:GetTeam(ownerHost) or nil
			local totemLvl = ownerTeam and ownerTeam.buildings and tonumber(ownerTeam.buildings.totems) or 0
			local turretMult = 1 + 0.12 * totemLvl
			for _, tur in pairs(st.turrets) do
				if tur.model and tur.model.Parent and now >= tur.nextShot then
					local origin = tur.model:GetPivot().Position + Vector3.new(0, 2.2, 0)
					local target = MonsterService:NearestMonster(origin, tur.def.range)
					if target then
						tur.nextShot = now + tur.def.interval
						local tPos = target.model:GetPivot().Position + Vector3.new(0, 1.5, 0)
						Net.FireAll("CombatFx", "projectile", "turret_" .. tur.def.id, origin, tPos)
						if tur.def.aoeRadius then
							for _, m in ipairs(MonsterService:MonstersInRadius(target.model:GetPivot().Position, tur.def.aoeRadius)) do
								MonsterService:HitMonster(m, {
									attacker = tur.owner, base = tur.def.damage * turretMult, attack = 1,
									element = tur.def.element, poise = tur.def.poise, burnsShield = tur.def.burnsShield,
								})
							end
						else
							MonsterService:HitMonster(target, {
								attacker = tur.owner, base = tur.def.damage * turretMult, attack = 1,
								element = tur.def.element, poise = tur.def.poise,
								slow = tur.def.slow and {factor = tur.def.slow, duration = tur.def.slowDuration} or nil,
								poison = tur.def.dotDamage and {dps = tur.def.dotDamage, duration = tur.def.dotDuration} or nil,
								freezesShield = tur.def.freezesShield,
							})
							if tur.def.chains then
								local second = MonsterService:NearestMonster(tPos, 10, {[target] = true})
								if second then
									Net.FireAll("CombatFx", "chain_lightning", {tPos, second.model:GetPivot().Position + Vector3.new(0, 1.5, 0)})
									MonsterService:HitMonster(second, {attacker = tur.owner, base = tur.def.damage * 0.75 * turretMult, attack = 1, element = tur.def.element, poise = 10})
								end
							end
						end
					end
				end
			end

			for idx, tr in pairs(st.traps) do
				if tr.spot and tr.spot.Parent then
					local hitMob = MonsterService:NearestMonster(tr.spot.Position, tr.def.triggerRadius)
					if hitMob then
						st.traps[idx] = nil
						tr.spot:SetAttribute("TrapId", nil)
						if tr.model then tr.model:Destroy() end
						Net.FireAll("CombatFx", "aoe_burst", tr.def.element or "air", tr.spot.Position, tr.def.effectRadius)
						for _, m in ipairs(MonsterService:MonstersInRadius(tr.spot.Position, tr.def.effectRadius)) do
							MonsterService:HitMonster(m, {
								attacker = tr.owner, base = tr.def.damage, attack = 1,
								element = tr.def.element, poise = tr.def.poise or 15,
								bind = tr.def.bindSeconds,
								poison = tr.def.dotDamage and {dps = tr.def.dotDamage, duration = tr.def.dotDuration} or nil,
							})
						end
					end
				end
			end
		end
	end

	-- 2) Активные волны
	for host, w in pairs(table.clone(waves)) do
		if not (w.plot and w.plot.Parent) or #PartyService:GetMembers(host) == 0 then
			MonsterService:ClearAll("wave_" .. host)
			waves[host] = nil
		elseif w.phase == "prep" then
			local beforeCeil = math.ceil(w.prepLeft)
			w.prepLeft -= dt
			if w.prepLeft <= 0 then
				self:SpawnWaveMonsters(w)
			elseif math.ceil(w.prepLeft) ~= beforeCeil then
				self:PushWaveState(host)
			end
		elseif w.phase == "active" then
			local st = ensurePlotState(w.plot)
			local gatePos = w.plot:GetPivot().Position
			local alive = 0
			for uid, mob in pairs(w.mobs) do
				if mob.hp <= 0 or not (mob.model and mob.model.Parent) then
					w.mobs[uid] = nil
				else
					alive += 1
					-- если ворота закрыты и целы, монстры снаружи ломают ворота
					if st.gateClosed and st.gateHp > 0 then
						local mp = mob.model:GetPivot().Position
						local rel = w.plot:GetPivot():PointToObjectSpace(mp)
						if rel.Z < 1.5 then
							local toGate = Vector3.new(gatePos.X - mp.X, 0, gatePos.Z - mp.Z)
							if toGate.Magnitude > 3.2 and now >= mob.bindUntil and now >= mob.staggerUntil and now >= mob.stunUntil and now >= mob.sleepUntil then
								local step = toGate.Unit * math.min(toGate.Magnitude - 2.2, mob.def.speed * dt)
								mob.model:PivotTo(CFrame.lookAt(Vector3.new(mp.X + step.X, mob.spawnPos.Y, mp.Z + step.Z), Vector3.new(gatePos.X, mob.spawnPos.Y, gatePos.Z)))
							elseif toGate.Magnitude <= 3.6 and now >= mob.nextAttack then
								mob.nextAttack = now + (mob.def.attackCooldown or 1.4)
								st.gateHp = math.max(0, st.gateHp - (mob.def.damage or 8))
								self:SyncGateVisual(w.plot)
								if st.gateHp <= 0 then
									for _, m in ipairs(PartyService:GetMembers(host)) do
										Net.Fire(m, "Notify", "gate_destroyed")
									end
								end
							end
						end
					else
						-- направляем волновых монстров внутрь участка, если они ещё далеко от огорода
						local yardCenter = (w.plot:GetPivot() * CFrame.new(0, 0, 16)).Position
						mob.spawnPos = Vector3.new(yardCenter.X, 0.3, yardCenter.Z)
					end
				end
			end
			if alive ~= w.remaining then
				w.remaining = alive
				self:PushWaveState(host)
			end
			if alive == 0 then
				self:FinishWave(w)
			end
		end
	end
end

-- Зов о помощи (шаг 5.4 ДД): оповещает свой сервер и публикует кросс-серверный вызов через MessagingService
function DefenseService.ShouldEscalateHelp(localNotified)
	return localNotified == 0
end

-- Веха 9: клиентам объявление уходит без кода доступа сервера
local function publicAlert(alert)
	local copy = table.clone(alert)
	copy.accessCode = nil
	return copy
end

function DefenseService:CallForHelp(player)
	local host = PartyService:GetHost(player)
	local w = host and waves[host]
	if not w then
		Net.Fire(player, "Notify", "help_no_wave")
		return false, "no_wave"
	end
	local used = callsUsed[player] or 0
	if used >= DefenseCfg.HelpCall.FreeCallsPerSession then
		Net.Fire(player, "Notify", "help_limit_reached")
		return false, "limit"
	end
	callsUsed[player] = used + 1

	local alert = {
		id = HttpService:GenerateGUID(false),
		hostUserId = host,
		hostName = PartyService:GetHostName(player),
		weather = w.weather,
		placeId = game.PlaceId,
		jobId = game.JobId,
		-- веха 9: игровые серверы зарезервированы лобби, помощника с другого сервера пускает код доступа
		serverId = LobbyLink and LobbyLink.ServerId or game.JobId,
		accessCode = LobbyLink and LobbyLink:AccessCode() or nil,
		expiresAt = os.time() + DefenseCfg.HelpCall.AlertDurationSeconds,
	}
	helpCalls[alert.id] = alert

	-- 1) Игрокам на этом сервере
	local localNotified = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if PartyService:GetHost(other) ~= host then
			Net.Fire(other, "HelpAlert", publicAlert(alert))
			localNotified += 1
		end
	end

	-- Escalate only when no eligible players were notified locally.
	local crossSent = false
	if DefenseService.ShouldEscalateHelp(localNotified) then
		pcall(function()
			MessagingService:PublishAsync(DefenseCfg.HelpCall.Topic, HttpService:JSONEncode(alert))
			crossSent = true
		end)
	end

	Net.Fire(player, "Notify", "help_sent")
	return true, {alertId = alert.id, localNotified = localNotified, crossSent = crossSent}
end

function DefenseService:RespondHelp(helper, alertId)
	local alert = type(alertId) == "string" and helpCalls[alertId]
	if not alert or os.time() > alert.expiresAt then
		Net.Fire(helper, "Notify", "help_expired")
		return false, "expired"
	end
	if PartyService:GetHost(helper) == alert.hostUserId then return false, "own_team" end

	-- На том же сервере — мгновенный перенос к воротам защищающейся деревни
	if alert.jobId == game.JobId then
		local ok = self:TeleportHelperToHost(helper, alert.hostUserId)
		return ok, ok and "teleported_local" or "no_wave"
	end

	-- На другом сервере — межсерверный телепорт через TeleportService
	local okTp, errTp = pcall(function()
		local opts = Instance.new("TeleportOptions")
		if alert.accessCode then
			opts.ReservedServerAccessCode = alert.accessCode
		else
			opts.ServerInstanceId = alert.jobId
		end
		-- веха 9: тот сервер узнаёт помощника по билету, который пишет этот сервер, а не по TeleportData
		if LobbyLink then LobbyLink:HelperTicket(helper, alert) end
		opts:SetTeleportData({helpHost = alert.hostUserId})
		TeleportService:TeleportAsync(alert.placeId, {helper}, opts)
	end)
	if not okTp then
		warn("[Defense] Cross-server teleport unavailable in Studio: " .. tostring(errTp))
	end
	return okTp, okTp and "teleported_cross" or "teleport_unavailable"
end

function DefenseService:TeleportHelperToHost(helper, hostUserId)
	local plotModel = self:PlotOfHost(hostUserId)
	if not plotModel then return false end
	local w = waves[hostUserId]
	if w then w.helpers[helper] = w.helpers[helper] or 0 end
	local gateCf = plotModel:GetPivot() * CFrame.new(0, 3.2, -6) * CFrame.Angles(0, math.pi, 0)
	if workspace.StreamingEnabled then
		pcall(helper.RequestStreamAroundAsync, helper, gateCf.Position, 5)
	end
	if helper.Character then
		helper.Character:PivotTo(gateCf)
	end
	Net.Fire(helper, "Notify", "help_arrived")
	self:PushWaveState(hostUserId)
	return true
end

function DefenseService:HookPlotPrompts(plotModel)
	local defFolder = plotModel:FindFirstChild("Defense")
	if not defFolder or defFolder:GetAttribute("Hooked") then return end
	defFolder:SetAttribute("Hooked", true)
	self:SyncGateVisual(plotModel)
	self:SyncTotemVisual(plotModel)

	local gatePr = defFolder:FindFirstChild("GatePrompt", true)
	if gatePr then
		gatePr.Triggered:Connect(function(p) self:InteractGate(p, plotModel) end)
	end
	local totemPr = defFolder:FindFirstChild("TotemPrompt", true)
	if totemPr then
		totemPr.Triggered:Connect(function(p) self:SetTotemRune(p, plotModel) end)
	end
	for i = 1, 4 do
		local sp = defFolder:FindFirstChild("TurretSpot_" .. i)
		local pr = sp and sp:FindFirstChild("TurretPrompt")
		if pr then pr.Triggered:Connect(function(p) self:PlaceTurret(p, sp) end) end
	end
	for i = 1, 3 do
		local sp = defFolder:FindFirstChild("TrapSpot_" .. i)
		local pr = sp and sp:FindFirstChild("TrapPrompt")
		if pr then pr.Triggered:Connect(function(p) self:PlaceTrap(p, sp) end) end
	end
end

function DefenseService:Init()
	DataService = Loader.Get("DataService")
	PartyService = Loader.Get("PartyService")
	PlayerService = Loader.Get("PlayerService")
	InventoryService = Loader.Get("InventoryService")
	WeatherService = Loader.Get("WeatherService")
	HouseService = Loader.Get("HouseService")
	MonsterService = Loader.Get("MonsterService")
	CombatService = Loader.Get("CombatService")
	local okLink, link = pcall(Loader.Get, "LobbyLinkService")
	LobbyLink = okLink and link or nil
end

function DefenseService:Start()
	local function scanPlots()
		local map = workspace:FindFirstChild("Map")
		local plots = map and map:FindFirstChild("Plots")
		if not plots then return end
		for _, pm in ipairs(plots:GetChildren()) do
			self:HookPlotPrompts(pm)
		end
	end
	scanPlots()
	workspace.DescendantAdded:Connect(function(d)
		if d.Name == "Defense" and d.Parent and d.Parent.Name:match("^Plot_") then
			task.defer(function() self:HookPlotPrompts(d.Parent) end)
		end
	end)
	WeatherService.Changed:Connect(function()
		for pm in pairs(plotDef) do
			if pm.Parent then self:SyncTotemVisual(pm) end
		end
	end)
	Players.PlayerRemoving:Connect(function(p) callsUsed[p] = nil end)

	-- Подписка на кросс-серверные Зовы о помощи
	pcall(function()
		MessagingService:SubscribeAsync(DefenseCfg.HelpCall.Topic, function(msg)
			local ok, alert = pcall(HttpService.JSONDecode, HttpService, msg.Data)
			if ok and type(alert) == "table" and alert.jobId ~= game.JobId then
				helpCalls[alert.id] = alert
				Net.FireAll("HelpAlert", publicAlert(alert))
			end
		end)
	end)

	Net.On("DefenseAction", 8, function(player, action, a)
		if action == "call_help" then
			self:CallForHelp(player)
		elseif action == "respond_help" then
			self:RespondHelp(player, a)
		elseif action == "set_rune" then
			local plot = HouseService:GetPlot(player)
			if plot then self:SetTotemRune(player, plot.model, a) end
		end
	end)

	local last = os.clock()
	while true do
		task.wait(0.2)
		local now = os.clock()
		local dt = math.min(now - last, 0.5)
		last = now
		pcall(self.Step, self, dt, now)
	end
end

return DefenseService
