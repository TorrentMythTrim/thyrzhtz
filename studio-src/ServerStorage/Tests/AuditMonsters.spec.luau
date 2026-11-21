-- Milestone 5 audit continuation (2026-11-14): the full monster roster of design doc 4.6–4.7.
-- Every one of the 10 regular and 5 elite types is spawned, fought and killed; each type's own mechanic is exercised.
-- The AI is driven with MonsterService:StepMob and simulated time, so the tests do not wait for real seconds.
-- Runs only in a play session (ctx.live); profile, team, health and position are restored after every test.
local ServerStorage = game:GetService("ServerStorage")

return function(it, expect, ctx)
	if not ctx.live then return end
	local Loader = require(ctx.shared.Modules.Loader)
	local Util = require(ctx.shared.Modules.Util)
	local Monsters = require(ctx.shared.Config.Monsters)
	local MapCfg = require(ctx.shared.Config.Map)
	local FarmCfg = require(ctx.shared.Config.Farm)
	local DayNight = require(ctx.shared.Formulas.DayNight)
	local Behaviors = require(ServerStorage.Modules.MonsterBehaviors)
	local DS, PS, HS = Loader.Get("DataService"), Loader.Get("PartyService"), Loader.Get("HouseService")
	local CS, MS, IS = Loader.Get("CombatService"), Loader.Get("MonsterService"), Loader.Get("InventoryService")
	local FS, WS = Loader.Get("FarmService"), Loader.Get("WeatherService")
	local Templates = ServerStorage.Templates.Monsters
	local player = game:GetService("Players"):GetPlayers()[1]
	local ZONE = "audit_m5"
	local KILL = 1e7

	local function garden()
		local plot = HS:GetPlot(player)
		return plot and plot.model:FindFirstChild("Garden")
	end

	local function fixture(fn)
		local profile = DS:GetProfile(player)
		local team = DS:GetTeam(PS:GetHost(player))
		local savedProfile, savedTeam = Util.DeepCopy(profile), Util.DeepCopy(team)
		local char = player.Character
		local hum, root = char:FindFirstChildOfClass("Humanoid"), char.HumanoidRootPart
		local cf, hp, maxHp = char:GetPivot(), hum.Health, hum.MaxHealth
		-- an empty corner of the map, standing on whatever ground is there
		local hit = workspace:Raycast(Vector3.new(600, 500, 640), Vector3.new(0, -1000, 0))
		char:PivotTo(CFrame.new(600, hit and hit.Position.Y + 3.2 or 25, 640))
		hum.MaxHealth = 100000
		hum.Health = 100000
		profile.skills.fighter = {}
		profile.gear.armor = 1
		profile.inventory.items = {}
		profile.inventory.hotbar = {}
		CS:SetBlock(player, false)
		local ok, err = pcall(fn, {profile = profile, team = team, char = char, hum = hum, root = root, grounded = hit ~= nil})
		MS:ClearAll(ZONE)
		Behaviors.Sweep(os.clock() + 1000) -- burns out trails and bed fires left by the test
		table.clear(profile)
		for k, v in pairs(savedProfile) do profile[k] = v end
		table.clear(team)
		for k, v in pairs(savedTeam) do team[k] = v end
		for _, bed in ipairs(garden() and garden():GetChildren() or {}) do
			local idx = bed:IsA("BasePart") and bed.Name:match("^Bed_(%d+)$")
			if idx then FS:ApplyBed(bed, team.garden.beds[idx], DayNight.Current().id, WS:Get()) end
		end
		hum.MaxHealth = maxHp
		hum.Health = hp
		hum.WalkSpeed = MapCfg.WalkSpeed
		char:PivotTo(cf)
		if not ok then error(err, 0) end
	end

	local function spawnAt(id, offset, opts)
		opts = opts or {}
		opts.zone = ZONE
		local r = player.Character.HumanoidRootPart.Position
		local mob = MS:Spawn(id, Vector3.new(r.X, r.Y - 3, r.Z) + offset, opts)
		if not mob then error("spawn failed: " .. id, 0) end
		return mob
	end

	local function run(mob, seconds, t)
		for _ = 1, math.ceil(seconds / 0.1) do
			t += 0.1
			MS:StepMob(mob, 0.1, t)
		end
		return t
	end

	local function hit(mob, base, extra)
		local h = {attacker = player, base = base, attack = 1, noCrit = true}
		for k, v in pairs(extra or {}) do h[k] = v end
		return MS:HitMonster(mob, h)
	end

	-- The first bed of the player's garden. A fresh profile has no bed placed, so one is placed for the test.
	local function builtBed(team)
		local bed = garden() and garden():FindFirstChild("Bed_1")
		if not bed then error("the player's plot has no Bed_1", 0) end
		team.garden.beds["1"] = team.garden.beds["1"] or Util.DeepCopy(FarmCfg.Bed)
		MS:AffectBed(bed, 0, 0)
		if not bed:GetAttribute("Built") then error("Bed_1 could not be placed", 0) end
		return bed, team.garden.beds["1"]
	end

	local function countMobs(id)
		local n = 0
		for _, m in ipairs(MS:GetAll()) do
			if m.id == id and m.zone == ZONE then n += 1 end
		end
		return n
	end

	it("M5 roster: all 10 regular and 5 elite types have full config and a template, spawn, take damage and die with rewards", function() fixture(function(f)
		local count = {regular = 0, elite = 0}
		for group, defs in pairs({regular = Monsters.Regular, elite = Monsters.Elite}) do
			for id, def in pairs(defs) do
				count[group] += 1
				local function need(cond, what)
					if not cond then error(id .. ": " .. what, 0) end
				end
				for _, k in ipairs({"hp", "damage", "speed", "attackRange", "attackCooldown", "xp"}) do
					need(type(def[k]) == "number", "config field " .. k)
				end
				need(type(def.name) == "table" and def.name.en and def.name.ru, "name")
				need(type(def.coins) == "table" and type(def.dust) == "table", "rewards")
				local tmpl = Templates:FindFirstChild(def.model or "")
				need(tmpl and tmpl.PrimaryPart and tmpl.PrimaryPart.Name == "Root", "template " .. tostring(def.model))
				local mob = spawnAt(id, Vector3.new(0, 0, 30))
				need(mob.model.Parent == workspace.Monsters, "model in workspace.Monsters")
				need(mob.model:GetAttribute("MonsterId") == id and mob.model:GetAttribute("MaxHP") == def.hp, "attributes")
				need(mob.model:GetAttribute("Elite") == (group == "elite"), "elite flag")
				if group == "elite" then need(def.poise and mob.model:GetAttribute("MaxPoise") == def.poise, "poise bar") end
				local coins, dealt = f.profile.currencies.coins, 0
				for _ = 1, 4 do dealt += (hit(mob, def.hp / 10, {burnsShield = true})) end
				need(dealt > 0 and mob.hp < mob.maxHp, "takes damage")
				local _, status = hit(mob, KILL, {burnsShield = true})
				need(status == "killed", "dies, got " .. tostring(status))
				need(mob.model.Parent == nil, "model removed")
				need(f.profile.currencies.coins > coins, "coins for the kill")
			end
		end
		expect(count.regular).toBe(10)
		expect(count.elite).toBe(5)
	end) end)

	it("M5 every type fights: next to a player each of the 15 hurts the player", function() fixture(function(f)
		for _, defs in ipairs({Monsters.Regular, Monsters.Elite}) do
			for id in pairs(defs) do
				f.hum.Health = f.hum.MaxHealth
				local mob = spawnAt(id, Vector3.new(0, 0, -3))
				hit(mob, 1) -- wakes the burrowed and the peaceful ones
				run(mob, 8, os.clock())
				if f.hum.Health >= f.hum.MaxHealth then error(id .. " did not damage the player in 8 simulated seconds", 0) end
				MS:ClearAll(ZONE)
				Behaviors.Sweep(os.clock() + 1000)
			end
		end
	end) end)

	it("M5 Mist Double copies the player's look and one slotted ability, casts it, and takes 1.5x from light", function() fixture(function(f)
		f.profile.combat.abilitySlots = {"thunder_hedgehog", "", ""}
		local mob = spawnAt("mist_double", Vector3.new(0, 0, -12))
		local t = os.clock()
		MS:StepMob(mob, 0.1, t + 0.1)
		expect(mob.model:FindFirstChild("Disguise") ~= nil).toBeTruthy()
		expect(mob.model.Disguise:FindFirstChildOfClass("Humanoid") ~= nil).toBeTruthy()
		expect(mob.model:GetAttribute("CopiedPlayer")).toBe(player.UserId)
		expect(mob.model:GetAttribute("CopiedAbility")).toBe("thunder_hedgehog")
		expect(mob.model.MistBody:FindFirstChildWhichIsA("BasePart").Transparency).toBe(1)
		local before = f.hum.Health
		MS:StepMob(mob, 0.1, t + 2.5) -- the first cast is ready 2 s after spawn
		expect(mob.x.casts).toBe(1)
		expect(f.hum.Health < before).toBeTruthy()
		local dummy = spawnAt("mist_double", Vector3.new(60, 0, 0), {hpFactor = 100})
		local plain = hit(dummy, 100)
		local light = hit(dummy, 100, {element = "light"})
		expect(light / plain).toNear(Monsters.Regular.mist_double.lightWeakness, 0.1)
	end) end)

	it("M5 Crystal Tick latches on, slows and bites; six quick presses throw it off, old presses do not count", function() fixture(function(f)
		local def = Monsters.Regular.crystal_tick
		local mob = spawnAt("crystal_tick", Vector3.new(0, 0, -5))
		local t = os.clock()
		MS:StepMob(mob, 0.1, t + 0.1)
		expect(player:GetAttribute("TickLatched")).toBe(def.shakePresses)
		expect(mob.model:GetAttribute("LatchedOn")).toBe(player.UserId)
		MS:StepMob(mob, 0.1, t + 0.2)
		expect(f.hum.WalkSpeed).toNear(MapCfg.WalkSpeed * (1 - def.latchSlow), 0.01)
		-- it rides along when the player moves, and keeps biting
		f.char:PivotTo(f.char:GetPivot() + Vector3.new(30, 0, 0))
		local before = f.hum.Health
		MS:StepMob(mob, 0.1, t + 1.3)
		expect((mob.model:GetPivot().Position - f.root.Position).Magnitude < 3).toBeTruthy()
		expect(f.hum.Health < before).toBeTruthy()
		-- presses older than the window are forgotten
		local c = os.clock()
		mob.x.presses = {c - 10, c - 9, c - 8, c - 7, c - 6}
		expect(MS:ShakeOff(player)).toBe(false)
		expect(player:GetAttribute("TickLatched")).toBe(def.shakePresses - 1)
		for _ = 1, def.shakePresses - 2 do expect(MS:ShakeOff(player)).toBe(false) end
		expect(MS:ShakeOff(player)).toBe(true)
		expect(player:GetAttribute("TickLatched")).toBe(nil)
		expect(f.hum.WalkSpeed).toNear(MapCfg.WalkSpeed, 0.01)
		expect((mob.model:GetPivot().Position - f.root.Position).Magnitude > 5).toBeTruthy()
		expect(mob.stunUntil > os.clock()).toBeTruthy()
		expect(MS:ShakeOff(player)).toBe(false)
		-- killing a latched tick frees the player as well
		local second = spawnAt("crystal_tick", Vector3.new(0, 0, -4))
		MS:StepMob(second, 0.1, os.clock() + 0.1)
		expect(player:GetAttribute("TickLatched")).toBe(def.shakePresses)
		hit(second, KILL)
		expect(player:GetAttribute("TickLatched")).toBe(nil)
		expect(f.hum.WalkSpeed).toNear(MapCfg.WalkSpeed, 0.01)
	end) end)

	it("M5 Ash Hound leaves a burning trail that hurts and burns out, and sets garden beds on fire", function() fixture(function(f)
		local def = Monsters.Regular.ash_hound
		local mob = spawnAt("ash_hound", Vector3.new(0, 0, -40))
		local t = run(mob, 1, os.clock())
		expect(mob.x.patches >= 3).toBeTruthy()
		local hazards = workspace:FindFirstChild("MonsterHazards")
		local patch = hazards and hazards:FindFirstChild("FireTrail")
		expect(patch ~= nil).toBeTruthy()
		expect(patch:FindFirstChildOfClass("Fire") ~= nil).toBeTruthy()
		MS:ClearAll(ZONE)
		f.char:PivotTo(CFrame.new(patch.Position + Vector3.new(0, 3, 0)))
		local before = f.hum.Health
		Behaviors.Sweep(t + 0.6)
		expect(f.hum.Health < before).toBeTruthy()
		Behaviors.Sweep(t + def.trailSeconds + 1)
		expect(hazards:FindFirstChild("FireTrail")).toBe(nil)
		-- a hound next to a bed sets it alight; the fire eats the bed's health, then dies down
		local bed, data = builtBed(f.team)
		f.char:PivotTo(CFrame.new(bed.Position + Vector3.new(0, 3, 8)))
		local healthBefore = data.health or FarmCfg.Bed.health
		local hound = MS:Spawn("ash_hound", bed.Position + Vector3.new(3, 0, 0), {zone = ZONE})
		hound.nextAttack = math.huge -- only the fire may damage the bed in this check
		local t2 = os.clock()
		MS:StepMob(hound, 0.1, t2 + 0.1)
		expect(bed:FindFirstChild("MonsterFire") ~= nil).toBeTruthy()
		MS:ClearAll(ZONE)
		Behaviors.Sweep(t2 + 0.2)
		Behaviors.Sweep(t2 + 1.3)
		expect((data.health or FarmCfg.Bed.health) < healthBefore).toBeTruthy()
		Behaviors.Sweep(t2 + 10)
		expect(bed:FindFirstChild("MonsterFire")).toBe(nil)
	end) end)

	it("M5 Void Cloak stays half-transparent, teleports behind the player, shows itself for a second, then strikes", function() fixture(function(f)
		local def = Monsters.Regular.void_cloak
		local mob = spawnAt("void_cloak", Vector3.new(0, 0, -20))
		local cloth = mob.model:FindFirstChild("Cloak")
		expect(mob.model:GetAttribute("Cloaked")).toBe(true)
		expect(cloth.Transparency).toNear(def.cloakTransparency, 0.01)
		local t = os.clock() + 1.1 -- the first teleport is ready a second after spawn
		MS:StepMob(mob, 0.1, t)
		local rel = mob.model:GetPivot().Position - f.root.Position
		rel = Vector3.new(rel.X, 0, rel.Z)
		expect(mob.x.teleports).toBe(1)
		expect(rel.Magnitude <= def.attackRange).toBeTruthy()
		expect(rel.Unit:Dot(f.root.CFrame.LookVector) < -0.9).toBeTruthy()
		-- the same step starts the reveal: fully visible, no damage yet
		expect(mob.model:GetAttribute("Cloaked")).toBe(false)
		expect(cloth.Transparency).toNear(0, 0.01)
		local before = f.hum.Health
		MS:StepMob(mob, 0.1, t + 0.5)
		expect(f.hum.Health).toBe(before)
		MS:StepMob(mob, 0.1, t + def.revealSeconds + 0.05)
		expect(f.hum.Health < before).toBeTruthy()
		expect(mob.model:GetAttribute("Cloaked")).toBe(true)
		expect(cloth.Transparency).toNear(def.cloakTransparency, 0.01)
	end) end)

	it("M5 Swarm Mother builds a nest every 5 s up to 10; nests release mosquitoes; a hit interrupts her and she attacks the offender", function() fixture(function(f)
		local def = Monsters.Elite.swarm_mother
		local mob = spawnAt("swarm_mother", Vector3.new(0, 0, -20))
		local t = os.clock()
		MS:StepMob(mob, 0.1, t + 0.1)
		expect(mob.model:GetAttribute("Building")).toBe(true)
		local stood = mob.model:GetPivot().Position
		MS:StepMob(mob, 0.1, t + def.nestBuildSeconds - 0.2)
		expect(#mob.x.nests).toBe(0)
		MS:StepMob(mob, 0.1, t + def.nestBuildSeconds + 0.2)
		expect(#mob.x.nests).toBe(1)
		expect((mob.model:GetPivot().Position - stood).Magnitude < 0.01).toBeTruthy() -- she stands still while building
		local nest = mob.x.nests[1]
		expect(nest.model:GetAttribute("MonsterId")).toBe("swarm_nest")
		-- the nest sends out a mosquito and keeps to its brood limit
		t += def.nestBuildSeconds + 0.2
		MS:StepMob(nest, 0.1, t + 3)
		expect(#nest.x.brood).toBe(1)
		expect(nest.x.brood[1].id).toBe("spore_mosquito")
		MS:StepMob(nest, 0.1, t + 30)
		expect(countMobs("spore_mosquito")).toBe(1)
		-- a hit interrupts the next build and turns her on the attacker
		MS:StepMob(mob, 0.1, t + 0.1)
		expect(mob.model:GetAttribute("Building")).toBe(true)
		hit(mob, 5)
		expect(mob.model:GetAttribute("Building")).toBe(false)
		expect(mob.x.buildDoneAt).toBe(nil)
		local r = os.clock()
		local far = (mob.model:GetPivot().Position - f.root.Position).Magnitude
		MS:StepMob(mob, 0.5, r + 0.1)
		expect((mob.model:GetPivot().Position - f.root.Position).Magnitude < far).toBeTruthy()
		f.char:PivotTo(CFrame.new(mob.model:GetPivot().Position + Vector3.new(0, 3, 3)))
		local before = f.hum.Health
		MS:StepMob(mob, 0.1, r + 0.2)
		expect(f.hum.Health < before).toBeTruthy()
		-- left alone she fills the field up to the limit and stops there
		local s = r + def.interruptSeconds + 0.1
		for _ = 1, def.maxNests + 3 do
			MS:StepMob(mob, 0.1, s)
			s += def.nestBuildSeconds + 0.1
			MS:StepMob(mob, 0.1, s)
		end
		expect(#mob.x.nests).toBe(def.maxNests)
		expect(countMobs("swarm_nest")).toBe(def.maxNests)
		-- a destroyed nest is gone for good; she replaces it after one more build
		local victim = mob.x.nests[1]
		hit(victim, KILL)
		expect(victim.model.Parent).toBe(nil)
		MS:StepMob(mob, 0.1, s + 0.1)
		expect(mob.model:GetAttribute("Nests")).toBe(def.maxNests - 1)
		MS:StepMob(mob, 0.1, s + 0.2 + def.nestBuildSeconds)
		expect(mob.model:GetAttribute("Nests")).toBe(def.maxNests)
		-- killing her takes the nests with her
		hit(mob, KILL)
		expect(countMobs("swarm_nest")).toBe(0)
	end) end)

	it("M5 Mold Gardener infects beds and spreads a blight field whose damage grows the longer the player stays", function() fixture(function(f)
		local def = Monsters.Elite.mold_gardener
		local mob = spawnAt("mold_gardener", Vector3.new(0, 0, -10))
		mob.nextAttack = math.huge -- only the blight may hurt in this test
		local t = os.clock() + 0.1
		MS:StepMob(mob, 0.1, t)
		local zone = workspace.MonsterHazards:FindFirstChild("BlightZone")
		expect(zone ~= nil).toBeTruthy()
		expect(mob.model:GetAttribute("BlightRadius")).toBe(def.blightStartRadius)
		expect(player:GetAttribute("BlightStacks")).toBe(nil) -- the player is still outside the field
		f.char:PivotTo(CFrame.new(mob.x.center + Vector3.new(0, 3, 0)))
		local dealt = {}
		for i = 1, 4 do
			local before = f.hum.Health
			MS:StepMob(mob, 0.1, t + i * (def.blightTick + 0.05))
			dealt[i] = before - f.hum.Health
		end
		expect(dealt[1]).toBe(def.blightBaseDamage)
		expect(dealt[2] > dealt[1] and dealt[3] > dealt[2] and dealt[4] > dealt[3]).toBeTruthy()
		expect(player:GetAttribute("BlightStacks")).toBe(4)
		-- the field keeps growing while the fight goes on, and stops while he is staggered
		local r0 = mob.x.radius
		run(mob, 5, t + 10)
		expect(mob.x.radius > r0 + 3).toBeTruthy()
		expect(zone.Size.Y > r0 * 2 + 6).toBeTruthy()
		mob.staggerUntil = t + 100
		local held = mob.x.radius
		run(mob, 3, t + 20)
		expect(mob.x.radius).toBe(held)
		mob.staggerUntil = 0
		-- leaving the field clears the stacks
		f.char:PivotTo(CFrame.new(mob.x.center + Vector3.new(def.blightMaxRadius + 20, 3, 0)))
		MS:StepMob(mob, 0.1, t + 40)
		expect(player:GetAttribute("BlightStacks")).toBe(nil)
		-- he waters the beds around him with mold
		local bed, data = builtBed(f.team)
		local infectionBefore = data.infection or 0
		local second = MS:Spawn("mold_gardener", bed.Position + Vector3.new(4, 0, 0), {zone = ZONE})
		second.nextAttack = math.huge
		MS:StepMob(second, 0.1, os.clock() + 1.1)
		expect((data.infection or 0) > infectionBefore).toBeTruthy()
		-- stopping him removes the field
		hit(mob, KILL)
		expect(zone.Parent).toBe(nil)
	end) end)

	it("M5 every type also goes for the garden: with no player in reach each of the 15 damages or infects a bed", function() fixture(function(f)
		local bed, data = builtBed(f.team)
		f.char:PivotTo(CFrame.new(bed.Position + Vector3.new(0, 3, 300)))
		for _, defs in ipairs({Monsters.Regular, Monsters.Elite}) do
			for id in pairs(defs) do
				data.health, data.infection = FarmCfg.Bed.health, 0
				local mob = MS:Spawn(id, bed.Position + Vector3.new(4, 0, 0), {zone = ZONE})
				hit(mob, 1) -- wakes the burrowed and the peaceful ones; the attacker is far out of reach
				run(mob, 15, os.clock())
				if data.health >= FarmCfg.Bed.health and data.infection <= 0 then
					error(id .. " left the bed untouched for 15 simulated seconds", 0)
				end
				MS:ClearAll(ZONE)
				Behaviors.Sweep(os.clock() + 1000)
			end
		end
	end) end)

	it("M5 Act 1 types keep their mechanics: leap, split, theft, ambush, treasure route, night-only, keeper cast, mosquito burst", function() fixture(function(f)
		local t = os.clock()
		-- Rot Sprout closes the distance with a leap
		local sprout = spawnAt("rot_sprout", Vector3.new(0, 0, -10))
		sprout.nextLeap = 0
		local p0 = sprout.model:GetPivot().Position
		MS:StepMob(sprout, 0.1, t + 0.1)
		expect((sprout.model:GetPivot().Position - p0).Magnitude > Monsters.Regular.rot_sprout.speed * 0.1 * 2).toBeTruthy()
		-- Mold Slug splits in two after 20 s of fighting
		local slug = spawnAt("mold_slug", Vector3.new(30, 0, 0))
		hit(slug, 1)
		MS:StepMob(slug, 0.1, t + Monsters.Regular.mold_slug.splitsAfter + 1)
		expect(slug.model.Parent).toBe(nil)
		expect(countMobs("mold_slug")).toBe(2)
		-- Fly Agaric Bandit steals a mushroom and gives it back when killed
		f.profile.inventory.items.mushroom_fly_agaric = 2
		local bandit = spawnAt("fly_agaric_bandit", Vector3.new(0, 0, 3))
		MS:StepMob(bandit, 0.1, t + 0.1)
		expect(bandit.stolenItem).toBe("mushroom_fly_agaric")
		expect(IS:Count(player, "mushroom_fly_agaric")).toBe(1)
		hit(bandit, KILL)
		expect(IS:Count(player, "mushroom_fly_agaric")).toBe(2)
		-- Root Hunter waits underground and surfaces with its first strike
		local hunter = spawnAt("root_hunter", Vector3.new(0, 0, -3))
		expect(hunter.model:GetAttribute("Burrowed")).toBe(true)
		local before = f.hum.Health
		MS:StepMob(hunter, 0.1, t + 0.1)
		expect(hunter.model:GetAttribute("Burrowed")).toBe(false)
		expect(f.hum.Health < before).toBeTruthy()
		-- Spore Carrier left alone walks its route and leaves a stash
		local function chests()
			local n = 0
			for _, c in ipairs(workspace:GetChildren()) do
				if c.Name == "CarrierTreasure" then n += 1 end
			end
			return n
		end
		local chestsBefore = chests()
		local carrier = spawnAt("spore_carrier", Vector3.new(80, 0, 0))
		for _ = 1, 40 do MS:StepMob(carrier, 5, t) end
		expect(carrier.model.Parent).toBe(nil)
		expect(chests()).toBe(chestsBefore + 1)
		-- Moon Reaper belongs to the night: by day an unprovoked one leaves (a Blood Moon keeps it)
		local reaper = spawnAt("moon_reaper", Vector3.new(-70, 0, 0))
		MS:StepMob(reaper, 0.1, t + 0.1)
		expect(reaper.model.Parent ~= nil).toBe(DayNight.Current().id == "night" or WS:Get() == "blood_moon")
		-- Index Keeper casts a random mushroom ability: it heals itself or hurts the player
		local keeper = spawnAt("index_keeper", Vector3.new(0, 0, -4))
		keeper.nextAttack = math.huge
		keeper.hp = keeper.maxHp - 100
		local keeperHp, health = keeper.hp, f.hum.Health
		keeper.nextCast = 0
		MS:StepMob(keeper, 0.1, t + 0.1)
		expect(keeper.hp > keeperHp or f.hum.Health < health).toBeTruthy()
		-- Spore Mosquito bursts a moment after it dies
		MS:ClearAll(ZONE)
		if f.grounded then
			local mosquito = spawnAt("spore_mosquito", Vector3.new(0, 0, -3))
			hit(mosquito, KILL)
			local hpNow = f.hum.Health
			task.wait(0.6)
			expect(f.hum.Health < hpNow).toBeTruthy()
		end
	end) end)
end
