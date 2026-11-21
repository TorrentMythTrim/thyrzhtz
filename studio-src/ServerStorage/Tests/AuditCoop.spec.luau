-- Milestone 9 (2026-11-21): the idle check, item trade and house decoration
-- (technical plan, milestone 9, items 4, 5 and 7; design doc 2.5, 6.7).
-- Other players are stand-ins (tables). Their profiles are made only in memory mode, so the trade tests run only
-- there. Time is passed in, nobody waits. What the tests change for the real player and in the services is put back.
return function(it, expect, ctx)
	local Coop = require(ctx.shared.Config.Coop)
	local Items = require(ctx.shared.Config.Items)

	it("M9 co-op numbers: the idle times of the design document; every blocked or decorative item exists", function()
		expect(Coop.Afk.IdleSeconds).toBe(15 * 60)
		expect(Coop.Afk.PromptSeconds).toBe(30)
		expect(Coop.Trade.MaxLines >= 1 and Coop.Trade.MaxCount >= 1).toBeTruthy()
		for id in pairs(Coop.Trade.Blocked) do expect(Items.Defs[id] ~= nil).toBeTruthy() end
		local models = 0
		for id, model in pairs(Coop.Decor.Models) do
			models += 1
			expect(Items.Defs[id].kind).toBe("cosmetic")
			expect(type(model)).toBe("string")
		end
		expect(models >= 1 and #Coop.Decor.Spots >= 1).toBeTruthy()
	end)

	if not ctx.live then return end
	local Loader = require(ctx.shared.Modules.Loader)
	local Locale = require(ctx.shared.Modules.Locale)
	local Util = require(ctx.shared.Modules.Util)
	local Afk, Trade, Decor = Loader.Get("AfkService"), Loader.Get("TradeService"), Loader.Get("DecorService")
	local Inv, DS, PS = Loader.Get("InventoryService"), Loader.Get("DataService"), Loader.Get("PartyService")
	local Players = game:GetService("Players")
	local player = Players:GetPlayers()[1]

	local function bot(id)
		local b = {UserId = id, Name = "AuditBot" .. id, DisplayName = "AuditBot", Parent = workspace, attrs = {}}
		function b:Kick(message) self.kicked = message or true end
		function b:SetAttribute(key, value) self.attrs[key] = value end
		function b:GetAttribute(key) return self.attrs[key] end
		return b
	end

	it("M9 idle check: the window after 15 minutes without input, 30 seconds to answer, then the player is removed", function()
		-- the step goes over every player: the real ones are left out while time is moved by hand
		local real = Players:GetPlayers()
		for _, p in ipairs(real) do Afk:Forget(p) end
		local b = bot(-9251)
		local ok, err = pcall(function()
			local idle, answer = Coop.Afk.IdleSeconds, Coop.Afk.PromptSeconds
			Afk:Track(b, 0)
			Afk:Step(idle - 1)
			expect(Afk:IsPrompted(b)).toBe(false)
			Afk:Active(b, idle - 1) -- input: the 15 minutes start again
			Afk:Step(2 * idle - 2)
			expect(Afk:IsPrompted(b)).toBe(false)
			Afk:Step(2 * idle - 1)
			expect(Afk:IsPrompted(b)).toBe(true)
			-- while the window is open, ordinary input does not close it
			Afk:Active(b, 2 * idle)
			Afk:Step(2 * idle - 1 + answer - 1)
			expect(Afk:IsPrompted(b)).toBe(true)
			expect(b.kicked).toBe(nil)
			-- the button closes it in time and the 15 minutes start again
			local t = 2 * idle - 1 + answer - 1
			expect(Afk:Awake(b, t)).toBe(true)
			expect(Afk:IsPrompted(b)).toBe(false)
			expect(Afk:Awake(b, t)).toBe(false) -- no window, nothing to answer
			Afk:Step(t + idle - 1)
			expect(Afk:IsPrompted(b)).toBe(false)
			Afk:Step(t + idle)
			expect(Afk:IsPrompted(b)).toBe(true)
			Afk:Step(t + idle + answer - 1)
			expect(b.kicked).toBe(nil)
			-- no answer in 30 seconds
			Afk:Step(t + idle + answer)
			expect(b.kicked).toBe(Locale.T(Locale.Default, "afk_kick"))
			expect(Afk:IsPrompted(b)).toBe(false)
		end)
		Afk:Forget(b)
		for _, p in ipairs(real) do Afk:Track(p) end
		if not ok then error(err, 0) end
	end)

	it("M9 decoration: a member of the team puts a decoration up at its house and takes it back; it is in the team record", function()
		local ITEM = "lantern_banner"
		local host = PS:GetHost(player)
		local plot = Decor:PlotOf(host)
		local team = DS:GetTeam(host)
		expect(plot ~= nil and team ~= nil).toBeTruthy()
		local had = Inv:Count(player, ITEM)
		local before = team.house and team.house.decorations and Util.DeepCopy(team.house.decorations) or nil
		local ok, err = pcall(function()
			if team.house then team.house.decorations = {} end
			Decor:Render(host)
			if had > 0 then expect(Inv:Take(player, ITEM, had)).toBe(true) end
			local spots = Decor.SpotCFrames(plot)
			expect(#spots).toBe(#Coop.Decor.Spots)
			-- nothing to put up
			local done, why = Decor:Use(player, plot, 1, true)
			expect(done).toBe(false)
			expect(why).toBe("no_item")
			expect(Inv:Give(player, ITEM, 1)).toBe(true)
			-- only the team that lives in the house, only a spot that exists
			done, why = Decor:Use(bot(-9261), plot, 1, true)
			expect(done).toBe(false)
			expect(why).toBe("not_yours")
			done, why = Decor:Use(player, plot, #spots + 1, true)
			expect(done).toBe(false)
			expect(why).toBe("unknown")
			expect(Inv:Count(player, ITEM)).toBe(1)
			-- up: the item leaves the bag and stands at the spot
			expect(Decor:Use(player, plot, 1, true)).toBe(true)
			expect(Inv:Count(player, ITEM)).toBe(0)
			local entry = DS:GetTeam(host).house.decorations["1"]
			expect(entry.item).toBe(ITEM)
			expect(entry.by).toBe(player.UserId)
			local shown = plot.Decor:FindFirstChild("Item_1")
			expect(shown ~= nil and shown:GetAttribute("Item") == ITEM).toBeTruthy()
			expect((shown:GetPivot().Position - spots[1].Position).Magnitude < 0.1).toBeTruthy()
			expect(plot.Decor:FindFirstChild("Item_2")).toBe(nil)
			-- down: the same item comes back, nothing is made or lost
			expect(Decor:Use(player, plot, 1, true)).toBe(true)
			expect(Inv:Count(player, ITEM)).toBe(1)
			expect(DS:GetTeam(host).house.decorations["1"]).toBe(nil)
			expect(plot.Decor:FindFirstChild("Item_1")).toBe(nil)
		end)
		if team.house then team.house.decorations = before or {} end
		Decor:Render(host)
		local now = Inv:Count(player, ITEM)
		if now > had then Inv:Take(player, ITEM, now - had) elseif now < had then Inv:Give(player, ITEM, had - now) end
		if not ok then error(err, 0) end
	end)

	if not DS:IsMemoryMode() then return end
	local X, Y = "mushroom_fly_agaric", "mushroom_toxic_toadstool"

	-- three stand-ins with profiles: a has 5 of X, b has 3 of Y, c has nothing to trade
	local function traders(fn)
		local a, b, c = bot(-9241), bot(-9242), bot(-9243)
		local saved = {Trade.Clock, Inv.Give}
		local ok, err = pcall(function()
			for _, p in ipairs({a, b, c}) do
				expect(DS:LoadProfile(p) ~= nil).toBeTruthy()
				Inv:EnsureStarterKit(p)
				for _, id in ipairs({X, Y}) do
					local n = Inv:Count(p, id)
					if n > 0 then Inv:Take(p, id, n) end
				end
			end
			expect(Inv:Give(a, X, 5)).toBe(true)
			expect(Inv:Give(b, Y, 3)).toBe(true)
			fn(a, b, c)
		end)
		Trade.Clock, Inv.Give = saved[1], saved[2]
		for _, p in ipairs({a, b, c}) do
			Trade:Forget(p)
			DS:ReleaseProfile(p)
		end
		if not ok then error(err, 0) end
	end
	local function bags(a, b)
		return string.format("%d %d | %d %d", Inv:Count(a, X), Inv:Count(a, Y), Inv:Count(b, X), Inv:Count(b, Y))
	end
	local function open(a, b)
		expect(Trade:Request(a, b, true)).toBe(true)
		local done, why = Trade:Answer(b, a, true, true)
		expect(done).toBe(true)
		expect(why).toBe("opened")
	end

	it("M9 trade: both players confirm, then one operation moves the items; nothing is lost or doubled", function() traders(function(a, b, c)
		expect(bags(a, b)).toBe("5 0 | 0 3")
		local done, why = Trade:Request(a, a, true)
		expect(done).toBe(false)
		open(a, b)
		expect(Trade:GetTrade(a) ~= nil and Trade:GetTrade(a) == Trade:GetTrade(b)).toBeTruthy()
		-- one trade at a time: the same items cannot be offered in two trades
		done, why = Trade:Request(c, a, true)
		expect(done).toBe(false)
		expect(why).toBe("busy")
		-- the server checks every offer
		for _, case in ipairs({{X, 6, "not_enough"}, {"basket", 1, "blocked"}, {X, -1, "bad"}, {X, 0 / 0, "bad"}, {X, Coop.Trade.MaxCount + 1, "bad"}, {"no_such_item", 1, "blocked"}}) do
			done, why = Trade:SetOffer(a, case[1], case[2])
			expect(done).toBe(false)
			expect(why).toBe(case[3])
		end
		expect(Trade:SetOffer(a, X, 2)).toBe(true)
		expect(Trade:SetOffer(b, Y, 3)).toBe(true)
		-- one confirmation moves nothing
		done, why = Trade:Confirm(a)
		expect(done).toBe(true)
		expect(why).toBe("waiting")
		expect(bags(a, b)).toBe("5 0 | 0 3")
		-- a changed offer takes back both confirmations: nobody agrees to something he has not seen
		expect(Trade:SetOffer(b, Y, 1)).toBe(true)
		done, why = Trade:Confirm(b)
		expect(why).toBe("waiting")
		expect(bags(a, b)).toBe("5 0 | 0 3")
		-- both have confirmed the same offers
		done, why = Trade:Confirm(a)
		expect(done).toBe(true)
		expect(why).toBe("done")
		expect(bags(a, b)).toBe("3 1 | 2 2")
		expect(Trade:GetTrade(a)).toBe(nil)
		expect(Trade:GetTrade(b)).toBe(nil)
		-- the trade is over: it cannot be confirmed a second time
		done, why = Trade:Confirm(a)
		expect(done).toBe(false)
		expect(why).toBe("no_trade")
		expect(bags(a, b)).toBe("3 1 | 2 2")
	end) end)

	it("M9 trade: a trade that is declined, late, cancelled or cannot be completed leaves both bags as they were", function() traders(function(a, b)
		-- declined
		expect(Trade:Request(a, b, true)).toBe(true)
		local done, why = Trade:Answer(b, a, false, true)
		expect(why).toBe("declined")
		expect(Trade:GetTrade(a)).toBe(nil)
		-- answered too late
		local t = 100
		Trade.Clock = function() return t end
		expect(Trade:Request(a, b, true)).toBe(true)
		t += Coop.Trade.RequestSeconds
		done, why = Trade:Answer(b, a, true, true)
		expect(done).toBe(false)
		expect(why).toBe("expired")
		expect(Trade:GetTrade(a)).toBe(nil)
		-- cancelled by either side
		open(a, b)
		expect(Trade:SetOffer(a, X, 2)).toBe(true)
		expect(Trade:Confirm(a)).toBe(true)
		expect(Trade:Cancel(b)).toBe(true)
		expect(Trade:GetTrade(a)).toBe(nil)
		expect(bags(a, b)).toBe("5 0 | 0 3")
		-- an offered item is gone by the time both confirm
		open(b, a)
		expect(Trade:SetOffer(a, X, 2)).toBe(true)
		expect(Trade:SetOffer(b, Y, 3)).toBe(true)
		expect(Inv:Take(a, X, 4)).toBe(true)
		Trade:Confirm(a)
		done, why = Trade:Confirm(b)
		expect(done).toBe(false)
		expect(bags(a, b)).toBe("1 0 | 0 3")
		expect(Trade:GetTrade(a)).toBe(nil)
		expect(Inv:Give(a, X, 4)).toBe(true)
		-- a move fails in the middle: both bags go back to what they were
		open(a, b)
		expect(Trade:SetOffer(a, X, 2)).toBe(true)
		expect(Trade:SetOffer(b, Y, 3)).toBe(true)
		local give, calls = Inv.Give, 0
		Inv.Give = function(self, ...)
			calls += 1
			if calls == 2 then return false end
			return give(self, ...)
		end
		Trade:Confirm(a)
		done, why = Trade:Confirm(b)
		Inv.Give = give
		expect(calls).toBe(2)
		expect(done).toBe(false)
		expect(bags(a, b)).toBe("5 0 | 0 3")
		-- and the same trade goes through afterwards
		open(a, b)
		expect(Trade:SetOffer(a, X, 5)).toBe(true)
		expect(Trade:SetOffer(b, Y, 3)).toBe(true)
		Trade:Confirm(b)
		done, why = Trade:Confirm(a)
		expect(why).toBe("done")
		expect(bags(a, b)).toBe("0 3 | 5 0")
	end) end)
end
