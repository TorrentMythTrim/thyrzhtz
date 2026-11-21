-- House decoration (milestone 9, design doc 6.7: the team builds and decorates its house together).
-- A cosmetic item from the bag is put at one of the fixed spots in front of the team's house; any member can put
-- one up or take one down, and everyone on the server sees it. What stands where is in the team record
-- (house.decorations), so it is there again next time. The spots and the look are a draft (Config.Coop.Decor);
-- the models are simple blocks until milestone 10.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Locale = require(Shared.Modules.Locale)
local Items = require(Shared.Config.Items)
local Coop = require(Shared.Config.Coop)

local DecorService = {Priority = 30}
local DataService, PartyService, InventoryService, PlayerService
local plotOf = {} -- [hostUserId] = the plot whose decorations are shown for this team
local REACH = 16  -- studs from a spot within which the server accepts its prompt

local function isReal(player)
	return typeof(player) == "Instance"
end

local function tell(player, key, ...)
	if isReal(player) and player.Parent then Net.Fire(player, "Notify", key, ...) end
end

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

-- Builders of the decoration models, by the names in Coop.Decor.Models. Pivot on the ground
local Builders = {}

-- Mushroom Lantern Banner: a pole with a cloth and a glowing lantern
function Builders.LanternBanner()
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(96, 72, 50)
	part(m, "Pole", Vector3.new(0.4, 7, 0.4), CFrame.new(0, 3.5, 0), wood, Enum.Material.Wood)
	part(m, "Arm", Vector3.new(2.4, 0.3, 0.3), CFrame.new(0.2, 6.7, 0), wood, Enum.Material.Wood)
	part(m, "Cloth", Vector3.new(1.5, 3.2, 0.15), CFrame.new(0.75, 4.95, 0), Color3.fromRGB(176, 58, 52), Enum.Material.Fabric)
	local lamp = part(m, "Lantern", Vector3.new(0.9, 1.1, 0.9), CFrame.new(-0.7, 5.9, 0), Color3.fromRGB(255, 214, 120), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Range = 14
	light.Brightness = 1
	light.Color = lamp.Color
	light.Parent = lamp
	m.WorldPivot = CFrame.new()
	return m
end

function DecorService:Init()
	DataService = Loader.Get("DataService")
	PartyService = Loader.Get("PartyService")
	InventoryService = Loader.Get("InventoryService")
	PlayerService = Loader.Get("PlayerService")
end

-- The plot of a team
function DecorService:PlotOf(hostUserId)
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	for _, plot in ipairs(plots and plots:GetChildren() or {}) do
		if plot:GetAttribute("OwnerHost") == hostUserId then return plot end
	end
	return nil
end

-- Where the spots of a plot are: on the ground in front of the house, counted from its foundation
function DecorService.SpotCFrames(plot)
	local house = plot:FindFirstChild("House")
	local base = house and house:FindFirstChild("Foundation")
	local list = {}
	if not base then return list end
	for i, spot in ipairs(Coop.Decor.Spots) do
		local x = spot.side * (base.Size.X / 2 - spot.inset)
		list[i] = base.CFrame * CFrame.new(x, -base.Size.Y / 2, -(base.Size.Z / 2 + 1.2))
	end
	return list
end

-- The folder of a plot with one invisible spot and its prompt for every place a decoration can stand
function DecorService:Prepare(plot)
	local folder = plot:FindFirstChild("Decor")
	if folder then return folder end
	folder = Instance.new("Folder")
	folder.Name = "Decor"
	for i, cf in ipairs(DecorService.SpotCFrames(plot)) do
		local spot = part(folder, "Spot_" .. i, Vector3.new(1, 1, 1), cf * CFrame.new(0, 2.5, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		spot.Transparency = 1
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DecorPrompt"
		prompt.ActionText = "Decorate"
		prompt.ObjectText = "House decoration"
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = spot
		prompt.Triggered:Connect(function(player) self:Use(player, plot, i) end)
	end
	folder.Parent = plot
	return folder
end

-- Show on the team's plot what its record says
function DecorService:Render(hostUserId)
	local plot = self:PlotOf(hostUserId)
	local team = DataService:GetTeam(hostUserId)
	if not (plot and team) then return false end
	plotOf[hostUserId] = plot
	local folder = self:Prepare(plot)
	local saved = team.house and team.house.decorations or {}
	for i, cf in ipairs(DecorService.SpotCFrames(plot)) do
		local entry = saved[tostring(i)]
		local itemId = type(entry) == "table" and entry.item or nil
		local shown = folder:FindFirstChild("Item_" .. i)
		if shown and shown:GetAttribute("Item") ~= itemId then
			shown:Destroy()
			shown = nil
		end
		local build = itemId and Builders[Coop.Decor.Models[itemId] or ""]
		if build and not shown then
			local m = build()
			m.Name = "Item_" .. i
			m:SetAttribute("Item", itemId)
			m:PivotTo(cf)
			m.Parent = folder
		end
		local spot = folder:FindFirstChild("Spot_" .. i)
		if spot then spot:SetAttribute("Item", itemId) end
	end
	return true
end

-- The team has left the server: the next team gets the house without its decorations
function DecorService:Clear(hostUserId)
	local plot = plotOf[hostUserId]
	plotOf[hostUserId] = nil
	local folder = plot and plot.Parent and plot:FindFirstChild("Decor")
	for _, child in ipairs(folder and folder:GetChildren() or {}) do
		if child:IsA("Model") then
			child:Destroy()
		else
			child:SetAttribute("Item", nil)
		end
	end
end

-- The decoration the player would put up: the one in hand, otherwise the first one in the bag
function DecorService:Carried(player)
	local profile = DataService:GetProfile(player)
	if not profile then return nil end
	local function usable(id)
		local def = id and Items.Defs[id]
		return def ~= nil and def.kind == "cosmetic" and Coop.Decor.Models[id] ~= nil and (profile.inventory.items[id] or 0) > 0
	end
	local held = profile.inventory.hotbar[tostring(player:GetAttribute("HotbarSlot") or 0)]
	if usable(held) then return held end
	local ids = {}
	for id in pairs(profile.inventory.items) do
		if usable(id) then table.insert(ids, id) end
	end
	table.sort(ids)
	return ids[1]
end

-- A member of the team puts a decoration up at a free spot or takes down the one that stands there.
-- ignoreDistance is for tests
function DecorService:Use(player, plot, index, ignoreDistance)
	local host = PartyService:GetHost(player)
	local team = host and DataService:GetTeam(host)
	if not team or plot:GetAttribute("OwnerHost") ~= host then
		tell(player, "decor_not_yours")
		return false, "not_yours"
	end
	local cf = DecorService.SpotCFrames(plot)[index]
	if not cf then return false, "unknown" end
	if not ignoreDistance then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - cf.Position).Magnitude > REACH then return false, "too_far" end
	end
	local profile = DataService:GetProfile(player)
	local lang = profile and profile.settings and profile.settings.language or Locale.Default
	team.house = team.house or {level = 1, decorations = {}}
	team.house.decorations = team.house.decorations or {}
	local saved, key = team.house.decorations, tostring(index)
	if saved[key] then
		local itemId = saved[key].item
		if not InventoryService:Give(player, itemId, 1) then
			tell(player, "farm_bag_full")
			return false, "bag_full"
		end
		saved[key] = nil
		tell(player, "decor_taken", Locale.Name(lang, Items.Defs[itemId].name))
	else
		local itemId = self:Carried(player)
		if not itemId or not InventoryService:Take(player, itemId, 1) then
			tell(player, "decor_need_item")
			return false, "no_item"
		end
		saved[key] = {item = itemId, by = player.UserId, at = os.time()}
		tell(player, "decor_placed", Locale.Name(lang, Items.Defs[itemId].name))
	end
	self:Render(host)
	if isReal(player) then PlayerService:Push(player) end
	PlayerService:PushTeam(host)
	return true
end

function DecorService:Start()
	-- HouseService gives a team its house and sets the Plot attribute of every member: show the decorations then
	local function hook(player)
		local function show()
			local host = PartyService:GetHost(player)
			if host and player:GetAttribute("Plot") then self:Render(host) end
		end
		player:GetAttributeChangedSignal("Plot"):Connect(show)
		show()
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do hook(player) end
	PartyService.TeamEmptied.Event:Connect(function(host) self:Clear(host) end)
end

return DecorService
