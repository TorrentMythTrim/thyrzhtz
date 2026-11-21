-- Blockout models of Act 1 (milestone 8): the elder, captive residents, repaired houses, the boss arena,
-- the Rotten Stump-Lord and its growths. Like MapBuilder and CombatModels these are stand-ins made of blocks;
-- final models come in milestone 10.
-- Rebuild in Studio (edit mode):  require(game.ServerStorage.Modules.Act1Models).Build()
-- The server calls Ensure() on start, which only adds what is missing (for example after MapBuilder.Map()).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage.Shared
local Act1 = require(Shared.Config.Act1)
local MapCfg = require(Shared.Config.Map)
local Layout = require(Shared.Modules.Layout)
local MapBuilder = require(ServerStorage.Modules.MapBuilder)

local A = {}
local Mat = Enum.Material
local C = MapBuilder.C

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

-- Anchored block that nothing collides with: the same defaults as the monster parts of CombatModels
local function part(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Mat.SmoothPlastic
	for k, v in pairs(extra or {}) do p[k] = v end
	p.Parent = parent
	return p
end

local function ball(parent, name, size, cf, color, material, extra)
	local p = part(parent, name, size, cf, color, material, extra)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function cylinder(parent, name, h, d, cf, color, material, extra)
	local e = extra and table.clone(extra) or {}
	e.Shape = Enum.PartType.Cylinder
	return part(parent, name, Vector3.new(h, d, d), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, e)
end

local function model(name)
	local m = Instance.new("Model")
	m.Name = name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return m
end

local function prompt(parent, name, action, object, distance, hold)
	local pr = Instance.new("ProximityPrompt")
	pr.Name = name
	pr.ActionText = action
	pr.ObjectText = object
	pr.HoldDuration = hold or 0
	pr.MaxActivationDistance = distance or 12
	pr.RequiresLineOfSight = false
	pr.Parent = parent
	return pr
end

-- CFrame at an angle from north and a distance from the village centre, looking at the centre (as in MapBuilder)
local function facingCenter(deg, r, y)
	local d = Layout.Direction(deg)
	return CFrame.lookAt(Vector3.new(d.X * r, y, d.Z * r), Vector3.new(0, y, 0))
end

-- A standing villager. cf: feet on the ground, the face looks at −Z. o: robe (colour), beard (the elder)
function A.Villager(name, cf, o)
	o = o or {}
	local m = model(name)
	local robe = o.robe or rgb(120, 104, 84)
	local function at(x, y, z) return cf * CFrame.new(x, y, z) end
	local root = part(m, "Root", Vector3.new(2.2, 5.4, 2.2), at(0, 2.7, 0), rgb(100, 100, 100), nil, {Transparency = 1})
	part(m, "Robe", Vector3.new(2, 2.9, 1.3), at(0, 1.45, 0), robe, Mat.Fabric)
	part(m, "Chest", Vector3.new(1.8, 1.2, 1.2), at(0, 3.4, 0), robe, Mat.Fabric)
	ball(m, "Head", Vector3.new(1.3, 1.3, 1.3), at(0, 4.6, 0), rgb(232, 196, 160))
	ball(m, "Cap", Vector3.new(2.3, 1, 2.3), at(0, 5.3, 0), C.cloth)
	for _, sx in ipairs({-1, 1}) do
		part(m, "Arm", Vector3.new(0.5, 2.1, 0.5), at(sx * 1.15, 3, 0), robe, Mat.Fabric)
		ball(m, "Eye", Vector3.new(0.16, 0.16, 0.1), at(sx * 0.28, 4.7, -0.62), rgb(30, 30, 30))
	end
	if o.beard then
		part(m, "Beard", Vector3.new(0.9, 1.1, 0.3), at(0, 4, -0.6), rgb(236, 236, 228))
		part(m, "Staff", Vector3.new(0.25, 5.6, 0.25), at(1.6, 2.8, -0.4), C.woodDark, Mat.Wood)
	end
	m.PrimaryPart = root
	return m
end

-- The elder in the middle of the village (design doc 7.1). ElderPrompt opens his quests
function A.Elder(village)
	local old = village:FindFirstChild("Elder")
	if old then old:Destroy() end
	local cf = facingCenter(Act1.Elder.Angle, Act1.Elder.Distance, MapBuilder.Heights.plaza)
	local m = A.Villager("Elder", cf, {beard = true, robe = rgb(96, 84, 120)})
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 0.6, 0)
	att.Parent = m.PrimaryPart
	prompt(att, "ElderPrompt", "Talk", "Elder", 12)
	m.Parent = village
	return m
