-- Matchmaking (milestone 9, decision 2): the protocol between the lobby place and the game place.
-- The same file is in both places. The lobby keeps a list of game servers for every party format, holds a free
-- house for a party and writes a ticket for each member. The game server reads the ticket on arrival, so the host
-- and the format never come from TeleportData, which travels through the client and can be forged.
-- Storage is behind a small backend: MemoryStore sorted maps on live servers, a table in Studio and in tests.
local MemoryStoreService = game:GetService("MemoryStoreService")

local M = {}
M.Version = 1
M.Maps = {Servers = "GS9_Servers_", Tickets = "GS9_Tickets", Sessions = "GS9_Sessions"}
-- Seconds. A server entry lives while its server keeps reporting; a claim holds a house for a party that is on
-- its way; a ticket covers a slow teleport; a session lets a member who dropped out come back to the team
M.Ttl = {Server = 120, Claim = 120, Ticket = 300, Session = 120}
M.Attempts = 3
M.StudioServer = "studio" -- Studio has no server ids: a play session there is always this server
M.Now = os.time -- tests move time by replacing this

local backend

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end

-- A table that behaves like the sorted maps: values are copied in and out, and they expire
function M.LocalBackend()
	local maps = {}
	local B = {Kind = "local"}
	local function entry(name, key)
		maps[name] = maps[name] or {}
		local e = maps[name][key]
		if e and e.expires <= M.Now() then
			maps[name][key] = nil
			return nil
		end
		return e
	end
	function B.Get(name, key)
		local e = entry(name, key)
		return e and copy(e.value) or nil
	end
	function B.Set(name, key, value, ttl)
		entry(name, key)
		maps[name][key] = {value = copy(value), expires = M.Now() + ttl}
		return true
	end
	function B.Update(name, key, fn, ttl)
		local e = entry(name, key)
		local value = fn(e and copy(e.value) or nil)
		if value == nil then return nil end
		maps[name][key] = {value = copy(value), expires = M.Now() + ttl}
		return value
	end
	function B.Remove(name, key)
		entry(name, key)
		maps[name][key] = nil
		return true
	end
	function B.List(name, limit)
		local out = {}
		for key in pairs(maps[name] or {}) do
			local e = entry(name, key)
			if e then table.insert(out, {key = key, value = copy(e.value)}) end
		end
		table.sort(out, function(a, b) return a.key < b.key end)
		while #out > (limit or 100) do table.remove(out) end
		return out
	end
	return B
end

function M.MemoryStoreBackend()
	local B = {Kind = "memorystore"}
	local function map(name) return MemoryStoreService:GetSortedMap(name) end
	function B.Get(name, key) return map(name):GetAsync(key) end
	function B.Set(name, key, value, ttl) return map(name):SetAsync(key, value, ttl) end
	function B.Update(name, key, fn, ttl) return map(name):UpdateAsync(key, fn, ttl) end
	function B.Remove(name, key) return map(name):RemoveAsync(key) end
	function B.List(name, limit)
		local out = {}
		for _, item in ipairs(map(name):GetRangeAsync(Enum.SortDirection.Ascending, math.min(limit or 100, 200))) do
			table.insert(out, {key = item.key, value = item.value})
		end
		return out
	end
	return B
end

function M.UseBackend(b)
	backend = b
	return b
end

function M.Backend()
	return backend
end

-- Every store call may fail (limits, outages): a few attempts, then the caller gets false
local function try(op, ...)
	if not backend then error("[Matchmaking] no backend: call UseBackend first", 2) end
	local err
	for attempt = 1, M.Attempts do
		local res = table.pack(pcall(backend[op], ...))
		if res[1] then return true, res[2] end
		err = res[2]
		if attempt < M.Attempts then task.wait(0.5 * attempt) end
	end
	warn("[Matchmaking] " .. op .. " failed: " .. tostring(err))
	return false, err
end

-- What a game server is called in the list: a reserved server by its private id, Studio by a fixed word
function M.ServerId()
	if game.PrivateServerId ~= "" then return game.PrivateServerId end
	if game.JobId ~= "" then return game.JobId end
	return M.StudioServer
end

-- The id ReserveServer gave for a new server. In Studio it is empty
function M.ReservedId(privateServerId)
	return privateServerId ~= "" and privateServerId or M.StudioServer
end

function M.FormatBySize(formats, size)
	for _, f in ipairs(formats) do
		if f.size == size then return f end
	end
	return nil
end

local function prune(entry, now)
	entry.claims = type(entry.claims) == "table" and entry.claims or {}
	for host, expires in pairs(entry.claims) do
		if type(expires) ~= "number" or expires <= now then entry.claims[host] = nil end
	end
	return entry
