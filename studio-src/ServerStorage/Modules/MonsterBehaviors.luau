-- Behaviour of the roster monsters that are not part of the Act 1 spawn list (design doc 4.6–4.7, milestone 5):
-- Mist Double, Crystal Tick, Ash Hound, Void Cloak, Swarm Mother with her nests, Mold Gardener.
-- MonsterService owns the mob table and the main loop and calls the hooks below; all numbers live in Config.Monsters.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Modules.Net)
local CombatCfg = require(Shared.Config.Combat)
local MapCfg = require(Shared.Config.Map)

local Behaviors = {}
local MS, CS, DS, Defense
local rng = Random.new()

local latched = {} -- [Player] = Crystal Tick riding that player
local zones = {}   -- [mob] = blight disc of a Mold Gardener
local trails = {}  -- fire patches left by Ash Hounds
local burning = {} -- [bed part] = {untilT, nextTick, damage, fire}

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function hazardFolder()
	local f = workspace:FindFirstChild("MonsterHazards")
	if not f then
		f = Instance.new("Folder")
		f.Name = "MonsterHazards"
		f.Parent = workspace
	end
	return f
end

local function alivePlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if r and h and h.Health > 0 then table.insert(list, {player = p, root = r, hum = h}) end
	end
	return list
end

local function nearestPlayer(pos, range, seeStealthed)
	local best, bestD = nil, range
	for _, e in ipairs(alivePlayers()) do
		if seeStealthed or not CS:IsStealthed(e.player) then
			local d = flat(e.root.Position - pos).Magnitude
			if d <= bestD then best, bestD = e, d end
		end
	end
	return best, bestD
end

local function entryOf(player)
	local c = player and player.Parent and player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if r and h and h.Health > 0 then return {player = player, root = r, hum = h} end
	return nil
end

local function isGone(mob)
	return mob.hp <= 0 or not (mob.model and mob.model.Parent)
end

local function speedOf(mob, now)
	return mob.def.speed * (now < mob.slowUntil and (1 - mob.slowFactor) or 1)
end

local function moveToward(mob, pos, target, speed, dt, stopAt)
	local delta = flat(target - pos)
	local dist = delta.Magnitude
	if dist <= stopAt or dist < 1e-3 then return end
	local dir = delta.Unit
	local step = dir * math.min(dist - stopAt, speed * dt)
	local np = Vector3.new(pos.X + step.X, mob.spawnPos.Y, pos.Z + step.Z)
	mob.model:PivotTo(CFrame.lookAt(np, np + dir))
end

-- weather and totem multipliers apply to these monsters like to every other one
local function scaled(damage, pos)
	if Defense then damage *= Defense:CombatMultipliersAt(pos).monster end
	return damage
end

-- ===== Mist Double: copies the look and one slotted ability of the nearest player; light hurts it more =====
local function copyPlayer(mob, e)
	local x = mob.x
	x.copiedFrom = e.player
	local prof = DS:GetProfile(e.player)
	local pool = {}
	for _, species in ipairs(prof and prof.combat and prof.combat.abilitySlots or {}) do
		if CombatCfg.MushroomAbilities[species] then table.insert(pool, species) end
	end
	x.ability = #pool > 0 and pool[rng:NextInteger(1, #pool)] or nil
	mob.model:SetAttribute("CopiedPlayer", e.player.UserId)
	mob.model:SetAttribute("CopiedAbility", x.ability)

	local old = mob.model:FindFirstChild("Disguise")
	if old then old:Destroy() end
	local char = e.player.Character
	local wasArchivable = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(char.Clone, char)
	char.Archivable = wasArchivable
	if not (ok and clone) then return end
	clone.Name = "Disguise"
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ForceField") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery = true, false, false, false
			if d.Transparency < 0.35 then d.Transparency = 0.35 end
		elseif d:IsA("Decal") then
			if d.Transparency < 0.35 then d.Transparency = 0.35 end
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local lift = e.hum.HipHeight + e.root.Size.Y / 2
	clone:PivotTo(mob.model:GetPivot() * CFrame.new(0, lift, 0))
	clone.Parent = mob.model
	-- the fog silhouette gives way to the copy; the wisps at its feet stay as the tell
	local body = mob.model:FindFirstChild("MistBody")
	if body then
		for _, d in ipairs(body:GetDescendants()) do
			if d:IsA("BasePart") then d.Transparency = 1 end
		end
	end
