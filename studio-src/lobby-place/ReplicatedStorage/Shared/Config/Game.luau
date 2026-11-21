-- Places of the experience (decision 2): the lobby and one game place with servers matched by party format.
-- The same ids are in Config.Game of the game place
return {
	Version = "0.1.0",
	Places = {
		Lobby = 106448766989936,
		Game = 129614341268000,
	},
	-- Decision 6: English by default, Russian in the settings
	DefaultLanguage = "en",
	Languages = {"en", "ru"},
}
