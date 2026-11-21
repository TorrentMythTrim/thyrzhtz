-- Milestone 5 audit continuation (2026-11-14): weapon effects, elemental reactions and death rules checked in a live fight.
-- AuditCombat.spec proves that every weapon hits; this spec proves what each hit does (design doc 4.2–4.5).
-- Runs only in a play session (ctx.live); profile, health and position are restored after every test.
return function(it, expect, ctx)
	if not ctx.live then return end
	local Loader = require(ctx.shared.Modules.Loader)
	local Util = require(ctx.shared.Modules.Util)
	local CombatCfg = require(ctx.shared.Config.Combat)
	local DS, CS, MS, IS = Loader.Get("DataService"), Loader.Get("CombatService"), Loader.Get("MonsterService"), Loader.Get("InventoryService")
	local player = game:GetService("Players"):GetPlayers()[1]
	local ZONE = "audit_m5_live"

	local function fixture(fn)
		local profile = DS:GetProfile(player)
		local saved = Util.DeepCopy(profile)
		local char = player.Character
		local hum, root = char:FindFirstChildOfClass("Humanoid"), char.HumanoidRootPart
		local cf, hp, maxHp, slot = char:GetPivot(), hum.Health, hum.MaxHealth, player:GetAttribute("HotbarSlot")
		local ground = workspace:Raycast(Vector3.new(600, 500, 560), Vector3.new(0, -1000, 0))
		char:PivotTo(CFrame.new(600, ground and ground.Position.Y + 3.2 or 25, 560))
		hum.MaxHealth = 100000
		hum.Health = 100000
		local ok, err = pcall(fn, {profile = profile, char = char, hum = hum, root = root})
		MS:ClearAll(ZONE)
		CS:SetBlock(player, false)
		player:SetAttribute("InBossPortal", nil)
		table.clear(profile)
		for k, v in pairs(saved) do profile[k] = v end
		hum.MaxHealth = maxHp
		hum.Health = hp
		char:PivotTo(cf)
		IS:SelectSlot(player, slot or 0)
		if not ok then error(err, 0) end
	end

	local function spawnNear(root, offset)
		local mob = MS:Spawn("rot_sprout", Vector3.new(root.Position.X, root.Position.Y - 3, root.Position.Z) + offset, {zone = ZONE, hpFactor = 200})
		if not mob then error("spawn failed", 0) end
		return mob
	end

	it("M5 weapons in a fight: staff cycles poison, slow and sleep; hammer stuns and breaks armor; bow binds", function() fixture(function(f)
		f.profile.inventory.items = {spore_staff = 1, mushroom_hammer = 1, mycelium_bow = 1}
		f.profile.inventory.hotbar = {}
		local function swing(weaponId)
			IS:SetHotbar(player, 6, weaponId)
			IS:SelectSlot(player, 6)
			task.wait(1.7) -- longer than the slowest weapon cooldown
			MS:ClearAll(ZONE)
			local mob = spawnNear(f.root, Vector3.new(0, 0, -4))
			local ok, why = CS:Attack(player, Vector3.new(0, 0, -1))
			if not ok then error(weaponId .. " attack rejected: " .. tostring(why), 0) end
			return mob, os.clock()
		end
		local seen = {}
		for _ = 1, 3 do
			local spore = player:GetAttribute("StaffNextSpore")
			local mob, now = swing("spore_staff")
			if spore == "poison" then expect(mob.poisonUntil > now).toBeTruthy()
			elseif spore == "slow" then expect(mob.slowUntil > now).toBeTruthy()
			elseif spore == "sleep" then expect(mob.sleepUntil > now).toBeTruthy()
			else error("unknown staff spore " .. tostring(spore), 0) end
			seen[spore] = true
		end
		expect(seen.poison and seen.slow and seen.sleep).toBeTruthy()
		local hammered, t1 = swing("mushroom_hammer")
		expect(hammered.stunUntil > t1).toBeTruthy()
		expect(hammered.armorBrokenUntil > t1).toBeTruthy()
		local bound, t2 = swing("mycelium_bow")
		expect(bound.bindUntil > t2).toBeTruthy()
	end) end)

	it("M5 all five elemental reactions fire on real monsters with their own effect", function() fixture(function(f)
		local function pair()
			MS:ClearAll(ZONE)
			return spawnNear(f.root, Vector3.new(60, 0, 0)), spawnNear(f.root, Vector3.new(66, 0, 0))
		end
		local function react(a, first, second)
			MS:HitMonster(a, {attacker = player, base = 10, attack = 1, noCrit = true, element = first})
			MS:HitMonster(a, {attacker = player, base = 10, attack = 1, noCrit = true, element = second})
		end
		-- every key of the config table is one of the plan's five reactions (air + spores has a second spelling)
		local ids = {}
		for _, r in pairs(CombatCfg.Reactions) do ids[r.id] = true end
		for _, id in ipairs({"chain_discharge", "toxic_blast", "crystal_wall", "void_rift", "spore_cloud"}) do
			if not ids[id] then error("reaction missing in config: " .. id, 0) end
		end

		local a, b = pair()
		react(a, "water", "lightning") -- chain discharge jumps to the neighbour
		expect(b.hp < b.maxHp).toBeTruthy()

		a, b = pair()
		react(a, "poison", "fire") -- toxic blast hurts everything around
		expect(b.hp < b.maxHp).toBeTruthy()

		a, b = pair()
		local wallsBefore = 0
		for _, c in ipairs(workspace:GetChildren()) do if c.Name == "CrystalWall" then wallsBefore += 1 end end
		react(a, "ice", "earth") -- crystal wall: a real wall and a short freeze
		local walls = 0
		for _, c in ipairs(workspace:GetChildren()) do if c.Name == "CrystalWall" then walls += 1 end end
		expect(walls).toBe(wallsBefore + 1)
		expect(a.stunUntil > os.clock()).toBeTruthy()

		a, b = pair()
		local gap = (a.model:GetPivot().Position - b.model:GetPivot().Position).Magnitude
		react(a, "light", "darkness") -- void rift pulls the neighbour in and hurts it
		expect((a.model:GetPivot().Position - b.model:GetPivot().Position).Magnitude < gap).toBeTruthy()
		expect(b.hp < b.maxHp).toBeTruthy()

		a, b = pair()
		react(a, "spores", "air") -- spore cloud poisons and slows the group
		expect(b.poisonUntil > os.clock() and b.slowUntil > os.clock()).toBeTruthy()
	end) end)

	it("M5 death: loot gathered inside a boss portal is lost; in the world the surviving monsters heal", function() fixture(function(f)
		player:SetAttribute("InBossPortal", true)
		CS:AddPortalLoot(player, "mycelium_essence", 2)
		expect(CS:GetPortalLoot(player).mycelium_essence).toBe(2)
		CS:OnCharacterDied(player)
		expect(CS:GetPortalLoot(player)).toBe(nil)
		player:SetAttribute("InBossPortal", nil)
		local mob = spawnNear(f.root, Vector3.new(40, 0, 0))
		MS:HitMonster(mob, {attacker = player, base = 50, attack = 1, noCrit = true})
		expect(mob.hp < mob.maxHp).toBeTruthy()
		CS:OnCharacterDied(player)
		expect(mob.hp).toBe(mob.maxHp)
	end) end)
end