end

-- Prompts on the two portals MapBuilder put in the village. Whether a portal works is decided on the server
function A.PortalPrompts(village)
	for name, promptName in pairs({PortalRaid = "RaidPrompt", PortalNext = "NextPrompt"}) do
		local portal = village:FindFirstChild(name)
		local surface = portal and portal:FindFirstChild("Surface")
		if surface and not surface:FindFirstChild(promptName, true) then
			local att = Instance.new("Attachment")
			att.Name = "PromptPoint"
			att.Position = Vector3.new(0, -5, 0)
			att.Parent = surface
			prompt(att, promptName, "Enter", "Portal", 14)
		end
	end
end

-- A cage of roots with a villager inside, one per resident, in the Old Garden.
-- Every team frees its own residents: the client hides the cages its team has already opened
function A.Captives()
	local folder = workspace:FindFirstChild("Act1")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Act1"
		folder.Parent = workspace
	end
	local old = folder:FindFirstChild("Captives")
	if old then old:Destroy() end
	local captives = Instance.new("Folder")
	captives.Name = "Captives"
	local garden = MapCfg.OldGarden
	local y = MapBuilder.Heights.garden
	for _, resident in ipairs(Act1.Residents) do
		local pos = Vector3.new(garden.Center.X + resident.offset.X, y, garden.Center.Y + resident.offset.Y)
		local cf = CFrame.lookAt(pos, Vector3.new(garden.Center.X, y, garden.Center.Y))
		local m = A.Villager("Captive_" .. resident.id, cf)
		m:SetAttribute("Resident", resident.id)
		for i = 1, 8 do
			local a = math.rad(i * 45)
			part(m, "Bar", Vector3.new(0.35, 6.2, 0.35), cf * CFrame.new(math.cos(a) * 2.4, 3.1, math.sin(a) * 2.4), C.mold, Mat.Wood, {CanCollide = true})
		end
		cylinder(m, "CageTop", 0.4, 5.6, cf * CFrame.new(0, 6.3, 0), C.mold, Mat.Wood)
		local att = Instance.new("Attachment")
		att.Parent = m.PrimaryPart
		prompt(att, "RescuePrompt", "Free", "Villager", 12, 1.5)
		m.Parent = captives
	end
	captives.Parent = folder
	return captives
end

-- What a client shows once its team has repaired a ruin: the same house, whole, standing in the same place.
-- Resident is the figure of a freed villager at the stall. Teams on one server are at different steps, so the
-- repaired village is drawn on the client and the server keeps only the ruins
function A.Assets()
	local old = ReplicatedStorage:FindFirstChild("Act1Assets")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "Act1Assets"
	local y0 = MapBuilder.Heights.village
	for i, h in ipairs(Act1.Restoration.Houses) do
		local house = MapBuilder.House(folder, "Ruin_" .. i, facingCenter(h[1], h[2], y0), h[3], h[4], {wallH = 8, rng = Random.new(i)})
		house.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	A.Villager("Resident", CFrame.new()).Parent = folder
	folder.Parent = ReplicatedStorage
	return folder
end

