-- События для связи клиента и сервера.
-- Клиент отправляет только намерения, сервер проверяет их и ограничивает частоту запросов.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = {}
Net.Events = {
	"Snapshot",            -- сервер -> клиент: состояние профиля и команды
	"Notify",              -- сервер -> клиент: всплывающее сообщение (ключ локализации)
	"SetSetting",          -- клиент -> сервер: изменить настройку (язык)
	"DevCommand",          -- клиент -> сервер: команда панели разработчика
	"SetHotbar",           -- клиент -> сервер: положить предмет в ячейку панели быстрого доступа
	"SelectSlot",          -- клиент -> сервер: выбрать ячейку панели (0 — ничего)
	"FarmFx",              -- сервер -> клиент: эффект на грядке (срезанный гриб летит в корзину)
	"AlchemyMix",          -- клиент -> сервер: смешать ингредиенты в ячейках алхимического стола (веха 4)
	"AlchemyResult",       -- сервер -> клиент: итог смешивания и подсказка Алхимика
	"AlchemyFx",           -- сервер -> всем клиентам: эффект взрыва или выведения мутации на столе
	"ReadMutationBook",    -- клиент -> сервер: прочитать книгу мутаций и открыть рецепт команде
	"ClaimIndexMilestone", -- клиент -> сервер: забрать награду за рубеж Индекса грибов
	"CombatAction",        -- клиент -> сервер: удар, блок, зелье, способность Q/R/T, назначение слота, призыв питомца (веха 5)
	"CombatFx",            -- сервер -> клиентам: визуал ударов, снарядов, реакций, телепорта и исцеления
	"DefenseAction",       -- клиент -> сервер: ворота, руна погодного тотема, зов о помощи и отклик на помощь (веха 6)
	"WaveState",           -- сервер -> клиенту: состояние волны обороны на участке (подготовка, бой, итог)
	"HelpAlert",           -- сервер -> клиентам: объявление о помощи со своего или другого сервера
	"WeatherFx",           -- сервер -> клиентам: удар молнии по грядке / погодные события
	"Act1Action",          -- клиент -> сервер: принять и сдать задание старосты (веха 8)
	"Act1Event",           -- сервер -> клиенту: окно старосты и найденный фрагмент лора (веха 8)
	"EconomyAction",       -- клиент -> сервер: улучшения, навыки, пресс, кузница, магазин и Алтарь Звёздных печатей (веха 7)
	"LobbyAction",         -- клиент -> сервер: вернуться в лобби (веха 9)
	"AfkPrompt",           -- сервер -> клиенту: окно «Не спи!» с таймером (веха 9, шаг 2.5 ДД)
	"AfkAction",           -- клиент -> сервер: игрок что-то делает / нажал «Не сплю»
	"TradeAction",         -- клиент -> сервер: обмен предметами — предложить, ответить, положить, подтвердить, отменить (веха 9)
	"TradeEvent",          -- сервер -> клиенту: предложение обмена, состояние обмена, игроки рядом
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

-- Обработчик на сервере: не больше perSecond вызовов в секунду от одного игрока
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

function Net.FireAll(name, ...)
	Net.Event(name):FireAllClients(...)
end

return Net
