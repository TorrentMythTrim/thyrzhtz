-- Act 1 on the client (milestone 8): the elder's window and the task line, the village as this team has restored
-- it, freed residents at the stall, the portals and the raid line.
-- Teams on one server are at different steps, so repairs are drawn here; the server keeps only the ruins.
-- Temporary interface, like the rest of the HUD, until the layouts of milestone 10.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Locale = require(Shared.Modules.Locale)
local Act1 = require(Shared.Config.Act1)
local Items = require(Shared.Config.Items)
local Monsters = require(Shared.Config.Monsters)

local Act1Controller = {Priority = 40}
local player = Players.LocalPlayer
local State, Ui
local repaired = {} -- [ruin name] = the whole house shown instead of it
local traders = {} -- [resident id] = the figure at the stall

local PORTALS = {
	PortalRaid = {flag = "bossPortal", label = "label_portal_raid", prompt = "RaidPrompt"},
	PortalNext = {flag = "nextPortal", label = "label_portal_next", prompt = "NextPrompt"},
}

local function residentName(lang, id)
	for _, resident in ipairs(Act1.Residents) do
		if resident.id == id then return Locale.Name(lang, resident.name) end
	end
	return "?"
end

local function objectiveText(lang, team, quest, index, state)
	local objective = quest.objectives[index]
	local have, need = Act1.ObjectiveProgress(team, quest, index, state)
	if objective.type == "deliver" then
		local def = Items.Defs[objective.item]
		return Locale.T(lang, "quest_obj_deliver", def and Locale.Name(lang, def.name) or objective.item, have, need)
	elseif objective.type == "kill" then
		local def = Monsters.Regular[objective.monster] or Monsters.Elite[objective.monster]
		return Locale.T(lang, "quest_obj_kill", def and Locale.Name(lang, def.name) or objective.monster, have, need)
	end
	return Locale.T(lang, "quest_obj_rescue", residentName(lang, objective.resident), have, need)
end

function Act1Controller:Init()
	State = Loader.Get("StateController")
	Ui = Loader.Get("UiController")
end