end

-- Houses of a server that the lobby may still give out: the free ones minus those held for parties on their way
function M.OpenHouses(entry, now)
	now = now or M.Now()
	local held = 0
	for _, expires in pairs(type(entry.claims) == "table" and entry.claims or {}) do
		if type(expires) == "number" and expires > now then held += 1 end
	end
	return math.max(0, (tonumber(entry.free) or 0) - held)
end

-- Lobby: a server that has just been reserved for this format, with a house held for the first party
function M.Register(format, serverId, code, houses, hostUserId)
	local now = M.Now()
	local entry = {code = code, format = format, houses = houses, free = houses, players = 0, claims = {}, t = now}
	if hostUserId then entry.claims[tostring(hostUserId)] = now + M.Ttl.Claim end
	local ok = try("Set", M.Maps.Servers .. format, serverId, entry, M.Ttl.Server)
	return ok and entry or nil
end

-- Lobby: servers of the format that have a house to give, fullest first, so that parties fill servers up
function M.FindOpen(format)
	local ok, list = try("List", M.Maps.Servers .. format, 100)
	local out, now = {}, M.Now()
	for _, item in ipairs(ok and list or {}) do
		local open = type(item.value) == "table" and M.OpenHouses(item.value, now) or 0
		if open >= 1 then table.insert(out, {id = item.key, open = open, entry = item.value}) end
	end
	table.sort(out, function(a, b)
		if a.open ~= b.open then return a.open < b.open end
		return a.id < b.id
	end)
	return out
end

-- Lobby: hold one house of the server for a party. One atomic update, so two lobby servers cannot get the same
-- house. Returns the server entry, or nil when no house is left
function M.Claim(format, serverId, hostUserId)
	local now, key = M.Now(), tostring(hostUserId)
	local ok, entry = try("Update", M.Maps.Servers .. format, serverId, function(entry)
		if type(entry) ~= "table" then return nil end
		prune(entry, now)
		if not entry.claims[key] and M.OpenHouses(entry, now) < 1 then return nil end
		entry.claims[key] = now + M.Ttl.Claim
		return entry
	end, M.Ttl.Server)
	return ok and entry or nil
end

-- Lobby: the party did not leave after all, its house is free again
function M.Release(format, serverId, hostUserId)
	local key = tostring(hostUserId)
	return (try("Update", M.Maps.Servers .. format, serverId, function(entry)
		if type(entry) ~= "table" or type(entry.claims) ~= "table" or not entry.claims[key] then return nil end
		entry.claims[key] = nil
		return entry
	end, M.Ttl.Server))
end

-- Game server: report the houses that are free now. arrived: hosts whose party is on the server, their claims end
function M.Heartbeat(format, serverId, code, houses, free, players, arrived)
	local now = M.Now()
	local ok, entry = try("Update", M.Maps.Servers .. format, serverId, function(entry)
		entry = prune(type(entry) == "table" and entry or {}, now)
		entry.code, entry.format, entry.houses, entry.free, entry.players, entry.t = code, format, houses, free, players, now
		for _, host in ipairs(arrived or {}) do entry.claims[tostring(host)] = nil end
		return entry
	end, M.Ttl.Server)
	return ok and entry or nil
end

function M.Unregister(format, serverId)
	return (try("Remove", M.Maps.Servers .. format, serverId))
end

-- Lobby: who this player travels with. On arrival host and format decide the team and the house
function M.PutTicket(userId, ticket)
	ticket.t = M.Now()
	return (try("Set", M.Maps.Tickets, "u_" .. tostring(userId), ticket, M.Ttl.Ticket))
end

-- Game server: the ticket of a player who has just arrived. It is valid for this server only and is used once
function M.TakeTicket(userId, serverId)
	local key = "u_" .. tostring(userId)
	local ok, ticket = try("Get", M.Maps.Tickets, key)
	if not ok then return nil, "store" end
	if type(ticket) ~= "table" then return nil, "none" end
	if ticket.server ~= serverId then return nil, "other_server" end
	try("Remove", M.Maps.Tickets, key)
	return ticket
end

-- Game server: the team of this member is still playing here, so the lobby can send the member back to it
function M.PutSession(userId, session)
	session.t = M.Now()
	return (try("Set", M.Maps.Sessions, "u_" .. tostring(userId), session, M.Ttl.Session))
end

function M.GetSession(userId)
	local ok, session = try("Get", M.Maps.Sessions, "u_" .. tostring(userId))
	return ok and type(session) == "table" and session or nil
end

function M.DropSession(userId)
	return (try("Remove", M.Maps.Sessions, "u_" .. tostring(userId)))
end

return M