end

local function castCopied(mob, e, pos)
	local def = mob.def
	local a = CombatCfg.MushroomAbilities[mob.x.ability]
	if a and a.heal and not a.damage then
		mob.hp = math.min(mob.maxHp, mob.hp + (def.abilityHeal or 15))
		Net.FireAll("CombatFx", "aoe_burst", "light", pos, 4)
		MS:SyncAttributes(mob)
		return
	end
	local radius = def.abilityRadius or 7
	local center = e.root.Position
	Net.FireAll("CombatFx", "aoe_burst", a and a.element or "dark", center, radius)
	for _, o in ipairs(alivePlayers()) do
		if flat(o.root.Position - center).Magnitude <= radius then
			CS:DamagePlayer(o.player, scaled(def.abilityDamage or 12, pos), mob)
		end
	end
end

local function stepMistDouble(mob, dt, now)
	local x, def = mob.x, mob.def
	local pos = mob.model:GetPivot().Position
	local e, dist = nearestPlayer(pos, def.copyRange or 40, false)
	if not e then return false end
	if x.copiedFrom ~= e.player then copyPlayer(mob, e) end
	if x.ability and now >= x.nextAbility and dist <= (def.abilityRange or 16) then
		x.nextAbility = now + (def.abilityCooldown or 6)
		x.casts += 1
		castCopied(mob, e, pos)
	end
	return false -- chasing and melee stay with the common AI
end

-- ===== Crystal Tick: jumps on a player and slows them until it is shaken off by mashing a key =====
local function releaseTick(mob, now, thrown)
	local x = mob.x
	local player = x.host
	if not player then return end
	x.host = nil
	x.presses = {}
	x.nextLatch = now + (mob.def.relatchCooldown or 5)
	if latched[player] == mob then latched[player] = nil end
	if player.Parent then
		player:SetAttribute("TickLatched", nil)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = player:GetAttribute("Blocking") and MapCfg.WalkSpeed * 0.6 or MapCfg.WalkSpeed
		end
		if thrown then Net.Fire(player, "Notify", "tick_shaken_off") end
	end
	if isGone(mob) then return end
	mob.model:SetAttribute("LatchedOn", nil)
	local pos = mob.model:GetPivot().Position
	local away = thrown and (mob.def.throwDistance or 7) or 0
	local a = rng:NextNumber(0, math.pi * 2)
	mob.model:PivotTo(CFrame.new(pos.X + math.cos(a) * away, mob.spawnPos.Y, pos.Z + math.sin(a) * away))
	if thrown then
		mob.stunUntil = math.max(mob.stunUntil, now + (mob.def.throwStun or 1.5))
		MS:SyncAttributes(mob, now)
	end
end

local function stepTick(mob, dt, now)
	local x, def = mob.x, mob.def
	if x.host then
		local e = entryOf(x.host)
		if not e then
			releaseTick(mob, now, false)
			return true
		end
		mob.model:PivotTo(e.root.CFrame * CFrame.new(0, 0.6, 0.9))
		e.hum.WalkSpeed = MapCfg.WalkSpeed * (1 - (def.latchSlow or 0.45)) * (e.player:GetAttribute("Blocking") and 0.6 or 1)
		if now >= x.nextBite then
			x.nextBite = now + (def.latchTick or 1)
			CS:DamagePlayer(e.player, scaled(def.damage or 3, e.root.Position), mob)
		end
		return true
	end
	if now < x.nextLatch then return false end
	local pos = mob.model:GetPivot().Position
	local e = nearestPlayer(pos, def.latchRange or 7, false)
	if not e or latched[e.player] then return false end
	x.host = e.player
	x.presses = {}
	x.nextBite = now + (def.latchTick or 1)
	latched[e.player] = mob
	e.player:SetAttribute("TickLatched", def.shakePresses or 6)
	mob.model:SetAttribute("LatchedOn", e.player.UserId)
	Net.Fire(e.player, "Notify", "tick_latched")
	return true
end

