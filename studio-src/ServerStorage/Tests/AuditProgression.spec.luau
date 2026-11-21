-- Milestone 7 audit (2026-11-14): currency journal, what every upgrade and skill changes in the game, rank experience
-- sources, shop rules and saved progress (design doc 6.1-6.5).
-- Live tests restore the profile, the team record, health and position after every test. No DataStore is touched:
-- the save-and-reload test runs only in forced memory mode, on a separate copy of DataService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

return function(it, expect, ctx)
	local Economy = require(ctx.shared.Config.Economy)
	local Items = require(ctx.shared.Config.Items)
	local Mushrooms = require(ctx.shared.Config.Mushrooms)
	local MonstersCfg = require(ctx.shared.Config.Monsters)
	local DefenseCfg = require(ctx.shared.Config.Defense)
	local CombatCfg = require(ctx.shared.Config.Combat)
	local FarmCfg = require(ctx.shared.Config.Farm)
	local MapCfg = require(ctx.shared.Config.Map)
	local Price = require(ctx.shared.Formulas.Price)
	local Growth = require(ctx.shared.Formulas.Growth)
	local Util = require(ctx.shared.Modules.Util)
	local EconomySim = require(ctx.shared.Modules.EconomySim)
	local Services = ServerScriptService.Server.Services
	local EconomyService = require(Services.EconomyService)
	local AlchemyService = require(Services.AlchemyService)
	local LOOP_SECONDS = 2

	it("upgrades: the nine of step 6.1, a rising price for every level and no level without an effect", function()
		local planned = {"sickle", "basket", "armor", "garden", "house", "alchemy_table", "spore_press", "forge", "totems"}
		local count = 0
		for _ in pairs(Economy.Upgrades) do count += 1 end
		expect(count).toBe(#planned)
		for _, id in ipairs(planned) do
			local def = Economy.Upgrades[id]
			expect(def ~= nil).toBeTruthy()
			local prev = 0
			for level = (def.startLevel or 1) + 1, def.maxLevel do
				local cost = Price.UpgradeCost(def, level)
				expect(cost > prev).toBeTruthy()
				prev = cost
			end
		end
		-- every forge level opens a recipe, and no recipe asks for a level that cannot be bought
		for level = 1, Economy.Upgrades.forge.maxLevel do
			local opens = false
			for _, recipe in ipairs(Economy.ForgeRecipes) do
				if recipe.reqForge == level then opens = true end
				expect(recipe.reqForge <= Economy.Upgrades.forge.maxLevel).toBeTruthy()
			end
			expect(opens).toBeTruthy()
		end
		-- garden: less soil wear; alchemy table: chance of an extra spore; house: healing per second
		local E = Economy.UpgradeEffects
		expect(Growth.SoilWearMultiplier(1, E.GardenSoilWearCutPerLevel)).toBe(1)
		expect(Growth.SoilWearMultiplier(5, E.GardenSoilWearCutPerLevel)).toNear(1 - 4 * E.GardenSoilWearCutPerLevel)
		local worn = Growth.ApplyHarvestWear({soil = 100, nutrition = 50})
		local spared = Growth.ApplyHarvestWear({soil = 100, nutrition = 50},
			Growth.SoilWearMultiplier(Economy.Upgrades.garden.maxLevel, E.GardenSoilWearCutPerLevel))
		expect(worn.soil).toBe(100 - FarmCfg.BedEffects.HarvestSoilLoss)
		expect(spared.soil > worn.soil).toBeTruthy()
		expect(spared.nutrition).toBe(worn.nutrition)
		local tableMax = Economy.Upgrades.alchemy_table.maxLevel
		expect(AlchemyService.BonusSporeChance(1)).toBe(0)
		expect(AlchemyService.BonusSporeChance(tableMax)).toNear(E.TableBonusSporeChancePerLevel * (tableMax - 1))
		expect(EconomyService.HouseHealPerTick(1)).toBe(E.HouseHealPerSecondPerLevel * LOOP_SECONDS)
		expect(EconomyService.HouseHealPerTick(4)).toBe(4 * E.HouseHealPerSecondPerLevel * LOOP_SECONDS)
	end)

	it("ranks and skills: eight ranks in the order of step 6.2 and the three branches of step 6.3", function()
		local ranks = {"gatherer", "gardener", "pathfinder", "keeper", "spore_master", "island_guardian", "mycelium_keeper", "primordial_guardian"}
		expect(#Economy.Ranks).toBe(#ranks)
		local prev = -1
		for i, id in ipairs(ranks) do
			expect(Economy.Ranks[i].id).toBe(id)
			expect(Economy.Ranks[i].xp > prev).toBeTruthy()
			prev = Economy.Ranks[i].xp
			expect(EconomyService.RankInfo(prev)).toBe(i)
		end
		expect(EconomyService.RankInfo(prev - 1)).toBe(#ranks - 1)
		local branches = {
			gardener = {"more_beds", "faster_growth", "mutation_chance", "harvest_quality"},
			fighter = {"more_damage", "new_combos", "dodge"},
			alchemist = {"stronger_potions", "longer_effects", "third_slot", "hints"},
		}
		local count = 0
		for branch, list in pairs(Economy.Skills) do
			count += 1
			expect(branches[branch] ~= nil).toBeTruthy()
			expect(#list).toBe(#branches[branch])
			for i, id in ipairs(branches[branch]) do
				expect(list[i]).toBe(id)
				expect(Economy.SkillDefs[id].branch).toBe(branch)
				expect(Economy.SkillDefs[id].max >= 1).toBeTruthy()
			end
		end
		expect(count).toBe(3)
	end)

	it("shop: seeds, recipes, materials and a cosmetic for coins, nothing from the forbidden list of step 6.5", function()
		local kinds, inShop = {}, {}
		for _, offer in ipairs(Economy.Shop) do
			local def = Items.Defs[offer.id]
			expect(def ~= nil and offer.coins > 0 and offer.count >= 1).toBeTruthy()
			kinds[def.kind] = true
			inShop[offer.id] = true
			expect(def.kind ~= "weapon").toBeTruthy()
			if def.species then
				local species = Mushrooms.Species[def.species]
				expect(species.relatedBoss == nil and species.rarity ~= "mythic" and species.rarity ~= "primordial").toBeTruthy()
			end
		end
		expect(kinds.spore and kinds.book and kinds.reagent and kinds.cosmetic).toBeTruthy()
		-- Star Seal goods are not sold for coins
		for _, offer in ipairs(Economy.StarSealShop) do
			if offer.itemId then expect(inShop[offer.itemId] == nil).toBeTruthy() end
		end
	end)

	it("balance model: the simulation uses the prices the game charges and counts exploration experience", function()
		local bed, firstWeapon
		for _, offer in ipairs(Economy.Shop) do
			if offer.id == "empty_bed" then bed = offer end
		end
		for _, recipe in ipairs(Economy.ForgeRecipes) do
			if recipe.id == "guardian_sickle" then firstWeapon = recipe end
		end
		expect(bed.coins).toBe(55)
		expect(firstWeapon.coins).toBe(120)
		expect(firstWeapon.sporeDust).toBe(45)
		local run, again = EconomySim.SimulateHours(3, 2026), EconomySim.SimulateHours(3, 2026)
		expect(run.finalXp).toBe(again.finalXp)
		local maxSum = 0
		for _, def in pairs(Economy.Upgrades) do maxSum += def.maxLevel end
		expect(run.maxUpgradeSum).toBe(maxSum)
		local X = Economy.ExplorationXp
		local keep = {X.monsterType, X.eliteType, X.territory}
		X.monsterType, X.eliteType, X.territory = 0, 0, 0
		local ok, without = pcall(EconomySim.SimulateHours, 3, 2026)
		X.monsterType, X.eliteType, X.territory = keep[1], keep[2], keep[3]
		expect(ok).toBeTruthy()
		expect(run.finalXp - without.finalXp).toBe(#MonstersCfg.Act1Regular * keep[1] + #MonstersCfg.Act1Elite * keep[2] + keep[3])
	end)

	if not ctx.live then return end

	local Loader = require(ctx.shared.Modules.Loader)
	local DS, PS, PL = Loader.Get("DataService"), Loader.Get("PartyService"), Loader.Get("PlayerService")
	local ES, IS, XS = Loader.Get("EconomyService"), Loader.Get("InventoryService"), Loader.Get("IndexService")
	local CS, MS, DF = Loader.Get("CombatService"), Loader.Get("MonsterService"), Loader.Get("DefenseService")
	local HS, FS, AS = Loader.Get("HouseService"), Loader.Get("FarmService"), Loader.Get("AlchemyService")
	local player = game:GetService("Players"):GetPlayers()[1]
	local ZONE = "audit_m7"

	local function character()
		for _ = 1, 80 do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then return char, hum, root end
			task.wait(0.25)
		end
		error("no living character", 0)
	end

	local function waitFor(condition)
		for _ = 1, 40 do
			if condition() then return true end
			task.wait(0.1)
		end
		return condition()
	end

	local function fixture(fn)
		local profile = DS:GetProfile(player)
		local host = PS:GetHost(player)
		local team = DS:GetTeam(host)
		local savedProfile, savedTeam = Util.DeepCopy(profile), Util.DeepCopy(team)
		local char, hum, root = character()
		local cf, hp = char:GetPivot(), hum.Health
		local ok, err = pcall(fn, profile, team, hum, root)
		MS:ClearAll(ZONE)
		table.clear(profile)
		for k, v in pairs(savedProfile) do profile[k] = v end
		table.clear(team)
		for k, v in pairs(savedTeam) do team[k] = v end
		if char.Parent then char:PivotTo(cf) end
		ES:ApplyArmorHealth(player)
		if hum.Health > 0 then hum.Health = math.min(hp, hum.MaxHealth) end
		ES:SyncPlotBuildings()
		AS:UpdateTables()
		PL:Push(player)
		PL:PushTeam(host)
		if not ok then error(err, 0) end
	end

	local function killOne(root, id)
		local mob = MS:Spawn(id, root.Position + Vector3.new(0, 0, 8), {zone = ZONE})
		if not mob then error("spawn failed", 0) end
		local xp = mob.def.xp
		MS:OnMonsterKilled(mob, player)
		return xp
	end

	it("currencies: every earn and spend is in the server journal with its source, and the journal adds up to the balance", function()
		fixture(function(profile, team, _, root)
			profile.ledger = {}
			profile.currencies = {coins = 2000, sporeDust = 2000, crystals = 20, starSeals = 5}
			local start = Util.DeepCopy(profile.currencies)
			profile.gear = {sickle = 1, basket = 3, armor = 1}
			profile.skills = {points = 0, gardener = {}, fighter = {more_damage = 1}, alchemist = {}}
			profile.inventory.items = {basket = 1, simple_sickle = 1, mushroom_fly_agaric = 6, mushroom_stone_polypore = 1}
			profile.inventory.hotbar = {}
			team.buildings.spore_press = 1
			team.buildings.forge = 1
			team.buildings.totems = 0

			expect(ES:BuyUpgrade(player, "sickle")).toBe(true)
			expect(ES:BuyUpgrade(player, "basket")).toBe(true)
			expect(ES:BuyUpgrade(player, "totems")).toBe(true)
			expect(ES:BuyShopItem(player, "spore_fly_agaric")).toBe(true)
			expect(ES:SellMushroom(player, "mushroom_fly_agaric", 2)).toBe(true)
			expect(ES:UsePress(player, "dust", "mushroom_fly_agaric")).toBe(true)
			expect(ES:ForgeWeapon(player, "guardian_sickle")).toBe(true)
			expect(IS:Count(player, "guardian_sickle")).toBe(1)
			expect(IS:Count(player, "mushroom_stone_polypore")).toBe(0)
			expect(ES:SellAllMushrooms(player)).toBe(true)
			expect(IS:Count(player, "mushroom_fly_agaric")).toBe(0)
			expect(ES:BuyStarSeal(player, "star_catalyst")).toBe(true)
			expect(ES:BuyStarSeal(player, "respec_skills")).toBe(true)
			expect(profile.skills.points).toBe(1)
			killOne(root, "rot_sprout")

			-- a second forge of the same weapon is refused and writes nothing
			local entries = #profile.ledger
			expect(ES:ForgeWeapon(player, "guardian_sickle")).toBe(false)
			expect(#profile.ledger).toBe(entries)

			local sum = {coins = 0, sporeDust = 0, crystals = 0, starSeals = 0}
			local running = Util.DeepCopy(start)
			local sources = {}
			for _, entry in ipairs(profile.ledger) do
				sum[entry.cur] += entry.delta
				running[entry.cur] += entry.delta
				expect(entry.bal).toBe(running[entry.cur])
				expect(type(entry.why) == "string" and entry.why ~= "" and entry.why ~= "general").toBeTruthy()
				sources[string.match(entry.why, "^[^:]+")] = true
			end
			for currency, amount in pairs(start) do
				expect(profile.currencies[currency]).toBe(amount + sum[currency])
			end
			for _, source in ipairs({"upgrade", "shop_buy", "sell", "press_dust", "forge", "sell_all", "seal", "seal_respec", "kill"}) do
				expect(sources[source]).toBe(true)
			end
			expect(sum.crystals < 0 and sum.starSeals == -2).toBeTruthy()
			expect(#profile.ledger <= Economy.LedgerMaxEntries).toBeTruthy()
		end)
	end)

	it("refused operations change nothing: no currency, no item and no journal line", function()
		fixture(function(profile, team)
			profile.inventory.items = {basket = 1, mushroom_stone_polypore = 1, mushroom_fly_agaric = 1}
			profile.inventory.hotbar = {}
			profile.currencies = {coins = 500, sporeDust = 10, crystals = 0, starSeals = 0}
			profile.ledger = {}
			profile.combat.ownedPets = {sprout_buddy = true}
			profile.skills = {points = 0, gardener = {}, fighter = {}, alchemist = {}}
			profile.rank = {xp = 0, rewardedTier = 1}
			team.buildings.forge = 1
			team.buildings.spore_press = 0
			team.buildings.totems = 0

			expect(ES:ForgeWeapon(player, "guardian_sickle")).toBe(false) -- not enough dust
			expect(ES:ForgeWeapon(player, "mushroom_hammer")).toBe(false) -- forge level too low
			expect(ES:UsePress(player, "dust", "mushroom_fly_agaric")).toBe(false) -- press not built
			expect(ES:BuyUpgrade(player, "totems")).toBe(false) -- no crystals
			expect(ES:BuyUpgrade(player, "no_such_upgrade")).toBe(false)
			expect(ES:BuyStarSeal(player, "star_catalyst")).toBe(false)
			expect(ES:BuyStarSeal(player, "astral_sporeling")).toBe(false)
			expect(ES:UpgradeSkill(player, "more_damage")).toBe(false) -- no skill points
			for _, id in ipairs({"book_void_spores", "star_catalyst", "guardian_sickle", "mushroom_fly_agaric", "research_book", "no_such_item"}) do
				expect(ES:BuyShopItem(player, id)).toBe(false)
			end
			expect(ES:SellMushroom(player, "basket", 1)).toBe(false) -- only mushrooms are bought back

			expect(profile.currencies.coins).toBe(500)
			expect(profile.currencies.sporeDust).toBe(10)
			expect(profile.currencies.crystals).toBe(0)
			expect(profile.currencies.starSeals).toBe(0)
			expect(IS:Count(player, "basket")).toBe(1)
			expect(IS:Count(player, "mushroom_stone_polypore")).toBe(1)
			expect(IS:Count(player, "mushroom_fly_agaric")).toBe(1)
			expect(IS:Count(player, "guardian_sickle")).toBe(0)
			expect(#profile.ledger).toBe(0)
			expect(profile.combat.ownedPets.astral_sporeling).toBe(nil)
			expect(team.buildings.totems).toBe(0)
		end)
	end)

	it("rank experience: combat, the Index and exploration raise it; a first kill of a type and a first visit to a territory pay once", function()
		fixture(function(profile, _, _, root)
			profile.rank = {xp = 0, rewardedTier = 1}
			profile.stats.seenMonsters = nil
			profile.stats.seenTerritories = nil
			profile.index = {discovered = {}, claimed = {}, title = ""}

			local killXp = killOne(root, "rot_sprout")
			expect(profile.rank.xp).toBe(killXp + Economy.ExplorationXp.monsterType)
			expect(profile.stats.seenMonsters.rot_sprout).toBe(true)
			expect(killOne(root, "rot_sprout")).toBe(killXp)
			expect(profile.rank.xp).toBe(2 * killXp + Economy.ExplorationXp.monsterType)

			local before = profile.rank.xp
			local _, eliteXp = ES:Explore(player, "monster", "mycelium_knight", {elite = true})
			expect(eliteXp).toBe(Economy.ExplorationXp.eliteType)
			expect(ES:Explore(player, "monster", "mycelium_knight", {elite = true})).toBe(false)
			expect(ES:Explore(player, "monster", "swarm_nest", {})).toBe(false) -- a summon is not a monster type
			expect(profile.rank.xp).toBe(before + eliteXp)

			before = profile.rank.xp
			ES:CheckTerritories(player)
			expect(profile.rank.xp).toBe(before) -- home is not a new territory
			local garden = MapCfg.OldGarden
			local home = root.CFrame
			root.CFrame = CFrame.new(garden.Center.X, root.Position.Y, garden.Center.Y)
			ES:CheckTerritories(player)
			ES:CheckTerritories(player)
			root.CFrame = home
			expect(profile.rank.xp).toBe(before + Economy.ExplorationXp.territory)
			expect(profile.stats.seenTerritories.old_garden).toBe(true)

			before = profile.rank.xp
			local found = XS:Discover(player, "fly_agaric", nil, "harvest")
			expect(found.xp > 0).toBeTruthy()
			expect(profile.rank.xp).toBe(before + found.xp)
			for _, xp in pairs(Economy.HarvestXp) do expect(xp > 0).toBeTruthy() end

			-- the experience above is worth a rank, and the rank pays its skill points
			expect(profile.skills.points ~= nil).toBeTruthy()
			local points = profile.skills.points
			expect(ES:AddXp(player, Economy.Ranks[2].xp)).toBe(true)
			expect(EconomyService.RankInfo(profile.rank.xp) >= 2).toBeTruthy()
			expect(profile.skills.points > points).toBeTruthy()
		end)
	end)

	it("upgrades in the game: sickle, basket, armor, spore press and totems change what the services compute", function()
		fixture(function(profile, team, hum)
			for _ = 1, 120 do
				if not player:GetAttribute("Berserk") then break end
				task.wait(0.25)
			end
			profile.skills = {points = 0, gardener = {}, fighter = {}, alchemist = {}}
			profile.gear = {sickle = 1, basket = 1, armor = 1}

			-- spore press: +15% dust per level
			local rarity = Mushrooms.Species.fly_agaric.rarity
			profile.inventory.items = {basket = 1, mushroom_fly_agaric = 2}
			profile.inventory.hotbar = {}
			team.buildings.spore_press = 1
			local dustBefore = profile.currencies.sporeDust
			local ok1, dust1 = ES:UsePress(player, "dust", "mushroom_fly_agaric")
			team.buildings.spore_press = 5
			local ok5, dust5 = ES:UsePress(player, "dust", "mushroom_fly_agaric")
			expect(ok1 and ok5).toBeTruthy()
			expect(dust1).toBe(Economy.PressDustYield[rarity])
			expect(dust5).toBe(math.floor(Economy.PressDustYield[rarity] * 1.6 + 0.5))
			expect(profile.currencies.sporeDust).toBe(dustBefore + dust1 + dust5)
			expect(IS:Count(player, "mushroom_fly_agaric")).toBe(0)

			-- sickle: +10% damage per level
			local attack = CS:AttackMultiplier(player)
			profile.gear.sickle = 4
			expect(CS:AttackMultiplier(player)).toNear(attack * 1.3, 1e-4)

			-- basket: +4 slots and +5% sale price per level
			local slots = IS:MaxSlots(player)
			local price = EconomyService.SellValue(profile, "mushroom_thunder_hedgehog")
			profile.gear.basket = 5
			expect(IS:MaxSlots(player)).toBe(slots + 16)
			expect(EconomyService.SellValue(profile, "mushroom_thunder_hedgehog") > price).toBeTruthy()

			-- armor: +12 max health per level
			profile.gear.armor = 3
			ES:ApplyArmorHealth(player)
			expect(hum.MaxHealth).toBe(CombatCfg.PlayerMaxHealth + 24)

			-- totems: the gate gets its extra health as soon as the level changes
			local gate = HS:GetPlot(player).model.Defense.PlotGate
			local perLevel = Economy.UpgradeEffects.TotemGateHpPerLevel
			team.buildings.totems = 0
			DF:SyncGateVisual(HS:GetPlot(player).model)
			expect(waitFor(function() return gate:GetAttribute("MaxHP") == DefenseCfg.Gate.MaxHP end)).toBe(true)
			local hpBefore = gate:GetAttribute("HP")
			team.buildings.totems = 2
			expect(waitFor(function() return gate:GetAttribute("MaxHP") == DefenseCfg.Gate.MaxHP + 2 * perLevel end)).toBe(true)
			if hpBefore > 0 then expect(gate:GetAttribute("HP")).toBe(hpBefore + 2 * perLevel) end
		end)
	end)

	it("skills in the game: damage, combo finisher, dodge, effect length, mutation luck, sale price, third slot and hints follow the learned level", function()
		fixture(function(profile, _, hum)
			profile.skills = {points = 0, gardener = {}, fighter = {}, alchemist = {}}
			profile.gear = {sickle = 1, basket = 1, armor = 1}
			local effects = Economy.SkillEffects

			local attack = CS:AttackMultiplier(player)
			profile.skills.fighter.more_damage = 5
			expect(CS:AttackMultiplier(player)).toNear(attack * 1.4, 1e-4)

			expect(CS.ComboFinisherMultiplier(profile, 1.35)).toBe(1.35)
			profile.skills.fighter.new_combos = 5
			expect(CS.ComboFinisherMultiplier(profile, 1.35)).toNear(1.35 * (1 + 5 * effects.ComboFinisherPerLevel))

			expect(CS.EffectDuration(profile, 10)).toBe(10)
			profile.skills.alchemist.longer_effects = 5
			expect(CS.EffectDuration(profile, 10)).toNear(10 * (1 + 5 * effects.LongerEffectsPerLevel))

			local luck = FS:LuckOf(player)
			profile.skills.gardener.mutation_chance = 3
			expect(FS:LuckOf(player)).toBe(luck + 3 * FarmCfg.MutationFactors.LuckPerSkillLevel)

			local price = EconomyService.SellValue(profile, "mushroom_thunder_hedgehog")
			profile.skills.gardener.harvest_quality = 5
			expect(EconomyService.SellValue(profile, "mushroom_thunder_hedgehog") > price).toBeTruthy()

			expect(AS:UnlockedSlots(player)).toBe(2)
			expect(AS:HasHints(player)).toBe(false)
			profile.skills.alchemist.third_slot = 1
			profile.skills.alchemist.hints = 1
			expect(AS:UnlockedSlots(player)).toBe(3)
			expect(AS:HasHints(player)).toBe(true)

			-- dodge: a level far above the cap makes the chance certain; without the skill the same hit lands
			CS:SetBlock(player, false)
			hum.Health = hum.MaxHealth
			local hp = hum.Health
			profile.skills.fighter.dodge = 25
			local dealt, how = CS:DamagePlayer(player, 1)
			expect(dealt).toBe(0)
			expect(how).toBe("dodged")
			expect(hum.Health).toBe(hp)
			profile.skills.fighter.dodge = 0
			expect(CS:DamagePlayer(player, 1) > 0).toBeTruthy()
		end)
	end)

	if ServerStorage:GetAttribute("GS_ForceMemoryData") == true and ReplicatedStorage:GetAttribute("DataMode") == "memory" then
		it("saved progress: upgrades, rank, skills and the journal come back after save and reload and still drive the game", function()
			local Data = require(Services.DataService:Clone())
			Data:Init()
			expect(Data:IsMemoryMode()).toBe(true)
			local USER = -1114701
			local function bot()
				local fake = {UserId = USER, Name = "AuditBot" .. USER, DisplayName = "AuditBot", Parent = workspace, attrs = {}}
				function fake:Kick(message) self.kicked = message or true end
				function fake:SetAttribute(key, value) self.attrs[key] = value end
				function fake:GetAttribute(key) return self.attrs[key] end
				return fake
			end

			local first = bot()
			local profile, team = Data:LoadProfile(first), Data:LoadTeam(USER)
			expect(profile ~= nil and team ~= nil).toBeTruthy()
			profile.gear.sickle, profile.gear.basket, profile.gear.armor = 4, 3, 2
			profile.rank.xp = Economy.Ranks[3].xp + 5
			local earned = EconomyService.CheckRankUps(profile)
			expect(earned).toBe(Economy.Ranks[2].skillPoints + Economy.Ranks[3].skillPoints)
			profile.skills.alchemist.third_slot = 1
			profile.skills.fighter.more_damage = 2
			profile.skills.points -= 3
			profile.stats.seenMonsters = {rot_sprout = true}
			expect(IS.ApplyCurrency(profile, "coins", 250, "audit_save")).toBe(true)
			team.buildings.alchemy_table, team.buildings.spore_press, team.buildings.forge, team.buildings.totems = 4, 2, 3, 1
			team.garden.level = 5
			team.house.level = 3
			expect(Data:ReleaseProfile(first)).toBe(true)
			Data:ReleaseTeam(USER)
			expect(Data:GetProfile(first)).toBe(nil)
			expect(Data:GetTeam(USER)).toBe(nil)

			local second = bot()
			local loaded, loadedTeam = Data:LoadProfile(second), Data:LoadTeam(USER)
			expect(loaded ~= nil and loadedTeam ~= nil).toBeTruthy()
			expect(loaded ~= profile and loadedTeam ~= team).toBeTruthy()
			local levels = {sickle = 4, basket = 3, armor = 2, garden = 5, house = 3, alchemy_table = 4, spore_press = 2, forge = 3, totems = 1}
			for id, level in pairs(levels) do
				expect(EconomyService.GetUpgradeLevel(loaded, loadedTeam, id)).toBe(level)
			end
			expect(EconomyService.RankInfo(loaded.rank.xp)).toBe(3)
			expect(loaded.rank.rewardedTier).toBe(3)
			expect(EconomyService.CheckRankUps(loaded)).toBe(0) -- rank points are not paid a second time
			expect(loaded.skills.points).toBe(earned - 3)
			expect(loaded.skills.alchemist.third_slot).toBe(1)
			expect(loaded.skills.fighter.more_damage).toBe(2)
			expect(loaded.currencies.coins).toBe(250)
			expect(loaded.ledger[#loaded.ledger].why).toBe("audit_save")
			expect(loaded.stats.seenMonsters.rot_sprout).toBe(true)
			-- the loaded values feed the same calculations the game uses
			expect(EconomyService.SellValue(loaded, "mushroom_thunder_hedgehog") > EconomyService.SellValue({gear = {basket = 1}}, "mushroom_thunder_hedgehog")).toBeTruthy()
			expect(AlchemyService.BonusSporeChance(loadedTeam.buildings.alchemy_table) > 0).toBeTruthy()
			expect(Data:ReleaseProfile(second)).toBe(true)
			Data:ReleaseTeam(USER)
		end)
	end
end
