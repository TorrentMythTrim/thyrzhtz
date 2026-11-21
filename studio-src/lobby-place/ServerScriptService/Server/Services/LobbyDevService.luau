-- Studio only: the entry for automated tests through MCP (execute_luau on the server in Play mode), as in the
-- game place: ServerStorage.GS_TestHook:Invoke("run_tests", folderOrPartOfSpecName, partOfSpecName)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DevService = {Priority = 10}

function DevService:Start()
	if not RunService:IsStudio() then return end
	local old = ServerStorage:FindFirstChild("GS_TestHook")
	if old then old:Destroy() end
	local hook = Instance.new("BindableFunction")
	hook.Name = "GS_TestHook"
	hook.OnInvoke = function(cmd, a, b)
		if cmd == "run_tests" then
			local Runner = require(ServerStorage.Tests.TestRunner)
			local ctx = {shared = ReplicatedStorage.Shared, live = true}
			local folder = typeof(a) == "Instance" and a or ServerStorage.Tests
			local only = (type(a) == "string" and a) or (type(b) == "string" and b) or nil
			return Runner.Run(folder, ctx, only)
		end
		return {error = "unknown " .. tostring(cmd)}
	end
	hook.Parent = ServerStorage
end

return DevService
