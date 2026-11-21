-- Item trade (milestone 9, design doc 6.7; technical plan, milestone 9, item 5): two players put items on the
-- table, both confirm, and the server moves everything in one operation, so nothing is lost and nothing is
-- duplicated. Any change of an offer takes both confirmations back. Only items are traded, not currencies.
-- The client sends intentions; the distance, the items and the room in the bags are checked here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Util = require(Shared.Modules.Util)
local Items = require(Shared.Config.Items)
local Coop = require(Shared.Config.Coop)

local TradeService = {Priority = 35}
TradeService.Clock = os.clock -- tests move time by replacing this
local DataService, InventoryService, PlayerService
local requests = {} -- [target] = {[from] = expiresAt}
local sessions = {} -- [player] = trade {a, b, offers = {[player] = {[itemId] = count}}, confirmed = {[player] = bool}}

-- Tests use stand-in players (tables); they get no network messages
local function isReal(player)
	return typeof(player) == "Instance"
end

local function tell(player, key, ...)
	if isReal(player) and player.Parent then Net.Fire(player, "Notify", key, ...) end
end

local function send(player, ...)
	if isReal(player) and player.Parent then Net.Fire(player, "TradeEvent", ...) end
end

local function nameOf(player)
	return player.DisplayName or player.Name
end

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

function TradeService:Init()
	DataService = Loader.Get("DataService")
	InventoryService = Loader.Get("InventoryService")
	PlayerService = Loader.Get("PlayerService")
end

-- Are the two close enough to trade? The server measures it, the client's word is not taken
function TradeService:Near(a, b)
	local ra, rb = rootOf(a), rootOf(b)
	return ra ~= nil and rb ~= nil and (ra.Position - rb.Position).Magnitude <= Coop.Trade.MaxDistance
end

function TradeService.CanTrade(itemId)
	local def = Items.Defs[itemId]
	return def ~= nil and not def.noSlot and not Coop.Trade.Blocked[itemId]
end

function TradeService:GetTrade(player)
	return sessions[player]
end

-- Players close enough to offer a trade to
function TradeService:Nearby(player)
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and DataService:GetProfile(other) and self:Near(player, other) then
			table.insert(list, {id = other.UserId, name = nameOf(other), busy = sessions[other] ~= nil})
		end
	end
	table.sort(list, function(x, y) return x.id < y.id end)
	return list
end

-- Offer a trade to another player. ignoreDistance is for tests
function TradeService:Request(player, target, ignoreDistance)
	if not target or target == player then return false, "unknown" end
	if not (DataService:GetProfile(player) and DataService:GetProfile(target)) then return false, "unknown" end
	if sessions[player] or sessions[target] then
		tell(player, "trade_busy")
		return false, "busy"
	end
	if not ignoreDistance and not self:Near(player, target) then
		tell(player, "trade_too_far")
		return false, "too_far"
	end
	requests[target] = requests[target] or {}
	requests[target][player] = TradeService.Clock() + Coop.Trade.RequestSeconds
	send(target, "request", player.UserId, nameOf(player))
	tell(player, "trade_sent", nameOf(target))
	return true
end

-- The other player accepts or declines the offer; accepting opens the trade
function TradeService:Answer(player, from, accept, ignoreDistance)
	local set = requests[player]
	local expires = set and from and set[from]
	if not expires then return false, "expired" end
	set[from] = nil
	if not accept then
		tell(from, "trade_declined", nameOf(player))
		return true, "declined"
	end
	if expires <= TradeService.Clock() then
		tell(player, "trade_expired")
		return false, "expired"
	end
	if sessions[player] or sessions[from] then
		tell(player, "trade_busy")
		return false, "busy"
	end
	if not ignoreDistance and not self:Near(player, from) then
		tell(player, "trade_too_far")
		return false, "too_far"
	end
	local trade = {
		a = from, b = player, anywhere = ignoreDistance == true,
		offers = {[from] = {}, [player] = {}},
		confirmed = {[from] = false, [player] = false},
	}
	sessions[from], sessions[player] = trade, trade
	self:Sync(trade)
	return true, "opened"
end

-- What one side sees of its trade
function TradeService:View(player)
	local trade = sessions[player]
	if not trade then return nil end
	local other = trade.a == player and trade.b or trade.a
	return {
		partner = {id = other.UserId, name = nameOf(other)},
		mine = trade.offers[player], theirs = trade.offers[other],
		confirmed = trade.confirmed[player], partnerConfirmed = trade.confirmed[other],
	}
end

function TradeService:Sync(trade)
	for _, p in ipairs({trade.a, trade.b}) do send(p, "state", self:View(p)) end
end

