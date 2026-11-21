-- Загрузчик модулей: подключает все модули папки, вызывает Init, затем Start.
-- Модули обращаются друг к другу через Loader.Get("ИмяМодуля").
local Loader = {}
local registry = {}
local order = {}

function Loader.Add(folder)
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("ModuleScript") then
			local ok, mod = pcall(require, m)
			if ok and type(mod) == "table" then
				mod.Name = mod.Name or m.Name
				registry[m.Name] = mod
				table.insert(order, mod)
			else
				warn("[Loader] не удалось загрузить " .. m:GetFullName() .. ": " .. tostring(mod))
			end
		end
	end
	table.sort(order, function(a, b) return (a.Priority or 0) > (b.Priority or 0) end)
end

function Loader.Get(name)
	local m = registry[name]
	if not m then error("[Loader] модуль не найден: " .. tostring(name), 2) end
	return m
end

function Loader.Start()
	for _, m in ipairs(order) do
		if type(m.Init) == "function" then
			local ok, err = pcall(m.Init, m)
			if not ok then warn("[Loader] Init " .. m.Name .. ": " .. tostring(err)) end
		end
	end
	for _, m in ipairs(order) do
		if type(m.Start) == "function" then
			task.spawn(function()
				local ok, err = pcall(m.Start, m)
				if not ok then warn("[Loader] Start " .. m.Name .. ": " .. tostring(err)) end
			end)
		end
	end
end

return Loader
