-- Milestone 6 audit continuation (2026-11-14): the weather cycle, what weather does to a real fight, fog ghosts,
-- waves by weather and the parts of the help call that one player in Studio can exercise (design doc 5.1–5.4).
-- Runs only in a play session (ctx.live); weather, profile, team, health and position are restored after every test.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(it, expect, ctx)
	if not ctx.live then return end
	local Loader = require(ctx.shared.Modules.Loader)
	local Util = require(ctx.shared.Modules.Util)
	local Weather = require(ctx.shared.Config.Weather)
	local DefenseCfg = require(ctx.shared.Config.Defense)
	local Monsters = require(ctx.shared.Config.Monsters)
	local DS, PS, WS, DF = Loader.Get("DataService"), Loader.Get("PartyService"), Loader.Get("WeatherService"), Loader.Get("DefenseService")
	local MS, DN = Loader.Get("MonsterService"), Loader.Get("DayNightService")
	local player = game:GetService("Players"):GetPlayers()[1]
	local ZONE = "audit_m6"
	local KILL = {base = 1e7, attack = 1, noCrit = true, burnsShield = true}

	local function fixture(fn)
		local profile = DS:GetProfile(player)
		local team = DS:GetTeam(PS:GetHost(player))
		local savedProfile, savedTeam = Util.DeepCopy(profile), Util.DeepCopy(team)
		local weather = WS:Get()
		local char = player.Character
		local hum, root = char:FindFirstChildOfClass("Humanoid"), char.HumanoidRootPart
		local cf, hp, maxHp = char:GetPivot(), hum.Health, hum.MaxHealth
		local ground = workspace:Raycast(Vector3.new(600, 500, 480), Vector3.new(0, -1000, 0))
		char:PivotTo(CFrame.new(600, ground and ground.Position.Y + 3.2 or 25, 480))
		hum.MaxHealth = 100000
		hum.Health = 100000
		profile.skills.fighter = {}
		profile.gear.armor = 1
		local ok, err = pcall(fn, {profile = profile, team = team, char = char, hum = hum, root = root})
		MS:ClearAll(ZONE)
		WS:Set(weather, false)
		table.clear(profile)
		for k, v in pairs(savedProfile) do profile[k] = v end
		table.clear(team)
		for k, v in pairs(savedTeam) do team[k] = v end
		hum.MaxHealth = maxHp
		hum.Health = hp
		char:PivotTo(cf)
		if not ok then error(err, 0) end
	end

	local function weatherMobs(id)
		local n = 0
		for _, m in ipairs(MS:GetAll()) do
			if m.zone == "weather" and (id == nil or m.id == id) then n += 1 end
		end
		return n
	end

	local function waveMobs(host)
		local list = {}
		for _, m in ipairs(MS:GetAll()) do
			if m.waveHost == host then table.insert(list, m) end
		end
		return list
	end

	it("M6 weather is one shared state cycling through the seven plan types; the next roll is never the current one", function() fixture(function()
		local listed = {}
		for _, id in ipairs(Weather.Order) do listed[id] = true end
		for _, id in ipairs({"clear", "rain", "thunderstorm", "fog", "spore_rain", "snow", "blood_moon"}) do
			if not listed[id] then error("weather missing: " .. id, 0) end
		end
		expect(#Weather.Order).toBe(7) -- the Eclipse is an endgame event, not a weather
		expect(Weather.ChangeEverySeconds.Min > 0 and Weather.ChangeEverySeconds.Max >= Weather.ChangeEverySeconds.Min).toBeTruthy()
		local rolled = {}
		for _, id in ipairs(Weather.Order) do
			expect(WS:Set(id, false)).toBe(true)
			expect(WS:Get()).toBe(id)
			expect(ReplicatedStorage:GetAttribute("Weather")).toBe(id)
			for _ = 1, 60 do
				local nxt = WS:RollNext()
				if nxt == id then error("rolled the current weather again: " .. id, 0) end
				rolled[nxt] = true
			end
		end
		for _, id in ipairs(Weather.Order) do
			if not rolled[id] then error("weather never rolled: " .. id, 0) end
		end
	end) end)

	it("M6 weather changes a real fight: the same monster bites harder in dangerous weather and the player's multiplier follows the table", function() fixture(function(f)
		local base = Monsters.Regular.rot_sprout.damage
		for _, id in ipairs(Weather.Order) do
			local w = Weather.Types[id]
			WS:Set(id, false)
			f.hum.Health = f.hum.MaxHealth
			local mob = MS:Spawn("rot_sprout", Vector3.new(f.root.Position.X, f.root.Position.Y - 3, f.root.Position.Z - 3), {zone = ZONE})
			MS:StepMob(mob, 0.1, os.clock() + 0.1)
			MS:ClearAll(ZONE)
			local bite = f.hum.MaxHealth - f.hum.Health
			if bite ~= math.floor(base * (w.monsterDamage or 1) + 0.5) then
				error(string.format("%s: bite %s, expected %s x %s", id, tostring(bite), tostring(base), tostring(w.monsterDamage or 1)), 0)
			end
			expect(DF:CombatMultipliersAt(f.root.Position).player).toNear(w.playerDamage or 1, 1e-6)
		end
		expect(Weather.Types.blood_moon.monsterDamage > 1 and Weather.Types.spore_rain.monsterDamage > 1).toBeTruthy()
		expect(Weather.Types.fog.playerDamage < 1 and Weather.Types.snow.playerDamage < 1).toBeTruthy()
	end) end)

	it("M6 fog brings ghost enemies and a hidden trail; monsters brought by a weather leave with it unless someone is fighting them", function() fixture(function()
		local ghosts = Weather.Types.fog.ghosts
		expect(ghosts ~= nil and ghosts.count > 0).toBeTruthy()
		expect(Monsters.Regular[ghosts.id] ~= nil).toBeTruthy()
		WS:Set("clear", false)
		MS:ClearAll("weather")
		WS:Set("fog", false)
		expect(weatherMobs(ghosts.id)).toBe(ghosts.count)
		expect(workspace.WeatherWorld:FindFirstChild("FogStep_1") ~= nil).toBeTruthy()
		WS:Set("rain", false)
		expect(weatherMobs(ghosts.id)).toBe(0)
		expect(weatherMobs("mold_slug")).toBe(2)
		WS:Set("rain", false) -- setting the same weather again must not stack more monsters
		expect(weatherMobs("mold_slug")).toBe(2)
		for _, m in ipairs(MS:GetAll()) do
			if m.zone == "weather" then
				MS:HitMonster(m, {attacker = player, base = 1, attack = 1, noCrit = true})
				break
			end
		end
		WS:Set("clear", false)
		expect(weatherMobs("mold_slug")).toBe(1) -- the one in a fight stays for the fight
		MS:ClearAll("weather")
	end) end)

	it("M6 a Moon Reaper stays through a daytime Blood Moon and leaves once the weather turns", function() fixture(function(f)
		local phase = DN:GetPhase()
		expect(DN:SetPhase("day")).toBe(true)
		local ok, err = pcall(function()
			WS:Set("blood_moon", false)
			local reaper = MS:Spawn("moon_reaper", Vector3.new(f.root.Position.X + 80, f.root.Position.Y - 3, f.root.Position.Z), {zone = ZONE})
			MS:StepMob(reaper, 0.1, os.clock() + 0.1)
			expect(reaper.model.Parent ~= nil).toBe(true)
			WS:Set("clear", false)
			MS:StepMob(reaper, 0.1, os.clock() + 0.2)
			expect(reaper.model.Parent).toBe(nil)
		end)
		DN:SetPhase(phase)
		if not ok then error(err, 0) end
	end) end)

	it("M6 waves come only with the five dangerous weathers, are announced before they arrive and scale with the party", function() fixture(function(f)
		for _, id in ipairs(Weather.Order) do
			local dangerous = id == "thunderstorm" or id == "fog" or id == "spore_rain" or id == "snow" or id == "blood_moon"
			expect((Weather.Types[id].waveChance or 0) > 0).toBe(dangerous)
		end
		local sizes = {}
		for n = 1, 4 do sizes[n] = math.max(3, math.floor(DefenseCfg.BaseMobCount * DefenseCfg.PartyMobScale[n] + 0.5)) end
		expect(sizes[1] < sizes[2] and sizes[2] < sizes[3] and sizes[3] < sizes[4]).toBeTruthy()
		expect(DefenseCfg.PrepSeconds > 0).toBeTruthy()
		local host = PS:GetHost(player)
		-- calm weather never starts a wave, even on a natural change
		WS:Set("clear", true)
		WS:Set("rain", true)
		expect(DF:StartWave(host, 0)).toBe(true) -- so none was running
		DF:Step(1, os.clock())
		for _, m in ipairs(waveMobs(host)) do MS:HitMonster(m, KILL) end
		DF:Step(1, os.clock())
		-- a natural change to dangerous weather starts one (the chance is forced to 1 for this check)
		local chance = Weather.Types.blood_moon.waveChance
		Weather.Types.blood_moon.waveChance = 1
		local okSet = pcall(WS.Set, WS, "blood_moon", true)
		Weather.Types.blood_moon.waveChance = chance
		expect(okSet).toBe(true)
		local started, why = DF:StartWave(host, 0)
		expect(started).toBe(false)
		expect(why).toBe("already_active")
		expect(#waveMobs(host)).toBe(0) -- the preparation time is still running
		DF:Step(DefenseCfg.PrepSeconds + 1, os.clock())
		local mobs = waveMobs(host)
		expect(#mobs).toBe(sizes[1] + 1) -- the solo wave plus the Blood Moon elite
		local reapers = 0
		for _, m in ipairs(mobs) do
			if m.id == "moon_reaper" then reapers += 1 end
			MS:HitMonster(m, KILL)
		end
		expect(reapers).toBe(1)
		local cleared = f.profile.stats.wavesCleared or 0
		DF:Step(1, os.clock())
		expect(f.profile.stats.wavesCleared or 0).toBe(cleared + 1)
	end) end)

	it("M6 help call: refused without a wave, an unknown alert counts as expired, an arriving helper lands at the defender's gate", function() fixture(function(f)
		local host = PS:GetHost(player)
		local called, whyCall = DF:CallForHelp(player)
		expect(called).toBe(false)
		expect(whyCall).toBe("no_wave")
		local answered, whyAnswer = DF:RespondHelp(player, "no-such-alert")
		expect(answered).toBe(false)
		expect(whyAnswer).toBe("expired")
		expect(DefenseCfg.HelpCall.FreeCallsPerSession > 0 and DefenseCfg.HelpCall.AlertDurationSeconds > 0).toBeTruthy()
		expect(DF.ShouldEscalateHelp(0)).toBe(true) -- nobody on this server can help: the call goes to the other servers
		expect(DF.ShouldEscalateHelp(1)).toBe(false)
		expect(DF:TeleportHelperToHost(player, host)).toBe(true)
		local gate = DF:PlotOfHost(host):GetPivot() * CFrame.new(0, 3.2, -6)
		expect((f.root.Position - gate.Position).Magnitude < 2).toBeTruthy()
	end) end)
end
