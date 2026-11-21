-- Milestone 8 audit (2026-11-14): the elder's quests, village restoration, the two portals and rescued residents
-- (technical plan, milestone 8, items 1–4; design doc 2.4, 6.2, 6.5, 7.1–7.2).
-- Runs only in a play session (ctx.live); the profile, the team record and the position are restored after every test.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

return function(it, expect, ctx)
	if not ctx.live then return end
	local Loader = require(ctx.shared.Modules.Loader)
	local Util = require(ctx.shared.Modules.Util)
	local Act1 = require(ctx.shared.Config.Act1)
	local Items = require(ctx.shared.Config.Items)
	local Monsters = require(ctx.shared.Config.Monsters)
	local MapCfg = require(ctx.shared.Config.Map)
	local Strings = require(ctx.shared.Locale.Strings)
	local DS, PS, PL = Loader.Get("DataService"), Loader.Get("PartyService"), Loader.Get("PlayerService")
	local IS, ES, MS, QS = Loader.Get("InventoryService"), Loader.Get("EconomyService"), Loader.Get("MonsterService"), Loader.Get("QuestService")
	local player = game:GetService("Players"):GetPlayers()[1]
	local ZONE = "audit_m8"
	local KILL = 1e7
	local R = Act1.Restoration

	-- a team that has not started the chain and an empty bag; everything is put back afterwards
	local function fixture(fn)
		local profile = DS:GetProfile(player)
		local team = DS:GetTeam(PS:GetHost(player))
		local savedProfile, savedTeam = Util.DeepCopy(profile), Util.DeepCopy(team)
		local char = player.Character
		local cf = char:GetPivot()
		local savedXp, savedRewards = Act1.QuestXp, Act1.Quests[2].rewards
		profile.inventory.items = {}
		profile.inventory.hotbar = {}
		team.quests = {active = {}, completed = {}}
		team.village = {restoration = 0, rescued = {}}
		team.acts = {current = 1, bossPortal = false, nextPortal = false}
		local ok, err = pcall(fn, {profile = profile, team = team, char = char})
		MS:ClearAll(ZONE)
		Act1.QuestXp, Act1.Quests[2].rewards = savedXp, savedRewards
		table.clear(profile)
		for k, v in pairs(savedProfile) do profile[k] = v end
		table.clear(team)
		for k, v in pairs(savedTeam) do team[k] = v end
		char:PivotTo(cf)
		PL:Push(player)
		if not ok then error(err, 0) end
	end

	local function standAt(pos)
		player.Character:PivotTo(CFrame.new(pos + Vector3.new(4, 3, 0)))
	end

	-- meet every objective of the current quest the short way and hand it in
	local function complete(team)
		if not QS.Status(team).active then expect(QS:Accept(player, true)).toBe(true) end
		local status = QS.Status(team)
		local state = team.quests.active[status.quest.id]
		for i, objective in ipairs(status.quest.objectives) do
			if objective.type == "deliver" then
				IS:Give(player, objective.item, status.objectives[i].need)
			elseif objective.type == "kill" then
				state.progress[i] = status.objectives[i].need
			elseif objective.type == "rescue" then
				QS:Rescue(player, objective.resident, true)
			end
		end
		local ok, id = QS:TurnIn(player, true)
		expect(ok).toBe(true)
		return id
	end

	local function kill(id)
		local root = player.Character.HumanoidRootPart.Position
		local mob = MS:Spawn(id, Vector3.new(root.X + 40, root.Y - 3, root.Z), {zone = ZONE})
		if not mob then error("spawn failed: " .. id, 0) end
		MS:HitMonster(mob, {attacker = player, base = KILL, attack = 1, noCrit = true})
		expect(mob.hp).toBe(0)
	end

	it("M8 config: the chain refers to items, monsters and residents that exist, restores the whole village and has every text in en and ru", function()
		local seen = {}
		for _, quest in ipairs(Act1.Quests) do
			expect(seen[quest.id]).toBe(nil)
			seen[quest.id] = true
			for _, key in ipairs({"quest_" .. quest.id .. "_title", "quest_" .. quest.id .. "_text"}) do
				expect(type(Strings.en[key])).toBe("string")
				expect(type(Strings.ru[key])).toBe("string")
			end
			expect(#quest.objectives >= 1).toBeTruthy()
			for _, objective in ipairs(quest.objectives) do
				if objective.type == "deliver" then
					expect(Items.Defs[objective.item] ~= nil).toBeTruthy()
				elseif objective.type == "kill" then
					expect((Monsters.Regular[objective.monster] or Monsters.Elite[objective.monster]) ~= nil).toBeTruthy()
				elseif objective.type == "rescue" then
					expect(QS.Resident(objective.resident) ~= nil).toBeTruthy()
				else
					error("unknown objective type " .. tostring(objective.type), 0)
				end
			end
		end
		expect(#R.Repairs).toBe(R.Max)
		expect(#Act1.Quests >= R.Max).toBeTruthy()
		-- design doc 7.2: the raid portal opens first, the portal to the next land after it
		expect(R.BossPortalAt >= 1 and R.BossPortalAt < R.NextPortalAt and R.NextPortalAt <= R.Max).toBeTruthy()
	end)

	it("M8 world: the elder stands in the middle of the village, the portals and the cages have their prompts, and every repair has a model", function()
		local village = workspace.Map.Village
		local elder = village:FindFirstChild("Elder")
		expect(elder ~= nil and elder:FindFirstChild("ElderPrompt", true) ~= nil).toBeTruthy()
		local at = elder:GetPivot().Position
		expect(Vector3.new(at.X, 0, at.Z).Magnitude <= MapCfg.Village.PlazaRadius).toBeTruthy()
		expect(village.ElderHouse:FindFirstChild("Mold1") ~= nil and village.ElderHouse:FindFirstChild("Crack1") ~= nil).toBeTruthy()
		expect(village.PortalRaid:FindFirstChild("RaidPrompt", true) ~= nil).toBeTruthy()
		expect(village.PortalNext:FindFirstChild("NextPrompt", true) ~= nil).toBeTruthy()
		for _, resident in ipairs(Act1.Residents) do
			local cage = workspace.Act1.Captives:FindFirstChild("Captive_" .. resident.id)
			expect(cage ~= nil and cage:FindFirstChild("RescuePrompt", true) ~= nil).toBeTruthy()
			local g = MapCfg.OldGarden
			local p = cage:GetPivot().Position
			expect(math.abs(p.X - g.Center.X) < g.Size.X / 2 and math.abs(p.Z - g.Center.Y) < g.Size.Y / 2).toBeTruthy()
		end
		local assets = ReplicatedStorage:FindFirstChild("Act1Assets")
		expect(assets ~= nil and assets:FindFirstChild("Resident") ~= nil).toBeTruthy()
		for _, name in ipairs(R.Repairs) do
			expect(village:FindFirstChild(name) ~= nil).toBeTruthy()
			if name ~= "ElderHouse" then
				-- the repaired house stands exactly where the ruin stands
				expect((assets[name].Foundation.Position - village[name].Foundation.Position).Magnitude < 0.01).toBeTruthy()
			end
		end
	end)

	it("M8 team size: a bigger team has to bring more; kills and rescues do not change", function() fixture(function(f)
		local deliver = {type = "deliver", item = "mushroom_fly_agaric", count = 3}
		for size, factor in ipairs(Act1.DeliverScale) do
			expect(Act1.Required(deliver, size)).toBe(3 * factor)
			if size > 1 then expect(factor > Act1.DeliverScale[size - 1]).toBeTruthy() end
		end
		expect(Act1.Required({type = "kill", monster = "rot_sprout", count = 3}, 4)).toBe(3)
		expect(Act1.Required({type = "rescue", resident = "resident_1"}, 4)).toBe(1)
		expect(Act1.TeamSize(0)).toBe(1)
		expect(Act1.TeamSize(9)).toBe(#Act1.DeliverScale)
		-- the size is fixed when the quest is taken; a team of three then needs three times as much
		expect(QS:Accept(player, true)).toBe(true)
		local quest = QS.Status(f.team).quest
		local state = f.team.quests.active[quest.id]
		expect(state.size).toBe(PS:GetSize(player))
		expect(QS.Status(f.team).objectives[1].need).toBe(quest.objectives[1].count * Act1.DeliverScale[state.size])
		state.size = 3
		expect(QS.Status(f.team).objectives[1].need).toBe(quest.objectives[1].count * Act1.DeliverScale[3])
	end) end)

	it("M8 elder: a quest is taken next to the elder, items are handed over in parts and the quest ends only when all is brought", function() fixture(function(f)
		local quest = Act1.Quests[1]
		local item, need = quest.objectives[1].item, quest.objectives[1].count
		-- the player's house is far from the plaza
		local ok, why = QS:Accept(player)
		expect(ok).toBe(false)
		expect(why).toBe("too_far")
		standAt(QS:ElderPosition())
		expect(QS:Accept(player)).toBe(true)
		ok, why = QS:Accept(player)
		expect(why).toBe("active")
		IS:Give(player, item, need - 1)
		ok, why = QS:TurnIn(player)
		expect(ok).toBe(false)
		expect(why).toBe("not_ready")
		expect(IS:Count(player, item)).toBe(0)
		expect(QS.Status(f.team).objectives[1].have).toBe(need - 1)
		expect(f.team.village.restoration).toBe(0)
		IS:Give(player, item, 5)
		expect(QS:TurnIn(player)).toBe(true)
		expect(IS:Count(player, item)).toBe(4) -- only the missing one was taken
		expect(f.team.village.restoration).toBe(1)
		expect(f.team.quests.completed[quest.id] ~= nil).toBeTruthy()
		expect(next(f.team.quests.active)).toBe(nil)
		local status = QS.Status(f.team)
		expect(status.quest.id).toBe(Act1.Quests[2].id)
		expect(status.active).toBe(false)
	end) end)

	it("M8 kills: only the monster the active quest names counts, and only while the quest is taken", function() fixture(function(f)
		complete(f.team)
		local quest = QS.Status(f.team).quest
		local objective = quest.objectives[1]
		expect(objective.type).toBe("kill")
		kill(objective.monster) -- not taken yet
		expect(QS:Accept(player, true)).toBe(true)
		expect(QS.Status(f.team).objectives[1].have).toBe(0)
		kill(objective.monster)
		expect(QS.Status(f.team).objectives[1].have).toBe(1)
		kill(objective.monster == "mold_slug" and "rot_sprout" or "mold_slug")
		expect(QS.Status(f.team).objectives[1].have).toBe(1)
		for _ = 2, objective.count do kill(objective.monster) end
		kill(objective.monster) -- one more than needed
		expect(QS.Status(f.team).objectives[1].have).toBe(objective.count)
		expect(QS:TurnIn(player, true)).toBe(true)
		expect(f.team.village.restoration).toBe(2)
	end) end)

	it("M8 rescue: a resident is freed at the cage, once, and a rescue made earlier counts for the quest", function() fixture(function(f)
		local resident = Act1.Residents[1].id
		local ok, why = QS:Rescue(player, resident)
		expect(ok).toBe(false)
		expect(why).toBe("too_far")
		ok, why = QS:Rescue(player, "nobody", true)
		expect(why).toBe("unknown")
		expect(#QS.Traders(f.team)).toBe(0)
		standAt(QS:CaptivePosition(resident))
		expect(QS:Rescue(player, resident)).toBe(true)
		ok, why = QS:Rescue(player, resident)
		expect(why).toBe("already")
		expect(f.team.village.rescued[resident] ~= nil).toBeTruthy()
		expect(QS.Traders(f.team)[1]).toBe(resident)
		-- walk the chain up to the first quest that asks for this resident
		local guard = 0
		while true do
			guard += 1
			if guard > #Act1.Quests then error("no quest asks for " .. resident, 0) end
			local quest = QS.Status(f.team).quest
			local wanted = false
			for _, objective in ipairs(quest.objectives) do
				if objective.type == "rescue" and objective.resident == resident then wanted = true end
			end
			if wanted then break end
			complete(f.team)
		end
		expect(QS:Accept(player, true)).toBe(true)
		local status = QS.Status(f.team)
		for i, objective in ipairs(status.quest.objectives) do
			if objective.type == "rescue" then expect(status.objectives[i].have).toBe(1) end
		end
	end) end)

	it("M8 restoration: every finished quest repairs one building; the raid portal opens first, then the next land, and the whole village gives the page of the ancestors", function() fixture(function(f)
		local ok, why = QS:UsePortal(player, "raid") -- the player's house is far from the portals
		expect(why).toBe("too_far")
		ok, why = QS:UsePortal(player, "raid", true)
		expect(ok).toBe(false)
		expect(why).toBe("closed")
		ok, why = QS:UsePortal(player, "next", true)
		expect(why).toBe("closed")
		for step = 1, R.Max do
			complete(f.team)
			expect(f.team.village.restoration).toBe(step)
			expect(f.team.acts.bossPortal == true).toBe(step >= R.BossPortalAt)
			expect(f.team.acts.nextPortal == true).toBe(step >= R.NextPortalAt)
			expect(f.team.acts.ancestorPage ~= nil).toBe(step >= R.Max)
		end
		local page = f.team.acts.ancestorPage
		expect(type(page)).toBe("number")
		ok, why = QS:UsePortal(player, "next", true)
		expect(ok).toBe(true)
		expect(why).toBe("stub") -- a placeholder until Act 2
		if #Act1.Quests == R.Max then
			expect(QS.Status(f.team).finished).toBe(true)
			ok, why = QS:Accept(player, true)
			expect(why).toBe("finished")
			ok, why = QS:TurnIn(player, true)
			expect(ok).toBe(false)
		end
		expect(f.team.village.restoration).toBe(R.Max)
		expect(f.team.acts.ancestorPage).toBe(page)
		expect(#QS.Traders(f.team)).toBe(#Act1.Residents)
	end) end)

	it("M8 rewards: a quest can give items and rank XP when they are configured, and a full bag stops the hand-in", function() fixture(function(f)
		complete(f.team)
		local quest = Act1.Quests[2]
		expect(quest.objectives[1].type).toBe("kill")
		quest.rewards = {items = {healing_potion = 2}}
		Act1.QuestXp = 25
		expect(QS:Accept(player, true)).toBe(true)
		f.team.quests.active[quest.id].progress[1] = quest.objectives[1].count
		-- fill every slot of the bag
		for id in pairs(Items.Defs) do
			if IS:FreeSlots(player) <= 0 then break end
			if id ~= "healing_potion" then IS:Give(player, id, 1) end
		end
		expect(IS:FreeSlots(player)).toBe(0)
		local ok, why = QS:TurnIn(player, true)
		expect(ok).toBe(false)
		expect(why).toBe("bag_full")
		expect(f.team.quests.active[quest.id] ~= nil).toBeTruthy()
		expect(f.team.village.restoration).toBe(1)
		f.profile.inventory.items = {}
		f.profile.inventory.hotbar = {}
		local xp = f.profile.rank.xp
		expect(QS:TurnIn(player, true)).toBe(true)
		expect(IS:Count(player, "healing_potion")).toBe(2)
		expect(f.profile.rank.xp).toBe(xp + 25)
	end) end)

	it("M8 residents and the stall: a freed resident is listed as a trader, and the stall sells with or without them", function() fixture(function(f)
		expect(IS:AddCurrency(player, "coins", 500, "audit_m8")).toBe(true)
		local offer = require(ctx.shared.Config.Economy).Shop[1]
		expect(ES:BuyShopItem(player, offer.id)).toBe(true)
		for i, resident in ipairs(Act1.Residents) do
			expect(QS:Rescue(player, resident.id, true)).toBe(true)
			expect(#QS.Traders(f.team)).toBe(i)
			expect(QS.Traders(f.team)[i]).toBe(resident.id)
		end
		expect(ES:BuyShopItem(player, offer.id)).toBe(true)
		expect(IS:Count(player, offer.id)).toBe(offer.count * 2)
	end) end)

	if ServerStorage:GetAttribute("GS_ForceMemoryData") == true and ReplicatedStorage:GetAttribute("DataMode") == "memory" then
		it("M8 saved progress: quests, restoration, portals, residents, lore and the boss flag come back after save and reload", function()
			local Data = require(ServerScriptService.Server.Services.DataService:Clone())
			Data:Init()
			expect(Data:IsMemoryMode()).toBe(true)
			local USER = -1114708
			local team = Data:LoadTeam(USER)
			expect(team ~= nil).toBeTruthy()
			local deliverIndex
			for index, quest in ipairs(Act1.Quests) do
				if index > 1 and quest.objectives[1].type == "deliver" then deliverIndex = index break end
			end
			expect(deliverIndex ~= nil).toBeTruthy()
			local quest = Act1.Quests[deliverIndex]
			for index = 1, deliverIndex - 1 do team.quests.completed[Act1.Quests[index].id] = 100 + index end
			team.quests.active[quest.id] = {size = 2, progress = {1}, acceptedAt = 200}
			team.village.restoration = deliverIndex - 1
			team.village.rescued[Act1.Residents[1].id] = 300
			QS.SyncPortals(team)
			team.acts.lore = {lore_act1_1 = 400}
			team.acts.bossDefeated = 500
			team.acts.ancestorPage = 600
			local portalOpen = team.acts.bossPortal
			Data:ReleaseTeam(USER)
			expect(Data:GetTeam(USER)).toBe(nil)

			local loaded = Data:LoadTeam(USER)
			expect(loaded ~= nil and loaded ~= team).toBeTruthy()
			local status = QS.Status(loaded)
			expect(status.quest.id).toBe(quest.id)
			expect(status.active).toBe(true)
			expect(status.objectives[1].have).toBe(1)
			expect(status.objectives[1].need).toBe(quest.objectives[1].count * Act1.DeliverScale[2])
			expect(loaded.quests.completed[Act1.Quests[1].id]).toBe(101)
			expect(loaded.village.restoration).toBe(deliverIndex - 1)
			expect(loaded.village.rescued[Act1.Residents[1].id]).toBe(300)
			expect(QS.Traders(loaded)[1]).toBe(Act1.Residents[1].id)
			expect(loaded.acts.bossPortal).toBe(portalOpen)
			expect(loaded.acts.bossPortal).toBe(deliverIndex - 1 >= R.BossPortalAt)
			expect(loaded.acts.lore.lore_act1_1).toBe(400)
			expect(loaded.acts.bossDefeated).toBe(500)
			expect(loaded.acts.ancestorPage).toBe(600)
			Data:ReleaseTeam(USER)
		end)
	end
end