-- One press of the shake key. Only presses inside the window count, so the key has to be mashed.
function Behaviors.ShakeOff(player)
	local mob = latched[player]
	if not mob then return false end
	local x, def, now = mob.x, mob.def, os.clock()
	local kept = {}
	for _, t in ipairs(x.presses) do
		if now - t <= (def.shakeWindow or 2.5) then table.insert(kept, t) end
	end
	table.insert(kept, now)
	x.presses = kept
	local need = def.shakePresses or 6
	player:SetAttribute("TickLatched", math.max(0, need - #kept))
	if #kept >= need then
		releaseTick(mob, now, true)
		return true
	end
	return false
end

-- ===== Ash Hound: leaves a burning trail while it runs and sets garden beds on fire =====
local function igniteBed(bed, def, now)
	local b = burning[bed]
	if not b then
		local fire = Instance.new("Fire")
		fire.Name = "MonsterFire"
		fire.Heat = 6
		fire.Size = 4
		fire.Parent = bed
		b = {nextTick = now, fire = fire}
		burning[bed] = b
	end
	b.untilT = now + (def.bedBurnSeconds or 3)
	b.damage = def.bedBurnDamage or 6
end

local function dropFire(mob, pos, now)
	local def = mob.def
	local radius = def.trailRadius or 3
	local p = Instance.new("Part")
	p.Name = "FireTrail"
	p.Shape = Enum.PartType.Cylinder
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 120, 40)
	p.Transparency = 0.35
	p.Size = Vector3.new(0.2, radius * 2, radius * 2)
	p.CFrame = CFrame.new(pos.X, mob.spawnPos.Y + 0.15, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	local fire = Instance.new("Fire")
	fire.Heat = 4
	fire.Size = radius
	fire.Parent = p
	p.Parent = hazardFolder()
	table.insert(trails, {
		part = p, pos = Vector3.new(pos.X, mob.spawnPos.Y, pos.Z), untilT = now + (def.trailSeconds or 4),
		nextTick = now + 0.3, radius = radius, damage = def.trailDamage or 3,
	})
	mob.x.patches += 1
end

local function stepHound(mob, dt, now)
	local x, def = mob.x, mob.def
	local pos = mob.model:GetPivot().Position
	if flat(pos - x.trailPos).Magnitude >= (def.trailSpacing or 4) then
		x.trailPos = pos
		dropFire(mob, pos, now)
	end
	if def.burnsBeds and now >= x.nextBedCheck then
		x.nextBedCheck = now + 0.5
		for _, bed in ipairs(MS:NearbyBuiltBeds(pos, def.bedBurnRadius or 5)) do
			igniteBed(bed, def, now)
		end
	end
	return false -- chasing and biting stay with the common AI
end

-- ===== Void Cloak: half-transparent, teleports behind its target, shows itself for a second before striking =====
local function setCloaked(mob, cloaked)
	local x = mob.x
	if x.cloaked == cloaked then return end
	x.cloaked = cloaked
	local k = cloaked and (mob.def.cloakTransparency or 0.75) or 0
	for d, base in pairs(x.base) do
		if d.Parent then d.Transparency = 1 - (1 - base) * (1 - k) end
	end
	mob.model:SetAttribute("Cloaked", cloaked)
end

local function stepCloak(mob, dt, now)
	local x, def = mob.x, mob.def
	local pos = mob.model:GetPivot().Position
	local range = def.attackRange or 5
	if x.phase == "reveal" then
		if now >= x.strikeAt then
			x.phase = "stalk"
			setCloaked(mob, true)
			mob.nextAttack = now + (def.attackCooldown or 2.4)
			local e = entryOf(x.target)
			if e and flat(e.root.Position - pos).Magnitude <= range + 2 then
				CS:DamagePlayer(e.player, scaled(def.damage or 14, pos), mob)
			end
		end
		return true
	end
	local e, dist = nearestPlayer(pos, 55, false)
	if not e or (pos - mob.spawnPos).Magnitude > mob.leash then return false end
	-- every strike starts with a blink behind the target's back, unless the cloak already stands there
	local back = flat(-e.root.CFrame.LookVector)
	back = back.Magnitude > 1e-3 and back.Unit or Vector3.new(0, 0, 1)
	local behind = dist > 1e-3 and flat(pos - e.root.Position).Unit:Dot(back) > 0.5
	if now >= mob.bindUntil and now >= x.nextTeleport and now >= mob.nextAttack
		and dist <= (def.teleportRange or 30) and (dist > range or not behind) then
		x.nextTeleport = now + (def.teleportCooldown or 5)
		local dest = e.root.Position + back * (range * 0.7)
		Net.FireAll("CombatFx", "aoe_burst", "dark", pos, 3)
		mob.model:PivotTo(CFrame.lookAt(
			Vector3.new(dest.X, mob.spawnPos.Y, dest.Z),
			Vector3.new(e.root.Position.X, mob.spawnPos.Y, e.root.Position.Z)))
		x.teleports += 1
		pos = mob.model:GetPivot().Position
		dist = flat(e.root.Position - pos).Magnitude
	end
	if dist <= range then
		if now >= mob.nextAttack then
			x.phase = "reveal"
			x.target = e.player
			x.strikeAt = now + (def.revealSeconds or 1)
			setCloaked(mob, false)
		end
	elseif now >= mob.bindUntil then
		moveToward(mob, pos, e.root.Position, speedOf(mob, now), dt, range * 0.7)
	end
	return true
end

-- ===== Swarm Mother: builds up to maxNests nests, one per nestBuildSeconds; a hit interrupts her and she turns on the attacker =====
local function stepMother(mob, dt, now)
	local x, def = mob.x, mob.def
	local pos = mob.model:GetPivot().Position
	for i = #x.nests, 1, -1 do
		if isGone(x.nests[i]) then table.remove(x.nests, i) end
	end
	mob.model:SetAttribute("Nests", #x.nests)

	if now < x.aggroUntil then
		local e = entryOf(x.offender)
		if not e then return false end
		local range = def.attackRange or 6.5
		local dist = flat(e.root.Position - pos).Magnitude
		if dist > range then
			if now >= mob.bindUntil then moveToward(mob, pos, e.root.Position, speedOf(mob, now), dt, range * 0.7) end
		elseif now >= mob.nextAttack then
			mob.nextAttack = now + (def.attackCooldown or 1.6)
			CS:DamagePlayer(e.player, scaled(def.damage or 15, pos), mob)
		end
		return true
	end

	-- she only builds while there is somebody to fight; with every nest standing the common AI takes over
	if not nearestPlayer(pos, 60, true) then
		x.buildDoneAt = nil
		mob.model:SetAttribute("Building", false)
		return false
	end
	if #x.nests >= (def.maxNests or 10) then return false end
	if not x.buildDoneAt then
		x.buildDoneAt = now + (def.nestBuildSeconds or 5)
		mob.model:SetAttribute("Building", true)
	elseif now >= x.buildDoneAt then
		x.buildDoneAt = nil
		mob.model:SetAttribute("Building", false)
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(5, def.nestRadius or 14)
		local nest = MS:Spawn("swarm_nest", Vector3.new(pos.X + math.cos(a) * d, mob.spawnPos.Y, pos.Z + math.sin(a) * d),
			{zone = mob.zone, leash = mob.leash})
		if nest then
			nest.x.mother = mob
			table.insert(x.nests, nest)
			mob.model:SetAttribute("Nests", #x.nests)
			Net.FireAll("CombatFx", "aoe_burst", "poison", nest.model:GetPivot().Position, 3)
		end
	end
	return true -- stands still while building
end

-- A nest never moves. It keeps a small brood of Spore Mosquitoes in the air while a player is around.
local function stepNest(mob, dt, now)
	local x, def = mob.x, mob.def
	if x.mother and isGone(x.mother) then
		MS:Remove(mob)
		return true
	end
	for i = #x.brood, 1, -1 do
		if isGone(x.brood[i]) then table.remove(x.brood, i) end
	end
	if now >= x.nextSpawn and #x.brood < (def.maxBrood or 1) then
		local pos = mob.model:GetPivot().Position
		if nearestPlayer(pos, 60, true) then
			x.nextSpawn = now + (def.spawnInterval or 7)
			local m = MS:Spawn("spore_mosquito",
				Vector3.new(pos.X + rng:NextNumber(-2, 2), mob.spawnPos.Y, pos.Z + rng:NextNumber(-2, 2)),
				{zone = mob.zone, leash = 80})
			if m then table.insert(x.brood, m) end
		end
	end
	return true
end

-- ===== Mold Gardener: infects plants; while he fights, a blight field spreads and hurts more the longer a player stays in it =====
local function clearZone(mob)
	local zone = zones[mob]
	if zone then zone:Destroy() end
	zones[mob] = nil
	local x = mob.x
	if x and x.stacks then
		for player in pairs(x.stacks) do
			if player.Parent then player:SetAttribute("BlightStacks", nil) end
		end
		x.stacks = {}
	end
end

local function stepGardener(mob, dt, now)
	local x, def = mob.x, mob.def
	local pos = mob.model:GetPivot().Position
	local fighting = next(mob.engagedPlayers) ~= nil or nearestPlayer(pos, 55, true) ~= nil

	if now >= x.nextInfect then
		x.nextInfect = now + (def.infectInterval or 3)
		local seen = {}
		for _, bed in ipairs(MS:NearbyBuiltBeds(pos, def.infectRadius or 12)) do seen[bed] = true end
		if x.center then
			for _, bed in ipairs(MS:NearbyBuiltBeds(x.center, x.radius)) do seen[bed] = true end
		end
		for bed in pairs(seen) do MS:AffectBed(bed, 0, def.bedInfection or 14) end
	end

	if not x.center then
		if not fighting then return false end
		x.center = Vector3.new(pos.X, mob.spawnPos.Y, pos.Z)
		x.radius = def.blightStartRadius or 6
		local zone = Instance.new("Part")
		zone.Name = "BlightZone"
		zone.Shape = Enum.PartType.Cylinder
		zone.Anchored, zone.CanCollide, zone.CanTouch, zone.CanQuery = true, false, false, false
		zone.Material = Enum.Material.Slate
		zone.Color = Color3.fromRGB(104, 128, 92)
		zone.Transparency = 0.4
		zone.Size = Vector3.new(0.2, x.radius * 2, x.radius * 2)
		zone.CFrame = CFrame.new(x.center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
		zone.Parent = hazardFolder()
		zones[mob] = zone
	elseif fighting and x.radius < (def.blightMaxRadius or 30) then
		x.radius = math.min(def.blightMaxRadius or 30, x.radius + (def.blightGrowth or 0.8) * dt)
		local zone = zones[mob]
		if zone and math.abs(zone.Size.Y - x.radius * 2) >= 0.5 then
			zone.Size = Vector3.new(0.2, x.radius * 2, x.radius * 2)
		end
	end
	mob.model:SetAttribute("BlightRadius", math.floor(x.radius * 10 + 0.5) / 10)

	if now >= x.nextTick then
		x.nextTick = now + (def.blightTick or 1)
		for _, e in ipairs(alivePlayers()) do
			if flat(e.root.Position - x.center).Magnitude <= x.radius then
				local stacks = math.min(def.blightMaxStacks or 12, (x.stacks[e.player] or 0) + 1)
				if stacks == 1 then Net.Fire(e.player, "Notify", "gardener_blight") end
				x.stacks[e.player] = stacks
				e.player:SetAttribute("BlightStacks", stacks)
				CS:DamagePlayer(e.player, (def.blightBaseDamage or 2) + (def.blightStackDamage or 1) * (stacks - 1), nil)
			elseif x.stacks[e.player] then
				x.stacks[e.player] = nil
				e.player:SetAttribute("BlightStacks", nil)
			end
		end
	end
	return false -- chasing and melee stay with the common AI
end

local steps = {
	mist_double = stepMistDouble,
	crystal_tick = stepTick,
	ash_hound = stepHound,
	void_cloak = stepCloak,
	swarm_mother = stepMother,
	swarm_nest = stepNest,
	mold_gardener = stepGardener,
}

-- Milestone 8: another module can attach its own hooks to a monster id instead of growing this file
-- (BossService does it for the Act 1 boss). hooks: OnSpawn(mob), Step(mob, dt, now) -> true to replace the
-- common AI, HitMultiplier(mob, hit) -> number
local extensions = {}
function Behaviors.Extend(id, hooks)
	extensions[id] = hooks
end

-- ===== Hooks called by MonsterService =====
function Behaviors.Init(services)
	MS, CS, DS, Defense = services.MonsterService, services.CombatService, services.DataService, services.DefenseService
end

function Behaviors.OnSpawn(mob)
	local now = os.clock()
	local id = mob.id
	if id == "mist_double" then
		mob.x = {nextAbility = now + 2, casts = 0}
	elseif id == "crystal_tick" then
		mob.x = {nextLatch = 0, nextBite = 0, presses = {}}
	elseif id == "ash_hound" then
		mob.x = {trailPos = mob.spawnPos, nextBedCheck = 0, patches = 0}
	elseif id == "void_cloak" then
		local base = {}
		for _, d in ipairs(mob.model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Root" then base[d] = d.Transparency end
		end
		mob.x = {phase = "stalk", nextTeleport = now + 1, base = base, teleports = 0}
		setCloaked(mob, true)
	elseif id == "swarm_mother" then
		mob.x = {nests = {}, aggroUntil = 0}
	elseif id == "swarm_nest" then
		mob.x = {brood = {}, nextSpawn = now + 2}
	elseif id == "mold_gardener" then
		mob.x = {stacks = {}, nextTick = 0, nextInfect = now + 1}
	else
		mob.x = {}
	end
	local ext = extensions[id]
	if ext and ext.OnSpawn then ext.OnSpawn(mob) end
end

-- Returns true when the behaviour has done the whole step and the common AI must not run.
function Behaviors.Step(mob, dt, now)
	local ext = extensions[mob.id]
	if ext and ext.Step then return ext.Step(mob, dt, now) == true end
	local fn = steps[mob.id]
	if not fn then return false end
	return fn(mob, dt, now) == true
end

function Behaviors.HitMultiplier(mob, hit)
	local ext = extensions[mob.id]
	if ext and ext.HitMultiplier then return ext.HitMultiplier(mob, hit) end
	if mob.def.lightWeakness and hit.element == "light" then return mob.def.lightWeakness end
	return 1
end

function Behaviors.OnHit(mob, hit, now)
	if mob.id == "swarm_mother" then
		local x = mob.x
		x.buildDoneAt = nil
		x.offender = hit.attacker or x.offender
		x.aggroUntil = now + (mob.def.interruptSeconds or 4)
		mob.model:SetAttribute("Building", false)
	end
end

-- The mob is leaving the game (killed or cleared): drop everything it holds outside its own model.
function Behaviors.OnRemoved(mob)
	local x = mob.x
	if not x then return end
	if mob.id == "crystal_tick" then
		releaseTick(mob, os.clock(), false)
	elseif mob.id == "mold_gardener" then
		clearZone(mob)
	elseif mob.id == "swarm_mother" then
		for _, nest in ipairs(x.nests) do
			if not isGone(nest) then MS:Remove(nest) end
		end
		x.nests = {}
	end
end

-- Runs every tick of the monster loop: hazards that outlive a step and clean-up after mobs that vanished.
function Behaviors.Sweep(now)
	for player, mob in pairs(latched) do
		if not player.Parent or isGone(mob) or now < mob.stunUntil or now < mob.sleepUntil or now < mob.staggerUntil then
			releaseTick(mob, now, false)
			latched[player] = nil
		end
	end
	for mob in pairs(zones) do
		if isGone(mob) then clearZone(mob) end
	end
	for i = #trails, 1, -1 do
		local t = trails[i]
		if now >= t.untilT then
			t.part:Destroy()
			table.remove(trails, i)
		elseif now >= t.nextTick then
			t.nextTick = now + 0.5
			for _, e in ipairs(alivePlayers()) do
				if flat(e.root.Position - t.pos).Magnitude <= t.radius and math.abs(e.root.Position.Y - t.pos.Y) < 7 then
					CS:DamagePlayer(e.player, t.damage, nil)
				end
			end
		end
	end
	for bed, b in pairs(burning) do
		if now >= b.untilT or not bed.Parent then
			b.fire:Destroy()
			burning[bed] = nil
		elseif now >= b.nextTick then
			b.nextTick = now + 1
			MS:AffectBed(bed, b.damage, 0)
		end
	end
end

return Behaviors
