-- Entry point of the lobby server
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared.Modules.Loader)
local Net = require(Shared.Modules.Net)
local GameConfig = require(Shared.Config.Game)

Net.Setup()
local ok, err = pcall(function() require(ServerStorage.Modules.LobbyBuilder).Ensure() end)
if not ok then warn("[Lobby] blockout: " .. tostring(err)) end
Loader.Add(script.Parent:WaitForChild("Services"))
Loader.Start()
print("[Lobby] Mushroom Guardians " .. GameConfig.Version .. ": lobby started")