-- Put `count` of an item on the table; 0 takes it off. Any change takes both confirmations back
function TradeService:SetOffer(player, itemId, count)
	local trade = sessions[player]
	if not trade then return false, "no_trade" end
	count = tonumber(count)
	if type(itemId) ~= "string" or not count or count ~= count or count < 0 or count > Coop.Trade.MaxCount then return false, "bad" end
	count = math.floor(count)
	if not TradeService.CanTrade(itemId) then
		tell(player, "trade_blocked")
		return false, "blocked"
	end
	if count > InventoryService:Count(player, itemId) then return false, "not_enough" end
	local offer = trade.offers[player]
	if count > 0 and not offer[itemId] and Util.Count(offer) >= Coop.Trade.MaxLines then
		tell(player, "trade_limit")
		return false, "limit"
	end
	offer[itemId] = count > 0 and count or nil
	local wasConfirmed = trade.confirmed[trade.a] or trade.confirmed[trade.b]
	trade.confirmed[trade.a], trade.confirmed[trade.b] = false, false
	if wasConfirmed then
		tell(trade.a, "trade_changed")
		tell(trade.b, "trade_changed")
	end
	self:Sync(trade)
	return true
end

-- A player agrees to the trade as it is now. When both have agreed, it happens
function TradeService:Confirm(player)
	local trade = sessions[player]
	if not trade then return false, "no_trade" end
	trade.confirmed[player] = true
	if not (trade.confirmed[trade.a] and trade.confirmed[trade.b]) then
		self:Sync(trade)
		return true, "waiting"
	end
	return self:Execute(trade)
end

-- Both confirmed: everything moves in one step, with no wait in between. Either both bags change or neither does
function TradeService:Execute(trade)
	local a, b = trade.a, trade.b
	sessions[a], sessions[b] = nil, nil
	local pa, pb = DataService:GetProfile(a), DataService:GetProfile(b)
	local ok, reason = pa ~= nil and pb ~= nil, "failed"
	if ok and not trade.anywhere and not self:Near(a, b) then ok, reason = false, "too_far" end
	if ok then
		-- every item may still be traded and is still there, and each bag has room for what it gets
		for _, p in ipairs({a, b}) do
			for itemId in pairs(trade.offers[p]) do
				if not TradeService.CanTrade(itemId) then ok = false end
			end
		end
		ok = ok and InventoryService:CanExchange(a, trade.offers[a], trade.offers[b])
			and InventoryService:CanExchange(b, trade.offers[b], trade.offers[a])
	end
	if ok then
		local before = {Util.DeepCopy(pa.inventory), Util.DeepCopy(pb.inventory)}
		local moved = true
		for itemId, n in pairs(trade.offers[a]) do moved = moved and InventoryService:Take(a, itemId, n) end
		for itemId, n in pairs(trade.offers[b]) do moved = moved and InventoryService:Take(b, itemId, n) end
		for itemId, n in pairs(trade.offers[a]) do moved = moved and InventoryService:Give(b, itemId, n) end
		for itemId, n in pairs(trade.offers[b]) do moved = moved and InventoryService:Give(a, itemId, n) end
		if not moved then
			-- the checks above rule this out; if it happens anyway, both bags go back to what they were
			pa.inventory, pb.inventory = before[1], before[2]
			ok = false
		end
	end
	for _, p in ipairs({a, b}) do
		send(p, "state", nil)
		tell(p, ok and "trade_done" or (reason == "too_far" and "trade_too_far" or "trade_failed"))
		if isReal(p) then PlayerService:Push(p) end
	end
	if ok then
		-- the two bags are two saved records: both are saved right away, so that the time in which a crash could
		-- leave only one of them written is short
		for _, p in ipairs({a, b}) do
			task.spawn(function() DataService:SaveNow(p) end)
		end
	end
	return ok, ok and "done" or reason
end

function TradeService:Cancel(player)
	local trade = sessions[player]
	if not trade then return false end
	sessions[trade.a], sessions[trade.b] = nil, nil
	for _, p in ipairs({trade.a, trade.b}) do
		send(p, "state", nil)
		tell(p, "trade_cancelled")
	end
	return true
end

-- A player is leaving: the trade ends and the offers to and from the player go away
function TradeService:Forget(player)
	self:Cancel(player)
	requests[player] = nil
	for _, set in pairs(requests) do set[player] = nil end
end

function TradeService:Start()
	Players.PlayerRemoving:Connect(function(player) self:Forget(player) end)
	Net.On("TradeAction", 8, function(player, action, a, b)
		if action == "nearby" then
			send(player, "nearby", self:Nearby(player))
		elseif action == "request" then
			self:Request(player, Players:GetPlayerByUserId(tonumber(a) or 0))
		elseif action == "answer" then
			self:Answer(player, Players:GetPlayerByUserId(tonumber(a) or 0), b == true)
		elseif action == "offer" then
			self:SetOffer(player, a, b)
		elseif action == "confirm" then
			self:Confirm(player)
		elseif action == "cancel" then
			self:Cancel(player)
		end
	end)
end

return TradeService
