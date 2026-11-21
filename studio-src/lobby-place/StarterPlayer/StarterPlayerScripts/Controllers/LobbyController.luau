-- The lobby on the client (milestone 9, design doc 2.1): the party window. It shows what the server sent and sends
-- the player's intentions back; it decides nothing itself. Temporary interface until the layouts of milestone 10.
-- The language is English by default and Russian by choice (decision 6); in the lobby the choice lasts for the visit.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Modules.Net)
local Locale = require(Shared.Modules.Locale)
local PartyCfg = require(Shared.Config.Party)

local Lobby = {Priority = 50}
local player = Players.LocalPlayer
local lang = Locale.Default
local state = nil -- the last LobbyState from the server

local DARK = Color3.fromRGB(24, 30, 27)
local GREEN = Color3.fromRGB(70, 150, 90)
local GREY = Color3.fromRGB(62, 66, 64)
local RED = Color3.fromRGB(150, 70, 62)

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function list(parent, padding, horizontal)
	return make("UIListLayout", {Padding = UDim.new(0, padding or 6), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical}, parent)
end

local function panel(props, parent)
	local f = make("Frame", props, parent)
	f.BackgroundColor3 = DARK
	f.BackgroundTransparency = 0.12
	make("UICorner", {CornerRadius = UDim.new(0, 10)}, f)
	make("UIPadding", {PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12)}, f)
	list(f, 8)
	return f
end

local function label(text, parent, props)
	local l = make("TextLabel", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamMedium, TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Text = text}, parent)
	if props then for k, v in pairs(props) do l[k] = v end end
	return l
end

local function button(text, parent, props)
	local b = make("TextButton", {Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = GREY,
		TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamMedium, TextSize = 15, Text = text}, parent)
	if props then for k, v in pairs(props) do b[k] = v end end
	make("UICorner", {CornerRadius = UDim.new(0, 8)}, b)
	return b
end

