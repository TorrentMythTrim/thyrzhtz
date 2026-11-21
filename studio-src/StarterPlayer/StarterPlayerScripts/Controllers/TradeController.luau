-- Item trade on the client (milestone 9, design doc 6.7): the trade button, the Guardians nearby, an incoming
-- offer and the trade window. It shows what the server sends and sends the player's choices back; the server
-- decides everything. Temporary interface until the layouts of milestone 10.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Locale = require(Shared.Modules.Locale)
local Items = require(Shared.Config.Items)
local Coop = require(Shared.Config.Coop)

local TradeController = {Priority = 30}
local State, Ui
local view = nil   -- the trade the server says the player is in
local nearby = {}  -- players close enough to offer a trade to
local asking = nil -- {id, name, untilT}: who has offered a trade

local function act(...)
	Net.Event("TradeAction"):FireServer(...)
end

local function itemText(lang, itemId, count)
	local def = Items.Defs[itemId]
	return (def and (def.icon .. " " .. Locale.Name(lang, def.name)) or itemId) .. " x" .. count
end

local function sortedIds(items)
	local ids = {}
	for id in pairs(items or {}) do table.insert(ids, id) end
	table.sort(ids)
	return ids
end

function TradeController:Init()
	State = Loader.Get("StateController")
	Ui = Loader.Get("UiController")
end

