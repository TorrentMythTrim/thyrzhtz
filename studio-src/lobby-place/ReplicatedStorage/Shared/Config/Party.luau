-- Party formats (design doc 2.1 and 2.2, decision 2). The same numbers as in Config.Party of the game place:
-- a party of `size` Guardians goes to a server of its format, which has `houses` houses
return {
	MaxSize = 4,
	ServerPlayers = 20,
	Formats = {
		{id = "solo", size = 1, houses = 20},
		{id = "duo", size = 2, houses = 10},
		{id = "trio", size = 3, houses = 6},
		{id = "quartet", size = 4, houses = 5},
	},
}