-- A row of a list: text on the left, buttons on the right
local function row(parent, order, text, dim)
	local f = make("Frame", {Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = order}, parent)
	label(text, f, {Name = "Text", Size = UDim2.new(1, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
		TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, TextTransparency = dim and 0.5 or 0})
	local buttons = make("Frame", {Name = "Buttons", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1}, f)
	list(buttons, 6, true)
	return f, buttons
end

local function clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

local function T(key, ...)
	return Locale.T(lang, key, ...)
end

local function act(action, a)
	Net.Event("LobbyAction"):FireServer(action, a)
end

local function formatOf(id)
	for _, f in ipairs(PartyCfg.Formats) do
		if f.id == id then return f end
	end
	return PartyCfg.Formats[1]
end

function Lobby:Build()
	local gui = make("ScreenGui", {Name = "GS_Lobby", ResetOnSpawn = false}, player:WaitForChild("PlayerGui"))
	self.Gui = gui

	local main = panel({Name = "Party", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(400, 0), AutomaticSize = Enum.AutomaticSize.Y}, gui)
	self.Title = label("", main, {Font = Enum.Font.GothamBold, TextSize = 24, LayoutOrder = 1})
	self.Subtitle = label("", main, {TextTransparency = 0.25, LayoutOrder = 2})
	self.FormatLabel = label("", main, {Font = Enum.Font.GothamBold, LayoutOrder = 3})
	local formats = make("Frame", {Name = "Formats", Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 4}, main)
	list(formats, 6, true)
	self.FormatButtons = {}
	for i, f in ipairs(PartyCfg.Formats) do
		local b = button("", formats, {Name = f.id, Size = UDim2.new(1 / #PartyCfg.Formats, -5, 1, 0), LayoutOrder = i})
		b.Activated:Connect(function() act("format", f.id) end)
		self.FormatButtons[f.id] = b
	end
	self.PartyLabel = label("", main, {Font = Enum.Font.GothamBold, LayoutOrder = 5})
	self.Members = make("Frame", {Name = "Members", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 6}, main)
	list(self.Members, 4)
	self.StartButton = button("", main, {Name = "Start", BackgroundColor3 = GREEN, Size = UDim2.new(1, 0, 0, 40),
		Font = Enum.Font.GothamBold, TextSize = 17, LayoutOrder = 7})
	self.StartButton.Activated:Connect(function() act("start") end)
	self.Hint = label("", main, {Name = "Hint", TextTransparency = 0.2, LayoutOrder = 8})
	self.LeaveButton = button("", main, {Name = "Leave", LayoutOrder = 9})
	self.LeaveButton.Activated:Connect(function() act("leave") end)
	self.RejoinLabel = label("", main, {Name = "RejoinText", LayoutOrder = 10})
	self.RejoinButton = button("", main, {Name = "Rejoin", BackgroundColor3 = GREEN, LayoutOrder = 11})
	self.RejoinButton.Activated:Connect(function() act("rejoin") end)

	local side = panel({Name = "Lobby", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(340, 0), AutomaticSize = Enum.AutomaticSize.Y}, gui)
	self.InvitesLabel = label("", side, {Font = Enum.Font.GothamBold, LayoutOrder = 1})
	self.Invites = make("Frame", {Name = "Invites", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 2}, side)
	list(self.Invites, 4)
	self.PlayersLabel = label("", side, {Font = Enum.Font.GothamBold, LayoutOrder = 3})
	self.PlayerList = make("ScrollingFrame", {Name = "Players", Size = UDim2.new(1, 0, 0, 180), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4}, side)
	list(self.PlayerList, 4)
	self.LanguageLabel = label("", side, {Font = Enum.Font.GothamBold, LayoutOrder = 5})
	local langs = make("Frame", {Name = "Languages", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 6}, side)
	list(langs, 6, true)
	self.LangButtons = {}
	for i, code in ipairs(Locale.Languages) do
		local b = button(code == "ru" and "Русский" or "English", langs, {Name = code, Size = UDim2.new(0.5, -3, 1, 0), LayoutOrder = i})
		b.Activated:Connect(function()
			lang = code
			self:Render()
		end)
		self.LangButtons[code] = b
	end

	self.Toasts = make("Frame", {Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(460, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, gui)
	list(self.Toasts, 6)
end

function Lobby:Toast(text)
	local l = label(text, self.Toasts, {TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0.2,
		BackgroundColor3 = DARK, TextSize = 16})
	make("UICorner", {CornerRadius = UDim.new(0, 8)}, l)
	make("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, l)
	task.delay(5, function() l:Destroy() end)
end

function Lobby:Render()
	self.Title.Text = T("lobby_title")
	self.Subtitle.Text = T("lobby_subtitle")
	self.FormatLabel.Text = T("lobby_format")
	self.PlayersLabel.Text = T("lobby_players")
	self.InvitesLabel.Text = T("lobby_invites")
	self.LanguageLabel.Text = T("lobby_language")
	for code, b in pairs(self.LangButtons) do
		b.BackgroundColor3 = code == lang and GREEN or GREY
	end
	local s = state
	if not s then return end
	local party = s.party
	local me = player.UserId
	local leading = party.leader == me
	local f = formatOf(party.format)
	local free = not party.launching

	for id, b in pairs(self.FormatButtons) do
		b.Text = T("format_" .. id) .. " · " .. formatOf(id).size
		b.BackgroundColor3 = id == party.format and GREEN or GREY
		b.TextTransparency = (leading and free) and 0 or 0.45
	end

	self.PartyLabel.Text = T("lobby_party", #party.members, f.size)
	clear(self.Members)
	for i = 1, f.size do
		local m = party.members[i]
		if m then
			local tags = {}
			if m.id == party.leader then table.insert(tags, T("lobby_leader")) end
			if m.id == me then table.insert(tags, T("lobby_you")) end
			local _, buttons = row(self.Members, i, m.name .. (#tags > 0 and ("  (" .. table.concat(tags, ", ") .. ")") or ""))
			if leading and free and m.id ~= me then
				local b = button(T("lobby_kick"), buttons, {Name = "Kick", Size = UDim2.new(0, 92, 1, 0), BackgroundColor3 = RED})
				b.Activated:Connect(function() act("kick", m.id) end)
			end
		else
			row(self.Members, i, T("lobby_empty_seat"), true)
		end
	end

	local full = #party.members == f.size
	self.StartButton.Visible = leading and free
	self.StartButton.Text = T("lobby_start")
	self.StartButton.BackgroundColor3 = full and GREEN or GREY
	if party.launching then
		self.Hint.Text = T("lobby_launching")
	elseif not leading then
		self.Hint.Text = T("lobby_start_wait")
	elseif not full then
		self.Hint.Text = T("lobby_need_full", #party.members, f.size)
	else
		self.Hint.Text = ""
	end
	self.Hint.Visible = self.Hint.Text ~= ""
	self.LeaveButton.Visible = #party.members > 1 and free
	self.LeaveButton.Text = T("lobby_leave")

	local back = s.rejoin
	self.RejoinLabel.Visible = back ~= nil and free
	self.RejoinButton.Visible = back ~= nil and free and #party.members == 1
	if back then
		self.RejoinLabel.Text = T("lobby_rejoin", back.hostName, T("format_" .. tostring(back.format)))
		self.RejoinButton.Text = T("lobby_rejoin_button")
	end

	clear(self.Invites)
	self.InvitesLabel.Visible = #s.invites > 0
	self.Invites.Visible = #s.invites > 0
	for i, inv in ipairs(s.invites) do
		local _, buttons = row(self.Invites, i, T("lobby_invite_from", inv.name, T("format_" .. tostring(inv.format))))
		local yes = button(T("lobby_accept"), buttons, {Name = "Accept", Size = UDim2.new(0, 84, 1, 0), BackgroundColor3 = GREEN, LayoutOrder = 1})
		yes.Activated:Connect(function() act("accept", inv.id) end)
		local no = button(T("lobby_decline"), buttons, {Name = "Decline", Size = UDim2.new(0, 92, 1, 0), LayoutOrder = 2})
		no.Activated:Connect(function() act("decline", inv.id) end)
	end

	clear(self.PlayerList)
	if #s.players == 0 then row(self.PlayerList, 1, T("lobby_nobody"), true) end
	local canInvite = leading and free and #party.members < f.size
	for i, other in ipairs(s.players) do
		local _, buttons = row(self.PlayerList, i, other.name)
		if other.size > 1 then
			label(T("lobby_in_party"), buttons, {Size = UDim2.new(0, 96, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
				TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 0.5})
		elseif other.invited then
			label(T("lobby_invite_sent"), buttons, {Size = UDim2.new(0, 96, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
				TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 0.5})
		elseif canInvite then
			local b = button(T("lobby_invite"), buttons, {Name = "Invite", Size = UDim2.new(0, 104, 1, 0), BackgroundColor3 = GREEN})
			b.Activated:Connect(function() act("invite", other.id) end)
		end
	end
end

function Lobby:Start()
	self:Build()
	Net.Event("LobbyState").OnClientEvent:Connect(function(snapshot)
		state = snapshot
		self:Render()
	end)
	Net.Event("Notify").OnClientEvent:Connect(function(key, ...)
		self:Toast(T(key, ...))
	end)
	self:Render()
	act("refresh")
end

return Lobby
