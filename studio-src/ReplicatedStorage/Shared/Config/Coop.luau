-- Co-op numbers of milestone 9 (design doc 2.5, 6.7; decision 2): the idle check, item trade, house decoration
-- and the link to the lobby. The idle times are from the design document. The trade and decoration numbers are
-- a draft that waits for approval (milestone 9 report).
local Coop = {}

-- Design doc 2.5: after 15 minutes without input the "Don't sleep!" window appears with a 30-second timer
Coop.Afk = {
	IdleSeconds = 15 * 60,
	PromptSeconds = 30,
	PingSeconds = 20, -- the client reports that the player is active at most this often
}

-- Design doc 6.7: item trade. Both players confirm, then one server operation moves the items
Coop.Trade = {
	MaxDistance = 24,    -- studs between the two players, checked on the server
	RequestSeconds = 20, -- an offer to trade waits this long for an answer
	MaxLines = 8,        -- different items one player can put into one trade
	MaxCount = 10000,    -- of one item in one trade: the limit of a single inventory operation
	-- Items that cannot be traded. Draft: the research book is personal (design doc 2.3), and without the basket
	-- or the starting sickle a player cannot harvest
	Blocked = {research_book = true, basket = true, simple_sickle = true},
}

-- Design doc 6.7: the team decorates its house together. Draft: cosmetic items stand at fixed spots in front of
-- the house. side: -1 left of the door, 1 right of it; inset: studs from the corner of the house towards the door
Coop.Decor = {
	Spots = {
		{side = -1, inset = 1.5}, {side = 1, inset = 1.5},
		{side = -1, inset = 5.5}, {side = 1, inset = 5.5},
	},
	Models = {lantern_banner = "LanternBanner"},
}

-- The lobby (decision 2; design doc 1.3: the game starts with the lobby)
Coop.Lobby = {
	-- A player who enters the game place without a ticket from the lobby is sent to the lobby. Never in Studio.
	-- false: such a player plays at once as a team of one, as before milestone 9
	RedirectDirectJoins = true,
	RedirectWaitSeconds = 20, -- a player who is still here this long after being sent plays here after all
	HeartbeatSeconds = 30,    -- a game server tells the lobby about its free houses this often
}

return Coop
