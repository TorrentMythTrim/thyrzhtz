-- Milestone 4 audit continuation (2026-11-14): the "done when" chain end to end and the gaps left by AuditAlchemy.spec.
-- Runs only in a play session (ctx.live); the profile and team are restored after every test.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

return function(it, expect, ctx)
	if not ctx.live then return end
	local Loader = require(ctx.shared.Modules.Loader)
	local Util = require(ctx.shared.Modules.Util)
	local Items = require(ctx.shared.Config.Items)
	local Mushrooms = require(ctx.shared.Config.Mushrooms)
	local Monsters = require(ctx.shared.Config.Monsters)
	local FarmCfg = require(ctx.shared.Config.Farm)
	local Recipes = require(ServerStorage.Config.Recipes)
	local DS, PS, AS = Loader.Get("DataService"), Loader.Get("PartyService"), Loader.Get("AlchemyService")
	local IS, MS = Loader.Get("InventoryService"), Loader.Get("MonsterService")
	local player = game:GetService("Players"):GetPlayers()[1]

	local function fixture(fn)
		local profile = DS:GetProfile(player)
		local team = DS:GetTeam(PS:GetHost(player))
		local savedProfile, savedTeam = Util.DeepCopy(profile), Util.DeepCopy(team)
		profile.skills.alchemist = {}
		profile.inventory.items = {}
		profile.inventory.hotbar = {}
		profile.index = {discovered = {}, claimed = {}, title = ""}
		team.recipes = {known = {}, details = {}}
		team.buildings.alchemy_table = 1
		local ok, err = pcall(fn, profile, team)
		table.clear(profile)
		for k, v in pairs(savedProfile) do profile[k] = v end
		table.clear(team)
		for k, v in pairs(savedTeam) do team[k] = v end
		AS:UpdateTables()
		if not ok then error(err, 0) end
	end

	it("M4 done-when: a recipe learned from a book is mixed and the new mushroom gets an Index entry", function() fixture(function(profile, team)
		profile.inventory.items = {book_novice_alchemist = 1}
		local read, recipeId = AS:ReadBook(player, "book_novice_alchemist")
		expect(read).toBe(true)
		local shown, detail = 0, team.recipes.details[recipeId]
		for _ in pairs(team.recipes.details) do shown += 1 end
		expect(shown).toBe(1) -- the client snapshot carries only what the team has opened
		expect(type(detail)).toBe("table")
		for _, id in ipairs(detail.ingredients) do
			profile.inventory.items[id] = (profile.inventory.items[id] or 0) + 20
		end
		local mixed, species = AS:Mix(player, table.clone(detail.ingredients), true)
		expect(mixed).toBe(true)
		expect(species).toBe(detail.resultSpecies)
		expect(IS:Count(player, Items.MushroomId(species, nil))).toBe(1)
		local entry = profile.index.discovered[species]
		expect(type(entry)).toBe("table")
		expect(entry.base).toBe(true)
		expect(entry.how).toBe("alchemy")
		expect(entry.count).toBe(1)
		expect(type(entry.firstTime)).toBe("number")
		-- the same ingredients in the wrong order: explosion, 10% of each stack, no second mushroom
		local a, b = detail.ingredients[1], detail.ingredients[2]
		if a ~= b then
			local haveA, haveB = IS:Count(player, a), IS:Count(player, b)
			local ok, why = AS:Mix(player, {b, a}, true)
			expect(ok).toBe(false)
			expect(why).toBe("explosion")
			expect(IS:Count(player, a)).toBe(haveA - math.floor(haveA * Recipes.ExplosionLoss + 0.5))
			expect(IS:Count(player, b)).toBe(haveB - math.floor(haveB * Recipes.ExplosionLoss + 0.5))
			expect(IS:Count(player, Items.MushroomId(species, nil))).toBe(1)
			expect(profile.index.discovered[species].count).toBe(1)
		end
	end) end)

	it("M4 every server recipe mixes in its exact order and its result has complete Index card data", function() fixture(function(profile)
		profile.skills.alchemist = {third_slot = 1}
		local templates = ServerStorage.Templates.Mushrooms
		local previews = ReplicatedStorage:FindFirstChild("MushroomPreviews")
		expect(previews ~= nil).toBeTruthy()
		for _, recipe in ipairs(Recipes.List) do
			profile.inventory.items = {}
			for _, id in ipairs(recipe.ingredients) do
				profile.inventory.items[id] = (profile.inventory.items[id] or 0) + 1
			end
			local mixed, species = AS:Mix(player, table.clone(recipe.ingredients), true)
			if not mixed then error(recipe.id .. " did not mix: " .. tostring(species), 0) end
			expect(species).toBe(recipe.resultSpecies)
			local s = Mushrooms.Species[species]
			local function need(cond, what)
				if not cond then error(recipe.id .. " -> " .. species .. ": " .. what, 0) end
			end
			need(s ~= nil, "no species")
			need(s.fromAlchemy == true, "fromAlchemy flag missing, the recipe field would stay hidden")
			need(type(s.name) == "table" and s.name.en and s.name.ru, "name")
			need(FarmCfg.MutationBaseChance[s.rarity] ~= nil, "mutation chance for rarity " .. tostring(s.rarity))
			need(s.element ~= nil or (type(s.elements) == "table" and #s.elements > 0), "element")
			need(templates:FindFirstChild(s.model or "") ~= nil, "appearance template " .. tostring(s.model))
			need(previews:FindFirstChild(s.model or "") ~= nil, "client preview " .. tostring(s.model))
			if s.relatedMonster then
				need(Monsters.Regular[s.relatedMonster] or Monsters.Elite[s.relatedMonster], "related monster " .. s.relatedMonster)
			end
			if s.relatedBoss then need(type(s.relatedBoss) == "table" and s.relatedBoss.en, "related boss name") end
			need(profile.index.discovered[species] and profile.index.discovered[species].how == "alchemy", "Index entry")
		end
	end) end)

	it("M4 the elite Index Keeper drops one mutation book from its pool", function() fixture(function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		expect(root ~= nil).toBeTruthy()
		local mob = MS:Spawn("index_keeper", root.Position + Vector3.new(0, 0, 40), {zone = "audit_m4"})
		expect(mob ~= nil).toBeTruthy()
		MS:OnMonsterKilled(mob, player)
		local books = 0
		for _, bookId in ipairs(Monsters.Elite.index_keeper.bookPool) do
			expect(Items.Defs[bookId] and Items.Defs[bookId].mutationBook).toBeTruthy()
			expect(Recipes.Books[bookId] ~= nil).toBeTruthy()
			books += IS:Count(player, bookId)
		end
		expect(books).toBe(1)
		expect(mob.model.Parent).toBe(nil)
	end) end)

	it("M4 a book opens its recipes one at a time and is not consumed once all are known", function() fixture(function(profile)
		local pool = Recipes.Books.book_novice_alchemist
		profile.inventory.items = {book_novice_alchemist = #pool + 1}
		for i = 1, #pool do
			local ok, id = AS:ReadBook(player, "book_novice_alchemist")
			expect(ok).toBe(true)
			expect(id).toBe(pool[i])
		end
		local ok, why = AS:ReadBook(player, "book_novice_alchemist")
		expect(ok).toBe(false)
		expect(why).toBe("all_known")
		expect(IS:Count(player, "book_novice_alchemist")).toBe(1)
	end) end)
end