function Act1Controller:Build()
	local make = Ui.Make
	local tracker = Ui.Panel({Name = "Act1Tracker", Visible = false, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 190), Size = UDim2.fromOffset(280, 0), AutomaticSize = Enum.AutomaticSize.Y}, Ui.Gui)
	self.Tracker = tracker
	self.TrackerLabel = Ui.Label("", tracker)

	local window = Ui.Panel({Name = "Act1Elder", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(460, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.05}, Ui.Gui)
	self.Window = window
	Ui.List(window, 8)
	self.Title = Ui.Label("", window, {Font = Enum.Font.GothamBold, TextSize = 18, LayoutOrder = 1})
	self.Body = Ui.Label("", window, {LayoutOrder = 2})
	local row = make("Frame", {Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 3}, window)
	Ui.List(row, 8, true)
	self.ActionButton = Ui.Button("", row, {Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Ui.GREEN, LayoutOrder = 1})
	self.CloseButton = Ui.Button("", row, {Size = UDim2.new(0.5, -4, 1, 0), LayoutOrder = 2})
	self.Lore = Ui.Label("", window, {LayoutOrder = 4, TextColor3 = Color3.fromRGB(214, 206, 180)})
	self.ActionButton.Activated:Connect(function()
		if self.action then Net.Event("Act1Action"):FireServer(self.action) end
	end)
	self.CloseButton.Activated:Connect(function() window.Visible = false end)

	local folder = Instance.new("Folder")
	folder.Name = "Act1Local"
	folder.Parent = workspace
	self.Folder = folder
end

-- The line about the boss portal while the player is inside
function Act1Controller:RaidLine()
	local state = player:GetAttribute("RaidState")
	if state == "stage" then
		return State:T("raid_hud_stage", player:GetAttribute("RaidStage") or 1, player:GetAttribute("RaidStages") or 1)
	elseif state == "boss" then
		return State:T("raid_hud_boss", player:GetAttribute("RaidGrowths") or Act1.Boss.Growths)
	elseif state == "heart" then
		return State:T("raid_hud_heart")
	elseif state == "won" then
		return State:T("raid_hud_won")
	end
	return nil
end

function Act1Controller:Render()
	local team = State.team
	if not team then
		self.Tracker.Visible = false
		return
	end
	local lang = State:Language()
	local quest = Act1.CurrentQuest(team)
	local state = quest and team.quests and team.quests.active and team.quests.active[quest.id] or nil
	local objectives = {}
	if quest then
		for i in ipairs(quest.objectives) do
			-- before the quest is taken the amounts are shown for the team as it is now
			table.insert(objectives, "• " .. objectiveText(lang, team, quest, i, state or {size = State.partySize}))
		end
	end

	local lines = {}
	local raid = self:RaidLine()
	if raid then table.insert(lines, "<b>" .. raid .. "</b>") end
	if quest and state then
		table.insert(lines, "<b>" .. State:T("quest_tracker") .. ": " .. State:T("quest_" .. quest.id .. "_title") .. "</b>")
		for _, text in ipairs(objectives) do table.insert(lines, text) end
	elseif quest then
		table.insert(lines, State:T("quest_offer"))
	end
	self.TrackerLabel.Text = table.concat(lines, "\n")
	self.Tracker.Visible = #lines > 0

	if not self.Window.Visible then return end
	local R = Act1.Restoration
	local body = {State:T("quest_restoration", team.village and tonumber(team.village.restoration) or 0, R.Max)}
	if team.acts and team.acts.ancestorPage then table.insert(body, State:T("ancestor_page_owned")) end
	table.insert(body, "")
	if quest then
		table.insert(body, "<b>" .. State:T("quest_" .. quest.id .. "_title") .. "</b>")
		table.insert(body, State:T("quest_" .. quest.id .. "_text"))
		for _, text in ipairs(objectives) do table.insert(body, text) end
		self.action = state and "turn_in" or "accept"
		self.ActionButton.Text = State:T(state and "quest_hand_in" or "quest_accept")
	else
		table.insert(body, State:T("quest_finished"))
		self.action = nil
	end
	self.ActionButton.Visible = quest ~= nil
	self.Title.Text = State:T("quest_window_title")
	self.Body.Text = table.concat(body, "\n")
	self.CloseButton.Text = State:T("close")
	local lore = {}
	for key in pairs(team.acts and team.acts.lore or {}) do table.insert(lore, key) end
	table.sort(lore)
	for i, key in ipairs(lore) do lore[i] = "<i>" .. State:T(key) .. "</i>" end
	if #lore > 0 then table.insert(lore, 1, "<b>" .. State:T("lore_title") .. "</b>") end
	self.Lore.Text = table.concat(lore, "\n")
	self.Lore.Visible = #lore > 0
end

local function setHidden(model, hidden, collideWhenShown)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = hidden and 1 or 0
			if collideWhenShown ~= nil then d.CanCollide = collideWhenShown and not hidden end
		end
	end
end

-- Bring the village, the cages and the portals to the state of this player's team
function Act1Controller:World()
	local team = State.team
	local map = workspace:FindFirstChild("Map")
	local village = map and map:FindFirstChild("Village")
	local assets = ReplicatedStorage:FindFirstChild("Act1Assets")
	if not (team and village and assets) then return end
	local lang = State:Language()
	local level = team.village and tonumber(team.village.restoration) or 0
	local rescued = team.village and team.village.rescued or {}

	for step, name in ipairs(Act1.Restoration.Repairs) do
		local done = level >= step
		local old = village:FindFirstChild(name)
		if name == "ElderHouse" then
			-- the elder's house stood through it all: repairing it only takes the mould and the cracks away
			for _, d in ipairs(old and old:GetChildren() or {}) do
				if d:IsA("BasePart") and (d.Name:match("^Mold") or d.Name:match("^Crack")) then
					d.LocalTransparencyModifier = done and 1 or 0
				end
			end
		else
			if old then setHidden(old, done, true) end
			if done and not repaired[name] then
				local template = assets:FindFirstChild(name)
				if template then
					repaired[name] = template:Clone()
					repaired[name].Parent = self.Folder
				end
			elseif not done and repaired[name] then
				repaired[name]:Destroy()
				repaired[name] = nil
			end
		end
	end

	-- freed residents stand behind the counter of the stall
	local stall = village:FindFirstChild("MerchantStall")
	for i, resident in ipairs(Act1.Residents) do
		local figure = traders[resident.id]
		if rescued[resident.id] and stall and not figure then
			figure = assets.Resident:Clone()
			figure:PivotTo(stall:GetPivot() * CFrame.new((i - (#Act1.Residents + 1) / 2) * 3, 1.2, 2.6))
			local tag = Instance.new("BillboardGui")
			tag.Size = UDim2.fromOffset(160, 26)
			tag.StudsOffset = Vector3.new(0, 3.6, 0)
			tag.MaxDistance = 60
			local text = Instance.new("TextLabel")
			text.Name = "Text"
			text.BackgroundTransparency = 1
			text.Size = UDim2.fromScale(1, 1)
			text.Font = Enum.Font.GothamBold
			text.TextScaled = true
			text.TextColor3 = Color3.fromRGB(255, 244, 214)
			text.TextStrokeTransparency = 0.35
			text.Parent = tag
			tag.Parent = figure.PrimaryPart
			figure.Parent = self.Folder
			traders[resident.id] = figure
		elseif not rescued[resident.id] and figure then
			figure:Destroy()
			traders[resident.id] = nil
			figure = nil
		end
		local text = figure and figure:FindFirstChild("Text", true)
		if text then text.Text = State:T("resident_trader") end
	end

	-- a cage this team has opened is gone for this team
	local act = workspace:FindFirstChild("Act1")
	local captives = act and act:FindFirstChild("Captives")
	for _, cage in ipairs(captives and captives:GetChildren() or {}) do
		local id = cage:GetAttribute("Resident")
		local free = rescued[id] ~= nil
		for _, d in ipairs(cage:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = free and 1 or 0
				if d.Name == "Bar" then d.CanCollide = not free end
			elseif d:IsA("ProximityPrompt") then
				d.Enabled = not free
				d.ActionText = State:T("prompt_rescue_action")
				d.ObjectText = residentName(lang, id)
			end
		end
	end

	local labels = village:FindFirstChild("Labels")
	for name, info in pairs(PORTALS) do
		local portal = village:FindFirstChild(name)
		local open = team.acts ~= nil and team.acts[info.flag] == true
		local key = open and (info.label .. "_open") or info.label
		for _, d in ipairs(portal and portal:GetDescendants() or {}) do
			if d.Name == "Surface" then
				d.LocalTransparencyModifier = open and 0 or 0.6
			elseif d.Name == "Plank" then
				d.LocalTransparencyModifier = open and 1 or 0
				d.CanCollide = not open
			elseif d:IsA("ProximityPrompt") then
				d.ActionText = State:T("prompt_portal_enter")
				d.ObjectText = State:T(key)
			end
		end
		local anchor = labels and labels:FindFirstChild("Label_" .. info.label)
		local gui = anchor and anchor:FindFirstChildWhichIsA("BillboardGui")
		local text = gui and gui:FindFirstChildWhichIsA("TextLabel")
		if text then
			gui:SetAttribute("LocaleKey", key)
			text.Text = State:T(key)
		end
	end

	local elder = village:FindFirstChild("Elder")
	local talk = elder and elder:FindFirstChild("ElderPrompt", true)
	if talk then
		talk.ActionText = State:T("prompt_elder_action")
		talk.ObjectText = State:T("label_elder")
	end
	local portals = act and act:FindFirstChild("Portals")
	for _, d in ipairs(portals and portals:GetDescendants() or {}) do
		if d:IsA("ProximityPrompt") and d.Name == "LeavePrompt" then
			d.ActionText = State:T("prompt_portal_leave")
			d.ObjectText = State:T("prompt_portal")
		end
	end
end

function Act1Controller:Start()
	self:Build()
	Net.Event("Act1Event").OnClientEvent:Connect(function(kind, key)
		if kind == "elder" then
			self.Window.Visible = true
			self:Render()
		elseif kind == "lore" then
			Ui:Toast("<b>" .. State:T("lore_found") .. "</b>\n" .. State:T(tostring(key)))
		end
	end)
	local function refresh()
		self:Render()
		self:World()
	end
	State.Changed:Connect(refresh)
	for _, name in ipairs({"RaidState", "RaidStage", "RaidGrowths"}) do
		player:GetAttributeChangedSignal(name):Connect(function() self:Render() end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Escape then self.Window.Visible = false end
	end)
	refresh()
	-- with streaming, parts of the village and the cages arrive later
	while true do
		task.wait(2)
		self:World()
	end
end

return Act1Controller
