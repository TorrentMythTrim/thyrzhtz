-- Act 1, Mushroomhaven (milestone 8, design doc 7.1–7.4): elder quests, village restoration, residents,
-- the boss portal and the Rotten Stump-Lord. Everything a designer may want to change is in this file.
-- The quest chain, the portal stages and every number here are a draft that waits for approval (milestone 8 report).
-- Rewards are not set at all: quest rewards and the boss reward are open decisions.
local Act1 = {}

-- Design doc 2.4: a bigger team has to bring more. Multiplier of "deliver" objectives by team size
Act1.DeliverScale = {1, 2, 3, 4}
-- Design doc 6.2: rank also grows for quests. Rank XP for a finished quest, to every team member online. 0 = off
Act1.QuestXp = 0
-- How close a player must stand to the elder to take or hand in a quest, and to a captive to free them
Act1.TalkDistance = 18

-- The elder stands on the plaza between the big mushroom and his house: angle from north and distance from the centre
Act1.Elder = {Angle = 315, Distance = 16}

-- One restoration step per finished quest; step i repairs Repairs[i]. Portals open on the way (design doc 7.2):
-- the raid portal first, then the portal to the next land
Act1.Restoration = {
	Max = 6,
	Repairs = {"Ruin_1", "Ruin_2", "Ruin_3", "Ruin_4", "Ruin_5", "ElderHouse"},
	BossPortalAt = 3,
	NextPortalAt = 5,
	-- angle, distance, width and depth of the five ruined houses: the same numbers as in MapBuilder.Village
	Houses = {{22, 54, 16, 12}, {158, 52, 16, 12}, {205, 50, 18, 13}, {245, 56, 18, 13}, {287, 60, 14, 11}},
}

-- Residents held in the Old Garden. offset: X and Z from the centre of the garden. Once freed they stand at the stall
Act1.Residents = {
	{id = "resident_1", name = {en = "Villager", ru = "Житель"}, offset = Vector2.new(-80, 62)},
	{id = "resident_2", name = {en = "Villager", ru = "Жительница"}, offset = Vector2.new(80, 62)},
}

-- The elder's chain, in order. Objective types:
--   deliver {item, count} — hand items to the elder; count is multiplied by DeliverScale
--   kill {monster, count}
--   rescue {resident}
-- rewards (optional): {items = {[itemId] = count}}, given to the player who hands the quest in
Act1.Quests = {
	{id = "elder_1", objectives = {{type = "deliver", item = "mushroom_fly_agaric", count = 3}}},
	{id = "elder_2", objectives = {{type = "kill", monster = "rot_sprout", count = 3}}},
	{id = "elder_3", objectives = {{type = "rescue", resident = "resident_1"}}},
	{id = "elder_4", objectives = {{type = "deliver", item = "mushroom_toxic_toadstool", count = 2}}},
	{id = "elder_5", objectives = {{type = "rescue", resident = "resident_2"}, {type = "kill", monster = "mold_slug", count = 2}}},
	{id = "elder_6", objectives = {{type = "deliver", item = "mycelium_essence", count = 2}}},
}

-- Boss portal (design doc 1.3, 1.5, 4.5): stages on the way to the boss. A cleared stage adds its loot to the
-- portal loot, which is lost on death inside the portal, and reveals a lore fragment
Act1.Portal = {
	Stages = {
		{monsters = {{"rot_sprout", 3}}, loot = {mycelium_essence = 1}, lore = "lore_act1_1"},
		{monsters = {{"rot_sprout", 2}, {"spore_mosquito", 2}}, loot = {nutrient_compost = 2}, lore = "lore_act1_2"},
	},
	ExitSeconds = 10, -- after the victory the team is taken back to the village
	MaxRuns = 20, -- one run per team; a server holds at most 20 teams
	-- arenas hang above the map, inside its X and Z bounds, one above another
	Center = Vector2.new(0, -40),
	BaseHeight = 600,
	HeightStep = 140,
	Width = 72,
	StageDepth = 46,
	BossDepth = 80,
	WallHeight = 36,
}

-- Rotten Stump-Lord (design doc 7.4). Health of the boss and of a growth is in Config.Monsters.Summons
Act1.Boss = {
	Id = "rot_stump",
	GrowthId = "rot_growth",
	SproutId = "rot_sprout",
	Growths = 3, -- three infected growths, then the heart
	Root = {Interval = 6, Telegraph = 1.4, Length = 60, Width = 6, Damage = 20},
	Summon = {Interval = 14, Count = 2, MaxAlive = 4},
}

function Act1.TeamSize(n)
	return math.clamp(math.floor(tonumber(n) or 1), 1, #Act1.DeliverScale)
end

-- How much of an objective a team of this size needs
function Act1.Required(objective, teamSize)
	local count = objective.count or 1
	if objective.type == "deliver" then
		return count * Act1.DeliverScale[Act1.TeamSize(teamSize)]
	end
	return count
end

-- The quest the team is on: the first one of the chain that is not completed. nil when the chain is finished
function Act1.CurrentQuest(team)
	local done = team and team.quests and team.quests.completed or {}
	for index, quest in ipairs(Act1.Quests) do
		if not done[quest.id] then return quest, index end
	end
	return nil
end

-- Progress of one objective as have, need. state is team.quests.active[quest.id], nil while the quest is not taken
function Act1.ObjectiveProgress(team, quest, index, state)
	local objective = quest.objectives[index]
	if objective.type == "rescue" then
		local rescued = team and team.village and team.village.rescued
		return (rescued and rescued[objective.resident]) and 1 or 0, 1
	end
	local need = Act1.Required(objective, state and state.size or 1)
	local have = state and state.progress and tonumber(state.progress[index]) or 0
	return math.min(have, need), need
end

return Act1
