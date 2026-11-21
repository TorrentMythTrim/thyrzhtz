-- Blockout of the lobby (milestone 9): a round glade with a big mushroom in the middle, where players stand while
-- they gather a party. Simple blocks, like the map of the game place; final models come in milestone 10.
-- Rebuild in Studio (edit mode):  require(game.ServerStorage.Modules.LobbyBuilder).Build()
-- The server calls Ensure() on start, which builds the lobby only when it is missing.
local B = {}
local Mat = Enum.Material

B.GladeRadius = 70
B.PlazaRadius = 30
B.Spawns = 8

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local function part(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
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

-- An upright cylinder: cf is its middle
local function cylinder(parent, name, height, diameter, cf, color, material, extra)
	local e = extra and table.clone(extra) or {}
	e.Shape = Enum.PartType.Cylinder
	return part(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, e)
end

local function ball(parent, name, size, cf, color, material, extra)
	local p = part(parent, name, size, cf, color, material, extra)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A point on a circle around the middle of the lobby: angle in degrees, radius in studs
local function around(deg, radius, y)
	local a = math.rad(deg)
	return Vector3.new(math.sin(a) * radius, y, -math.cos(a) * radius)
end

function B.Build()
	for _, name in ipairs({"Lobby", "Baseplate", "SpawnLocation"}) do
		local old = workspace:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"

	cylinder(lobby, "Glade", 4, B.GladeRadius * 2, CFrame.new(0, -2, 0), rgb(86, 132, 74), Mat.Grass)
	cylinder(lobby, "Plaza", 0.4, B.PlazaRadius * 2, CFrame.new(0, 0.2, 0), rgb(150, 144, 130), Mat.Cobblestone)

	-- a hedge around the glade, so that nobody walks off it
	local segments = 28
	local width = 2 * math.pi * B.GladeRadius / segments + 1.5
	for i = 1, segments do
		local pos = around(i * 360 / segments, B.GladeRadius - 2, 6)
		part(lobby, "Hedge", Vector3.new(width, 12, 4), CFrame.lookAt(pos, Vector3.new(0, 6, 0)), rgb(52, 92, 50), Mat.Grass)
	end

	-- the big mushroom in the middle
	cylinder(lobby, "MushroomStem", 26, 9, CFrame.new(0, 13.4, 0), rgb(232, 222, 198), Mat.SmoothPlastic)
	ball(lobby, "MushroomCap", Vector3.new(46, 18, 46), CFrame.new(0, 29, 0), rgb(190, 52, 44), Mat.SmoothPlastic)
	for i = 1, 7 do
		local pos = around(i * 360 / 7 + 12, 13 + (i % 2) * 4, 36.3 - (i % 2) * 1.3)
		ball(lobby, "MushroomSpot", Vector3.new(5, 1.6, 5), CFrame.new(pos), rgb(244, 240, 228), Mat.SmoothPlastic, {CanCollide = false})
	end

	-- lanterns around the plaza
	for i = 1, 6 do
		local base = around(i * 60 + 30, B.PlazaRadius + 3, 0)
		cylinder(lobby, "LanternPost", 9, 0.8, CFrame.new(base + Vector3.new(0, 4.5, 0)), rgb(72, 56, 44), Mat.Wood)
		local lamp = ball(lobby, "Lantern", Vector3.new(2.2, 2.6, 2.2), CFrame.new(base + Vector3.new(0, 10, 0)), rgb(255, 214, 120), Mat.Neon, {CanCollide = false})
		local light = Instance.new("PointLight")
		light.Range = 28
		light.Brightness = 1.2
		light.Color = lamp.Color
		light.Parent = lamp
	end

	-- small mushrooms between the plaza and the hedge
	local rng = Random.new(9)
	for i = 1, 14 do
		local h = rng:NextNumber(2.5, 6)
		local base = around(i * 360 / 14 + rng:NextNumber(-8, 8), rng:NextNumber(B.PlazaRadius + 10, B.GladeRadius - 10), 0)
		cylinder(lobby, "ShroomStem", h, h * 0.3, CFrame.new(base + Vector3.new(0, h / 2, 0)), rgb(232, 222, 198))
		ball(lobby, "ShroomCap", Vector3.new(h * 1.2, h * 0.5, h * 1.2), CFrame.new(base + Vector3.new(0, h, 0)),
			i % 3 == 0 and rgb(120, 170, 220) or (i % 3 == 1 and rgb(190, 52, 44) or rgb(226, 170, 70)))
	end

	-- players appear on the plaza around the mushroom, looking at it
	for i = 1, B.Spawns do
		local pos = around(i * 360 / B.Spawns, 18, 0.9)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn_" .. i
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.CanCollide = false
		spawn.Transparency = 1
		spawn.Size = Vector3.new(5, 1, 5)
		spawn.CFrame = CFrame.lookAt(pos, Vector3.new(0, 0.9, 0))
		spawn.Parent = lobby
	end

	lobby.Parent = workspace
	return lobby
end

function B.Ensure()
	return workspace:FindFirstChild("Lobby") or B.Build()
end

return B