-- A line of a list: text on the left, small buttons on the right
function TradeController:Row(parent, order, text, dim)
	local make = Ui.Make
	local row = make("Frame", {Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = order}, parent)
	Ui.Label(text, row, {Name = "Text", Size = UDim2.new(1, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
		RichText = false, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextTransparency = dim and 0.5 or 0})
	local buttons = make("Frame", {Name = "Buttons", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1}, row)
	Ui.List(buttons, 4, true)
	return row, buttons
end

function TradeController:Build()
	local make = Ui.Make
	self.OpenButton = Ui.Button("🤝", Ui.Gui, {Name = "TradeButton", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -64, 0, 12), Size = UDim2.fromOffset(44, 44), TextSize = 22, BackgroundColor3 = Ui.DARK})
	self.OpenButton.Activated:Connect(function()
		if view then return end
		self.Window.Visible = not self.Window.Visible
		if self.Window.Visible then act("nearby") end
		self:Render()
	end)

	local window = Ui.Panel({Name = "Trade", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(460, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.05}, Ui.Gui)
	self.Window = window
	Ui.List(window, 6)
	self.Title = Ui.Label("", window, {Font = Enum.Font.GothamBold, TextSize = 18, RichText = false, LayoutOrder = 1})
	self.Body = make("Frame", {Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 2}, window)
	Ui.List(self.Body, 2)
	self.Bag = make("ScrollingFrame", {Name = "Bag", Size = UDim2.new(1, 0, 0, 150), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3}, window)
	Ui.List(self.Bag, 2)
	self.Status = Ui.Label("", window, {RichText = false, TextColor3 = Color3.fromRGB(214, 206, 180), LayoutOrder = 4})
	local buttons = make("Frame", {Name = "Buttons", Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 5}, window)
	Ui.List(buttons, 8, true)
	self.ConfirmButton = Ui.Button("", buttons, {Name = "Confirm", Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Ui.GREEN, LayoutOrder = 1})
	self.ConfirmButton.Activated:Connect(function() act(view and "confirm" or "nearby") end)
	self.CancelButton = Ui.Button("", buttons, {Name = "Cancel", Size = UDim2.new(0.5, -4, 1, 0), LayoutOrder = 2})
	self.CancelButton.Activated:Connect(function()
		if view then
			act("cancel")
		else
			window.Visible = false
		end
	end)

	local ask = Ui.Panel({Name = "TradeRequest", Visible = false, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(360, 0), AutomaticSize = Enum.AutomaticSize.Y}, Ui.Gui)
	self.Ask = ask
	Ui.List(ask, 6)
	self.AskLabel = Ui.Label("", ask, {RichText = false, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1})
	local answers = make("Frame", {Name = "Buttons", Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 2}, ask)
	Ui.List(answers, 8, true)
	self.AcceptButton = Ui.Button("", answers, {Name = "Accept", Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Ui.GREEN, LayoutOrder = 1})
	self.DeclineButton = Ui.Button("", answers, {Name = "Decline", Size = UDim2.new(0.5, -4, 1, 0), LayoutOrder = 2})
	local function answer(accept)
		if asking then act("answer", asking.id, accept) end
		asking = nil
		self:Render()
	end
	self.AcceptButton.Activated:Connect(function() answer(true) end)
	self.DeclineButton.Activated:Connect(function() answer(false) end)
end

local function clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

function TradeController:Render()
	local lang = State:Language()
	self.Ask.Visible = asking ~= nil and view == nil
	if asking then self.AskLabel.Text = State:T("trade_request", asking.name) end
	self.AcceptButton.Text = State:T("trade_accept")
	self.DeclineButton.Text = State:T("trade_decline")
	if not self.Window.Visible then return end
	clear(self.Body)
	clear(self.Bag)
	self.Bag.Visible = view ~= nil
	self.CancelButton.Text = State:T(view and "trade_cancel" or "close")
	if not view then
		-- nobody to trade with yet: the Guardians standing close
		self.Title.Text = State:T("trade_title")
		self.Status.Text = ""
		self.ConfirmButton.Text = State:T("trade_refresh")
		self.ConfirmButton.BackgroundColor3 = Ui.GREY
		Ui.Label(State:T("trade_pick"), self.Body, {Font = Enum.Font.GothamBold, LayoutOrder = 0})
		if #nearby == 0 then Ui.Label(State:T("trade_nobody"), self.Body, {TextTransparency = 0.4, LayoutOrder = 1}) end
		for i, other in ipairs(nearby) do
			local _, buttons = self:Row(self.Body, i, other.name, other.busy)
			if other.busy then
				Ui.Label(State:T("trade_busy_mark"), buttons, {Size = UDim2.new(0, 110, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
					TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 0.5})
			else
				local b = Ui.Button(State:T("trade_offer"), buttons, {Name = "Offer", Size = UDim2.new(0, 160, 1, 0), BackgroundColor3 = Ui.GREEN})
				b.Activated:Connect(function() act("request", other.id) end)
			end
		end
		return
	end

	self.Title.Text = State:T("trade_with", view.partner.name)
	local order = 0
	local function section(key, offer, mine)
		order += 1
		Ui.Label(State:T(key), self.Body, {Font = Enum.Font.GothamBold, LayoutOrder = order})
		local ids = sortedIds(offer)
		if #ids == 0 then
			order += 1
			Ui.Label(State:T("trade_nothing"), self.Body, {TextTransparency = 0.5, LayoutOrder = order})
		end
		for _, id in ipairs(ids) do
			order += 1
			local _, buttons = self:Row(self.Body, order, itemText(lang, id, offer[id]))
			if mine then
				local less = Ui.Button("-1", buttons, {Name = "Less", Size = UDim2.new(0, 40, 1, 0), LayoutOrder = 1})
				less.Activated:Connect(function() act("offer", id, offer[id] - 1) end)
				local none = Ui.Button("x", buttons, {Name = "Remove", Size = UDim2.new(0, 32, 1, 0), LayoutOrder = 2})
				none.Activated:Connect(function() act("offer", id, 0) end)
			end
		end
	end
	section("trade_you_give", view.mine, true)
	section("trade_you_get", view.theirs, false)
	order += 1
	Ui.Label(State:T("trade_bag"), self.Body, {Font = Enum.Font.GothamBold, LayoutOrder = order})

	-- the bag: what the player can still add to the offer
	local items = State.profile and State.profile.inventory.items or {}
	for i, id in ipairs(sortedIds(items)) do
		local def = Items.Defs[id]
		local offered = view.mine[id] or 0
		if def and not def.noSlot and not Coop.Trade.Blocked[id] and items[id] > offered then
			local _, buttons = self:Row(self.Bag, i, itemText(lang, id, items[id] - offered))
			for j, step in ipairs({1, 10}) do
				local more = Ui.Button("+" .. step, buttons, {Name = "Add" .. step, Size = UDim2.new(0, 44, 1, 0), LayoutOrder = j})
				more.Activated:Connect(function() act("offer", id, math.min(items[id], offered + step)) end)
			end
		end
	end

	if view.confirmed then
		self.Status.Text = State:T("trade_wait_partner", view.partner.name)
	elseif view.partnerConfirmed then
		self.Status.Text = State:T("trade_partner_ready", view.partner.name)
	else
		self.Status.Text = ""
	end
	self.ConfirmButton.Text = State:T("trade_confirm")
	self.ConfirmButton.BackgroundColor3 = view.confirmed and Ui.GREY or Ui.GREEN
end

function TradeController:Start()
	self:Build()
	Net.Event("TradeEvent").OnClientEvent:Connect(function(kind, a, b)
		if kind == "request" then
			asking = {id = a, name = tostring(b), untilT = os.clock() + Coop.Trade.RequestSeconds}
			local mine = asking
			task.delay(Coop.Trade.RequestSeconds, function()
				if asking == mine then
					asking = nil
					self:Render()
				end
			end)
		elseif kind == "state" then
			local was = view
			view = a
			if view then
				self.Window.Visible = true
			elseif was then
				self.Window.Visible = false
			end
		elseif kind == "nearby" then
			nearby = type(a) == "table" and a or {}
		end
		self:Render()
	end)
	State.Changed:Connect(function() self:Render() end)
	self:Render()
end

return TradeController
