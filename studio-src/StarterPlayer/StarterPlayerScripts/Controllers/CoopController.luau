-- Milestone 9 on the client: the "Don't sleep!" window (design doc 2.5), the way back to the lobby and the texts
-- of the house decoration prompts. Temporary interface, like the rest of the HUD, until the layouts of milestone 10.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Coop = require(Shared.Config.Coop)

local CoopController = {Priority = 30}
local player = Players.LocalPlayer
local State, Ui
local moved = false  -- there was input since the last report to the server
local deadline = nil -- when the "Don't sleep!" window runs out; nil while it is closed

function CoopController:Init()
	State = Loader.Get("StateController")
	Ui = Loader.Get("UiController")
end

function CoopController:Build()
	-- the window is above everything else on the screen
	local gui = Ui.Make("ScreenGui", {Name = "GS_Afk", ResetOnSpawn = false, DisplayOrder = 50, Enabled = false},
		player:WaitForChild("PlayerGui"))
	self.AfkGui = gui
	Ui.Make("Frame", {Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45, BorderSizePixel = 0}, gui)
	local window = Ui.Panel({Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(380, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.02}, gui)
	Ui.List(window, 10)
	self.AfkTitle = Ui.Label("", window, {Font = Enum.Font.GothamBold, TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1})
	self.AfkText = Ui.Label("", window, {TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2})
	self.AfkButton = Ui.Button("", window, {Name = "Awake", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Ui.GREEN,
		Font = Enum.Font.GothamBold, TextSize = 18, LayoutOrder = 3})
	self.AfkButton.Activated:Connect(function()
		Net.Event("AfkAction"):FireServer("awake")
		deadline = nil
		gui.Enabled = false
	end)

	-- the way back to the lobby is in the settings panel, above its "Close" button
	Ui.CloseButton.LayoutOrder = 10
	self.LobbyButton = Ui.Button("", Ui.SettingsPanel, {Name = "ReturnToLobby", LayoutOrder = 5})
	self.LobbyButton.Activated:Connect(function() Net.Event("LobbyAction"):FireServer("return") end)
end

function CoopController:Render()
	self.AfkTitle.Text = State:T("afk_title")
	self.AfkButton.Text = State:T("afk_button")
	self.LobbyButton.Text = State:T("lobby_return")
	if deadline then
		self.AfkText.Text = State:T("afk_text", math.max(0, math.ceil(deadline - os.clock())))
	end
end

-- The decoration spots of the player's own house: their prompts work and speak the player's language.
-- The server checks whose house it is in any case
function CoopController:Prompts()
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	local mine = player:GetAttribute("Plot")
	for _, plot in ipairs(plots and plots:GetChildren() or {}) do
		local decor = plot:FindFirstChild("Decor")
		for _, spot in ipairs(decor and decor:GetChildren() or {}) do
			local prompt = spot:FindFirstChild("DecorPrompt")
			if prompt then
				prompt.Enabled = plot.Name == mine
				prompt.ActionText = State:T(spot:GetAttribute("Item") and "decor_take" or "decor_place")
				prompt.ObjectText = State:T("decor_spot")
			end
		end
	end
end

function CoopController:Start()
	self:Build()
	Net.Event("AfkPrompt").OnClientEvent:Connect(function(seconds)
		deadline = os.clock() + (tonumber(seconds) or Coop.Afk.PromptSeconds)
		self.AfkGui.Enabled = true
		self:Render()
	end)
	UserInputService.InputBegan:Connect(function() moved = true end)
	UserInputService.InputChanged:Connect(function() moved = true end)
	State.Changed:Connect(function()
		self:Render()
		self:Prompts()
	end)
	self:Render()
	local lastReport, tick = 0, 0
	while true do
		task.wait(0.5)
		local now = os.clock()
		tick += 1
		if deadline then
			self.AfkText.Text = State:T("afk_text", math.max(0, math.ceil(deadline - now)))
		elseif moved and now - lastReport >= Coop.Afk.PingSeconds then
			moved, lastReport = false, now
			Net.Event("AfkAction"):FireServer("active")
		end
		if tick % 4 == 0 then self:Prompts() end -- with streaming, plots and their spots arrive later
	end
end

return CoopController