-- Rotten Stump-Lord: a huge infected stump with mushrooms on its back (design doc 7.4).
-- Pivot on the ground, the face looks at −Z. HeartCover hides Heart until the three growths are destroyed
function A.RotStump()
	local m = model("Boss_RotStump")
	local bark, rot = rgb(78, 60, 44), rgb(92, 122, 70)
	local root = part(m, "Root", Vector3.new(12, 14, 12), CFrame.new(0, 7, 0), rgb(100, 100, 100), nil, {Transparency = 1, CanQuery = true})
	cylinder(m, "Trunk", 12, 13, CFrame.new(0, 6, 0), bark, Mat.Wood)
	cylinder(m, "Rim", 1.2, 14.5, CFrame.new(0, 12.4, 0), rgb(96, 76, 56), Mat.Wood)
	for i = 1, 7 do
		local a = math.rad(i * 360 / 7 + 20)
		local pos = Vector3.new(math.cos(a) * 8.5, 0.9, math.sin(a) * 8.5)
		part(m, "RootArm", Vector3.new(2.2, 1.8, 9), CFrame.lookAt(pos, Vector3.new(0, 0.9, 0)), bark, Mat.Wood)
	end
	for _, s in ipairs({{-3, 13.6, 3.5, 4.2}, {2.5, 14.2, 4.5, 5}, {0, 13.4, 0.5, 3.4}, {4.5, 13.2, 1, 2.8}}) do
		cylinder(m, "ShroomStem", 1.6, 0.9, CFrame.new(s[1], s[2] - 0.6, s[3]), rgb(214, 204, 178))
		ball(m, "ShroomCap", Vector3.new(s[4], s[4] * 0.45, s[4]), CFrame.new(s[1], s[2] + 0.4, s[3]), rot, Mat.Slate)
	end
	for _, sx in ipairs({-1, 1}) do
		ball(m, "Eye", Vector3.new(1.1, 0.8, 0.5), CFrame.new(sx * 2.6, 9.6, -6.3), rgb(195, 255, 90), Mat.Neon)
	end
	ball(m, "Heart", Vector3.new(4, 4.6, 3), CFrame.new(0, 5, -5.2), rgb(255, 70, 90), Mat.Neon, {Transparency = 1})
	local cover = Instance.new("Model")
	cover.Name = "HeartCover"
	cover.Parent = m
	for _, sx in ipairs({-1.6, 1.6}) do
		part(cover, "Bark", Vector3.new(3.2, 6.4, 1.2), CFrame.new(sx, 5, -6.4), rgb(64, 50, 38), Mat.Wood)
	end
	m.PrimaryPart = root
	m.WorldPivot = CFrame.new()
	return m
end

-- Infected growth: three of them stand around the stump
function A.RotGrowth()
	local m = model("Boss_RotGrowth")
	local root = part(m, "Root", Vector3.new(4, 4.5, 4), CFrame.new(0, 2.25, 0), rgb(100, 100, 100), nil, {Transparency = 1, CanQuery = true})
	ball(m, "Lump", Vector3.new(4.4, 3.8, 4.4), CFrame.new(0, 1.9, 0), rgb(92, 122, 70), Mat.Slate)
	for i = 1, 5 do
		local a = math.rad(i * 72)
		ball(m, "Pustule", Vector3.new(1.2, 1.2, 1.2), CFrame.new(math.cos(a) * 1.5, 2.9 + (i % 2) * 0.5, math.sin(a) * 1.5), rgb(196, 255, 110), Mat.Neon)
	end
	m.PrimaryPart = root
	m.WorldPivot = CFrame.new()
	return m
end

function A.MonsterTemplates()
	local folder = ServerStorage.Templates.Monsters
	for name, build in pairs({Boss_RotStump = A.RotStump, Boss_RotGrowth = A.RotGrowth}) do
		local old = folder:FindFirstChild(name)
		if old then old:Destroy() end
		build().Parent = folder
	end
end

