-- Events between the client and the server of the lobby (milestone 9). The same module as in the game place,
-- with the lobby's own list. The client sends intentions only; the server checks them and limits their rate.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = {}
Net.Events = {
	"LobbyState",  -- server -> client: the player's party, invitations and the other players in the lobby
	"LobbyAction", -- client -> server: format, invite, accept, decline, leave, kick, start, rejoin
	"Notify",      -- server -> client: a message (localization key and its arguments)
}
local FOLDER = "Remotes"

function Net.Setup()
	local f = ReplicatedStorage:FindFirstChild(FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = FOLDER
	end
	for _, n in ipairs(Net.Events) do
		if not f:FindFirstChild(n) then
			local r = Instance.new("RemoteEvent")
			r.Name = n
			r.Parent = f
		end
	end
	f.Parent = ReplicatedStorage
end

function Net.Event(name)
	return ReplicatedStorage:WaitForChild(FOLDER):WaitForChild(name)
end

-- Server handler: at most perSecond calls a second from one player
function Net.On(name, perSecond, handler)
	local ev = Net.Event(name)
	local buckets = {}
	ev.OnServerEvent:Connect(function(player, ...)
		local now = os.clock()
		local b = buckets[player]
		if not b then
			b = {tokens = perSecond, t = now}
			buckets[player] = b
		end
		b.tokens = math.min(perSecond, b.tokens + (now - b.t) * perSecond)
		b.t = now
		if b.tokens < 1 then return end
		b.tokens -= 1
		local ok, err = pcall(handler, player, ...)
		if not ok then warn("[Net] " .. name .. ": " .. tostring(err)) end
	end)
	Players.PlayerRemoving:Connect(function(p) buckets[p] = nil end)
end

function Net.Fire(player, name, ...)
	Net.Event(name):FireClient(player, ...)
end

return Net
