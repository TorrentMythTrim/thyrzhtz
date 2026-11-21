-- Entry point of the lobby client
if not game:IsLoaded() then game.Loaded:Wait() end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared.Modules.Loader)

Loader.Add(script.Parent:WaitForChild("Controllers"))
Loader.Start()
