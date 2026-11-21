-- Idle check (milestone 9, design doc 2.5): after 15 minutes without input the player sees the "Don't sleep!"
-- window with an "I'm awake" button and a 30-second timer; whoever does not press it in time is removed from the
-- server. The client only reports that there was input; the times are counted here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local Locale = require(Shared.Modules.Locale)
local Coop = require(Shared.Config.Coop)

local AfkService = {Priority = 40}
local DataService
local state = {} -- [player] = {active = time of the last input, deadline = when the window runs out (nil: not shown)}

function AfkService:Init()
	DataService = Loader.Get("DataService")
end

function AfkService:Track(player, now)
	state[player] = {active = now or os.clock()}
end

function AfkService:Forget(player)
	state[player] = nil
end

-- The client saw input. While the window is open only its button counts
function AfkService:Active(player, now)
	local s = state[player]
	if s and not s.deadline then s.active = now or os.clock() end
end

-- The "I'm awake" button
function AfkService:Awake(player, now)
	local s = state[player]
	if not (s and s.deadline) then return false end
	s.deadline = nil
	s.active = now or os.clock()
	return true
end

function AfkService:IsPrompted(player)
	local s = state[player]
	return s ~= nil and s.deadline ~= nil
end

-- One step for every player. now is passed in so that tests can move time themselves
function AfkService:Step(now)
	for player, s in pairs(state) do
		if s.deadline then
			if now >= s.deadline then
				state[player] = nil
				local profile = DataService:GetProfile(player)
				local lang = profile and profile.settings and profile.settings.language or Locale.Default
				player:Kick(Locale.T(lang, "afk_kick"))
			end
		elseif now - s.active >= Coop.Afk.IdleSeconds then
			s.deadline = now + Coop.Afk.PromptSeconds
			if typeof(player) == "Instance" then Net.Fire(player, "AfkPrompt", Coop.Afk.PromptSeconds) end
		end
	end
end

function AfkService:Start()
	Players.PlayerAdded:Connect(function(player) self:Track(player) end)
	for _, player in ipairs(Players:GetPlayers()) do self:Track(player) end
	Players.PlayerRemoving:Connect(function(player) self:Forget(player) end)
	Net.On("AfkAction", 2, function(player, action)
		if action == "awake" then
			self:Awake(player)
		else
			self:Active(player)
		end
	end)
	while true do
		task.wait(1)
		self:Step(os.clock())
	end
end

return AfkService
