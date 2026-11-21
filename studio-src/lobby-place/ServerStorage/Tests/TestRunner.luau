-- Мини-фреймворк автотестов. Спеки — модули *.spec, возвращают function(it, expect, ctx)
local Runner = {}

function Runner.Expect(v)
	local e = {}
	function e.toBe(x)
		if v ~= x then error(string.format("expected %s, got %s", tostring(x), tostring(v)), 2) end
	end
	function e.toNear(x, eps)
		eps = eps or 1e-6
		if type(v) ~= "number" or math.abs(v - x) > eps then
			error(string.format("expected %s (+-%s), got %s", tostring(x), tostring(eps), tostring(v)), 2)
		end
	end
	function e.toBeTruthy()
		if not v then error("expected truthy, got " .. tostring(v), 2) end
	end
	return e
end

-- only — часть имени спека (например "AuditAlchemy"): запускаются только подходящие спеки; без него — все
function Runner.Run(folder, ctx, only)
	local res = {passed = 0, failed = 0, failures = {}}
	local exact = only and folder:FindFirstChild(only) -- точное имя спека важнее совпадения по части имени: "Combat.spec" не запускает ещё и "AuditCombat.spec"
	for _, spec in ipairs(folder:GetChildren()) do
		if spec:IsA("ModuleScript") and string.match(spec.Name, "%.spec$") and (only == nil or (exact ~= nil and spec == exact) or (exact == nil and string.find(spec.Name, only, 1, true) ~= nil)) then
			local ok, fn = pcall(require, spec)
			if not ok or type(fn) ~= "function" then
				res.failed += 1
				table.insert(res.failures, spec.Name .. ": load error: " .. tostring(fn))
			else
				local function it(name, body)
					local ok2, err = pcall(body)
					if ok2 then
						res.passed += 1
					else
						res.failed += 1
						table.insert(res.failures, spec.Name .. " > " .. name .. ": " .. tostring(err))
					end
				end
				local okRun, errRun = pcall(fn, it, Runner.Expect, ctx)
				if not okRun then
					res.failed += 1
					table.insert(res.failures, spec.Name .. ": " .. tostring(errRun))
				end
			end
		end
	end
	return res
end

return Runner