-- Rooms of a boss portal along +Z: one per stage, then the boss room. Returns the rooms and the full depth
function A.ArenaLayout()
	local P = Act1.Portal
	local rooms, z = {}, 0
	for i = 1, #P.Stages do
		table.insert(rooms, {index = i, z0 = z, z1 = z + P.StageDepth})
		z += P.StageDepth
	end
	table.insert(rooms, {index = #P.Stages + 1, boss = true, z0 = z, z1 = z + P.BossDepth})
	return rooms, z + P.BossDepth
end

-- One team's boss portal. origin: the floor at the middle of the entrance wall, the boss is in the +Z direction.
-- Barrier_i closes the way out of stage i until it is cleared; Exit carries LeavePrompt
function A.Arena(origin, name)
	local P = Act1.Portal
	local rooms, depth = A.ArenaLayout()
	local m = Instance.new("Model")
	m.Name = name
	local W, wallH = P.Width, P.WallHeight
	local solid = {CanCollide = true, CanQuery = true}
	local stone, dark = rgb(70, 78, 72), rgb(44, 50, 48)
	local function at(x, y, z) return origin * CFrame.new(x, y, z) end
	local floor = part(m, "Floor", Vector3.new(W, 2, depth), at(0, -1, depth / 2), stone, Mat.Slate, solid)
	for _, sx in ipairs({-1, 1}) do
		part(m, "Wall", Vector3.new(2, wallH, depth + 4), at(sx * (W / 2 + 1), wallH / 2 - 2, depth / 2), dark, Mat.Slate, solid)
	end
	part(m, "WallEntrance", Vector3.new(W, wallH, 2), at(0, wallH / 2 - 2, -1), dark, Mat.Slate, solid)
	part(m, "WallEnd", Vector3.new(W, wallH, 2), at(0, wallH / 2 - 2, depth + 1), dark, Mat.Slate, solid)
	for _, room in ipairs(rooms) do
		local mid = (room.z0 + room.z1) / 2
		if not room.boss then
			part(m, "Barrier_" .. room.index, Vector3.new(W, wallH, 1.5), at(0, wallH / 2 - 2, room.z1), C.woodDark, Mat.Wood, solid)
			part(m, "Chest_" .. room.index, Vector3.new(3, 2, 2), at(W / 2 - 6, 1, mid), C.gold, Mat.Wood, solid)
			part(m, "LoreStone_" .. room.index, Vector3.new(2, 4, 0.6), at(-W / 2 + 6, 2, mid), rgb(150, 170, 200), Mat.Slate, solid)
		end
		local lamp = part(m, "Lamp_" .. room.index, Vector3.new(1, 1, 1), at(0, wallH - 8, mid), rgb(190, 150, 255), Mat.Neon)
		local light = Instance.new("PointLight")
		light.Range = 60
		light.Brightness = 1.4
		light.Color = lamp.Color
		light.Parent = lamp
	end
	local exit = part(m, "Exit", Vector3.new(8, 10, 0.6), at(0, 5, 0.6), rgb(150, 90, 230), Mat.Neon, {Transparency = 0.4})
	local att = Instance.new("Attachment")
	att.Parent = exit
	prompt(att, "LeavePrompt", "Leave", "Portal", 12)
	m.PrimaryPart = floor
	return m
end

function A.Build()
	local village = workspace.Map.Village
	A.Elder(village)
	A.PortalPrompts(village)
	A.Captives()
	A.Assets()
	A.MonsterTemplates()
	return true
end

-- Adds only what is missing. Safe on every server start
function A.Ensure()
	local map = workspace:FindFirstChild("Map")
	local village = map and map:FindFirstChild("Village")
	if village then
		if not village:FindFirstChild("Elder") then A.Elder(village) end
		A.PortalPrompts(village)
	end
	local folder = workspace:FindFirstChild("Act1")
	if not (folder and folder:FindFirstChild("Captives")) then A.Captives() end
	if not ReplicatedStorage:FindFirstChild("Act1Assets") then A.Assets() end
	local monsters = ServerStorage.Templates:FindFirstChild("Monsters")
	if monsters and not (monsters:FindFirstChild("Boss_RotStump") and monsters:FindFirstChild("Boss_RotGrowth")) then
		A.MonsterTemplates()
	end
end

return A
