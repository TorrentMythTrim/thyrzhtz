-- Milestone 8 audit (2026-11-14): the boss portal and the Rotten Stump-Lord
-- (technical plan, milestone 8, items 6–7; design doc 1.3, 1.5, 4.5, 7.4).
-- Runs only in a play session (ctx.live). A run made by a test is stepped by the test with its own clock
-- (run.manual), so nothing waits for real seconds; the profile, the team record, health and position are restored.
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
	local Models = require(ServerStorage.Modules.Act1Models)
	local DS, PS, PL = Loader.Get("DataService"), Loader.Get("PartyService"), Loader.Get("PlayerService")
	local IS, MS, CS = Loader.Get("InventoryService"), Loader.Get("MonsterService"), Loader.Get("CombatService")
	local QS, BS = Loader.Get("QuestService"), Loader.Get("BossService")
	local player = game:GetService("Players"):GetPlayers()[1]
	local host = PS:GetHost(player)
	local KILL = 1e7
	local B, P = Act1.Boss, Act1.Portal

	local function hit(mob, base, extra)
		local h = {attacker = player, base = base, attack = 1, noCrit = true}
		for k, v in pairs(extra or {}) do h[k] = v end
		return MS:HitMonster(mob, h)
	end

	-- the team's raid portal is open, the bag is empty and the character cannot die; everything is put back afterwards
	local function fixture(fn)
		local profile = DS:GetProfile(player)
		local team = DS:GetTeam(host)
		local savedProfile, savedTeam = Util.DeepCopy(profile), Util.DeepCopy(team)
		local char = player.Character
		local hum = char:FindFirstChildOfClass("Humanoid")
		local cf, hp, maxHp = char:GetPivot(), hum.Health, hum.MaxHealth
		hum.MaxHealth = 100000
		hum.Health = 100000
		profile.skills.fighter = {}
		profile.gear.armor = 1
		profile.inventory.items = {}
		profile.inventory.hotbar = {}
		team.acts = {current = 1, bossPortal = true, nextPortal = false}
		CS:SetBlock(player, false)
		local ok, err = pcall(fn, {profile = profile, team = team, char = char, hum = hum, home = cf})
		local run = BS:GetRun(host)
		if run then BS:Close(run) end
		player:SetAttribute("InBossPortal", nil)
		local loot = CS:GetPortalLoot(player)
		if loot then table.clear(loot) end
		table.clear(profile)
		for k, v in pairs(savedProfile) do profile[k] = v end
		table.clear(team)
		for k, v in pairs(savedTeam) do team[k] = v end
		hum.MaxHealth = maxHp
		hum.Health = hp
		char:PivotTo(cf)
		PL:Push(player)
		if not ok then error(err, 0) end
	end

	local function enter()
		local ok, why = BS:Enter(player)
		if not ok then error("enter failed: " .. tostring(why), 0) end
		local run = BS:GetRun(host)
		run.manual = true
		return run, os.clock()
	end

	local function killZone(run)
		for _, mob in ipairs(MS:GetAll()) do
			if mob.zone == run.zone then hit(mob, KILL) end
		end
	end

	-- clear the stage rooms; returns the time after the last step
	local function toBoss(run, t)
		while not run.rooms[run.stage].boss do
			killZone(run)
			t += 0.2
			BS:StepRun(run, t)
		end
		expect(run.boss ~= nil).toBeTruthy()
		return t
	end

	local function stageLoot()
		local total = {}
		for _, stage in ipairs(P.Stages) do
			for id, count in pairs(stage.loot or {}) do total[id] = (total[id] or 0) + count end
		end
		return total
	end

	it("M8 config: the portal stages and the boss refer to monsters, items, models and texts that exist, and every arena lies inside the map", function()
		expect(#P.Stages >= 1).toBeTruthy()
		for _, stage in ipairs(P.Stages) do
			expect(#stage.monsters >= 1).toBeTruthy()
			for _, entry in ipairs(stage.monsters) do
				expect((Monsters.Regular[entry[1]] or Monsters.Elite[entry[1]]) ~= nil).toBeTruthy()
				expect(entry[2] >= 1).toBeTruthy()
			end
			for id in pairs(stage.loot or {}) do expect(Items.Defs[id] ~= nil).toBeTruthy() end
			expect(type(Strings.en[stage.lore])).toBe("string")
			expect(type(Strings.ru[stage.lore])).toBe("string")
		end
		-- design doc 7.4: three infected growths, Rot Sprouts as the summons
		expect(B.Growths).toBe(3)
		expect(B.SproutId).toBe("rot_sprout")
		for _, id in ipairs({B.Id, B.GrowthId}) do
			local def = Monsters.Summons[id]
			expect(def ~= nil and type(def.name.en) == "string" and type(def.name.ru) == "string").toBeTruthy()
			expect(ServerStorage.Templates.Monsters:FindFirstChild(def.model) ~= nil).toBeTruthy()
		end
		-- the teleport ability clamps to the map bounds, so an arena outside them would throw players out
		local _, depth = Models.ArenaLayout()
		local bmin, bmax = MapCfg.Bounds.Min, MapCfg.Bounds.Max
		for _, slot in ipairs({1, P.MaxRuns}) do
			local o = BS.Origin(slot).Position
			expect(o.X - P.Width / 2 > bmin.X and o.X + P.Width / 2 < bmax.X).toBeTruthy()
			expect(o.Z > bmin.Y and o.Z + depth < bmax.Y).toBeTruthy()
			expect(o.Y > 100).toBeTruthy()
		end
		expect(BS.Origin(2).Position.Y - BS.Origin(1).Position.Y > P.WallHeight).toBeTruthy()
	end)

	it("M8 portal: closed until the village is restored far enough; a run belongs to the team and starts at stage 1", function() fixture(function(f)
		f.team.acts.bossPortal = false
		local ok, why = QS:UsePortal(player, "raid", true)
		expect(ok).toBe(false)
		expect(why).toBe("closed")
		ok, why = BS:Enter(player)
		expect(why).toBe("closed")
		expect(BS:GetRun(host)).toBe(nil)
		f.team.acts.bossPortal = true
		expect(QS:UsePortal(player, "raid", true)).toBe(true)
		local run = BS:GetRun(host)
		run.manual = true
		expect(run.stage).toBe(1)
		expect(run.players[player]).toBe(true)
		expect(player:GetAttribute("InBossPortal")).toBe(true)
		expect(player:GetAttribute("RaidState")).toBe("stage")
		local want = 0
		for _, entry in ipairs(P.Stages[1].monsters) do want += entry[2] end
		expect(BS:AliveInZone(run)).toBe(want)
		local pos = f.char:GetPivot().Position
		expect(math.abs(pos.Y - run.origin.Position.Y) < 12).toBeTruthy()
		expect(workspace.Act1.Portals:FindFirstChild("Portal_" .. host) ~= nil).toBeTruthy()
		ok, why = BS:Enter(player)
		expect(why).toBe("inside")
	end) end)

	it("M8 stages: a cleared stage adds its loot to the portal loot, shows its lore fragment and opens the way on", function() fixture(function(f)
		local run, t = enter()
		expect(run.model:FindFirstChild("Barrier_1") ~= nil).toBeTruthy()
		BS:StepRun(run, t + 0.2)
		expect(run.stage).toBe(1) -- monsters are alive
		killZone(run)
		BS:StepRun(run, t + 0.4)
		expect(run.stage).toBe(2)
		expect(run.model:FindFirstChild("Barrier_1")).toBe(nil)
		local loot = CS:GetPortalLoot(player)
		for id, count in pairs(P.Stages[1].loot) do
			expect(loot[id]).toBe(count)
			expect(IS:Count(player, id)).toBe(0) -- not in the bag until the player leaves alive
		end
		expect(type(f.team.acts.lore[P.Stages[1].lore])).toBe("number")
		toBoss(run, t + 0.4)
		expect(run.rooms[run.stage].boss).toBe(true)
		expect(#run.growths).toBe(B.Growths)
		for id, count in pairs(stageLoot()) do expect(CS:GetPortalLoot(player)[id]).toBe(count) end
		for _, stage in ipairs(P.Stages) do expect(f.team.acts.lore[stage.lore] ~= nil).toBeTruthy() end
		expect(player:GetAttribute("RaidState")).toBe("boss")
	end) end)

	it("M8 boss: the stump cannot be hurt while a growth stands, the third growth opens the heart, and nothing stuns or moves it", function() fixture(function(f)
		local run, t = enter()
		t = toBoss(run, t)
		local boss = run.boss
		local model = boss.model
		expect(boss.hp).toBe(Monsters.Summons[B.Id].hp)
		expect(hit(boss, 500)).toBe(0)
		expect(boss.hp).toBe(boss.maxHp)
		expect(model:GetAttribute("HeartOpen")).toBe(false)
		expect(model.Heart.Transparency).toBe(1)
		for i, growth in ipairs(run.growths) do
			hit(growth, KILL)
			t += 0.2
			BS:StepRun(run, t)
			expect(player:GetAttribute("RaidGrowths")).toBe(B.Growths - i)
			expect(run.heartOpen).toBe(i == B.Growths)
			if i < B.Growths then expect(hit(boss, 500)).toBe(0) end
		end
		expect(model:GetAttribute("HeartOpen")).toBe(true)
		expect(model.Heart.Transparency).toBe(0)
		expect(model.HeartCover.Bark.Transparency).toBe(1)
		expect(player:GetAttribute("RaidState")).toBe("heart")
		expect(hit(boss, 100)).toBe(100)
		expect(boss.hp).toBe(boss.maxHp - 100)
		hit(boss, 1, {stun = 5, sleep = 5, bind = 5})
		MS:Knockback(boss, f.char:GetPivot().Position, 40)
		t += 0.2
		BS:StepRun(run, t)
		expect(boss.stunUntil).toBe(0)
		expect(boss.sleepUntil).toBe(0)
		expect((model:GetPivot().Position - boss.x.home.Position).Magnitude < 0.05).toBeTruthy()
	end) end)

	it("M8 boss attacks: roots strike along a straight line after a warning and miss a player who steps aside; Rot Sprouts come up to the limit", function() fixture(function(f)
		local from, dir = Vector3.new(10, 5, 10), Vector3.new(0, 0, 1)
		expect(BS.InLine(Vector3.new(10, 0, 30), from, dir, 60, 6)).toBe(true)
		expect(BS.InLine(Vector3.new(12.9, 9, 69), from, dir, 60, 6)).toBe(true)
		expect(BS.InLine(Vector3.new(13.2, 0, 30), from, dir, 60, 6)).toBe(false) -- beside the strip
		expect(BS.InLine(Vector3.new(10, 0, 71), from, dir, 60, 6)).toBe(false) -- beyond its end
		expect(BS.InLine(Vector3.new(10, 0, 9), from, dir, 60, 6)).toBe(false) -- behind the stump

		local run, t = enter()
		t = toBoss(run, t)
		run.nextSummon = t + 1000
		local home = run.boss.x.home.Position
		f.char:PivotTo(CFrame.new(home + Vector3.new(0, 4, -25)))
		run.nextRoot = t
		BS:StepRun(run, t)
		expect(#run.lines).toBe(1)
		expect(run.model:FindFirstChild("RootWarning") ~= nil).toBeTruthy()
		expect(run.nextRoot).toBe(t + B.Root.Interval)
		local before = f.hum.Health
		BS:StepRun(run, t + B.Root.Telegraph - 0.1)
		expect(f.hum.Health).toBe(before) -- the warning does not hurt
		BS:StepRun(run, t + B.Root.Telegraph + 0.01)
		expect(f.hum.Health < before).toBeTruthy()
		expect(#run.lines).toBe(0)
		-- the same again, but the player steps out of the strip before the blow
		t += 20
		run.nextRoot = t
		BS:StepRun(run, t)
		expect(#run.lines).toBe(1)
		f.char:PivotTo(CFrame.new(home + Vector3.new(B.Root.Width * 3, 4, -25)))
		before = f.hum.Health
		BS:StepRun(run, t + B.Root.Telegraph + 0.01)
		expect(f.hum.Health).toBe(before)

		run.nextRoot = t + 1000
		expect(BS:AliveInZone(run, B.SproutId)).toBe(0)
		local expected = 0
		for _ = 1, 4 do
			t += 1
			run.nextSummon = t
			BS:StepRun(run, t)
			expected = math.min(B.Summon.MaxAlive, expected + B.Summon.Count)
			expect(BS:AliveInZone(run, B.SproutId)).toBe(expected)
		end
		expect(expected).toBe(B.Summon.MaxAlive)
	end) end)

	it("M8 victory: killing the heart ends the run — the team keeps the flag, the portal loot goes to the bag and the player is back in the village", function() fixture(function(f)
		local run, t = enter()
		t = toBoss(run, t)
		for _, growth in ipairs(run.growths) do hit(growth, KILL) end
		t += 0.2
		BS:StepRun(run, t)
		expect(run.heartOpen).toBe(true)
		hit(run.boss, KILL)
		expect(run.boss.hp).toBe(0)
		t += 0.2
		BS:StepRun(run, t)
		expect(run.state).toBe("won")
		expect(type(f.team.acts.bossDefeated)).toBe("number")
		expect(f.team.acts.bossKills).toBe(1)
		expect(BS:AliveInZone(run)).toBe(0)
		expect(player:GetAttribute("RaidState")).toBe("won")
		expect(player:GetAttribute("InBossPortal")).toBe(true)
		local ok, why = BS:Enter(player)
		expect(why).toBe("inside")
		BS:StepRun(run, t + P.ExitSeconds - 1)
		expect(BS:GetRun(host)).toBe(run) -- still inside until the time is up
		BS:StepRun(run, t + P.ExitSeconds + 0.1)
		expect(BS:GetRun(host)).toBe(nil)
		expect(player:GetAttribute("InBossPortal")).toBe(nil)
		expect(player:GetAttribute("RaidState")).toBe(nil)
		expect(workspace.Act1.Portals:FindFirstChild("Portal_" .. host)).toBe(nil)
		for id, count in pairs(stageLoot()) do expect(IS:Count(player, id)).toBe(count) end
		local portal = workspace.Map.Village.PortalRaid:GetPivot().Position
		local pos = f.char:GetPivot().Position
		expect(Vector3.new(pos.X - portal.X, 0, pos.Z - portal.Z).Magnitude < 20).toBeTruthy()
		-- the raid can be entered again; the flag stays
		expect(BS:Enter(player)).toBe(true)
		expect(BS:GetRun(host).stage).toBe(1)
		expect(type(f.team.acts.bossDefeated)).toBe("number")
	end) end)

	it("M8 leaving: death loses everything found inside and closes an empty run; walking out keeps the loot", function() fixture(function(f)
		local run, t = enter()
		killZone(run)
		BS:StepRun(run, t + 0.2)
		expect(next(CS:GetPortalLoot(player)) ~= nil).toBeTruthy()
		expect(BS:Leave(player, "death")).toBe(true)
		local loot = CS:GetPortalLoot(player)
		expect(loot == nil or next(loot) == nil).toBeTruthy()
		expect(BS:GetRun(host)).toBe(nil)
		expect(BS:AliveInZone(run)).toBe(0)
		for id in pairs(P.Stages[1].loot) do expect(IS:Count(player, id)).toBe(0) end
		f.char:PivotTo(f.home) -- the arena is gone: do not let the character fall while waiting
		task.wait(1.7)
		expect(player:GetAttribute("InBossPortal")).toBe(nil)

		run, t = enter()
		expect(run.stage).toBe(1) -- a new run starts from the beginning
		killZone(run)
		BS:StepRun(run, t + 0.2)
		expect(BS:Leave(player, "exit")).toBe(true)
		for id, count in pairs(P.Stages[1].loot) do expect(IS:Count(player, id)).toBe(count) end
		expect(BS:GetRun(host)).toBe(nil)
		expect(player:GetAttribute("InBossPortal")).toBe(nil)
	end) end)
end
