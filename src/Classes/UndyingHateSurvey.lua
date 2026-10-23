-- Path of Building
--
-- Class: Undying Hate Survey
-- Logs the hidden value the game rolls for a timeless jewel (Undying Hate or Heroic Tragedy) in each jewel socket,
-- read from character fetches, so a player can walk one jewel around the tree (and Divine it between rounds) to
-- record what each socket gets. "souls" is the number on the jewel throughout: souls, or deeds for Heroic Tragedy.
--
local ipairs = ipairs
local pairs = pairs
local t_insert = table.insert
local t_concat = table.concat
local s_format = string.format
local m_floor = math.floor
local dkjson = require "dkjson"

local UndyingHate = LoadModule("Modules/UndyingHate")

-- The two jewels' conqueror names differ, so the log tells them apart without a jewel column
local HEADER = "time,character,souls,conqueror,socket,clock,hidden"

---@class UndyingHateSurvey
local UndyingHateSurveyClass = newClass("UndyingHateSurvey")

function UndyingHateSurveyClass:UndyingHateSurvey(tree, logPath)
	self.tree = tree
	self.logPath = logPath
	for index, radius in ipairs(data.jewelRadius) do
		if radius.label == "Very Large" then
			self.radiusIndex = index
			break
		end
	end

	-- The jewel sockets the jewels can sit in, clockwise from 12 o'clock
	self.sockets = { }
	self.socketById = { }
	for _, id in ipairs(tree.jewelSlots) do
		local node = tree.nodes[id]
		if node and node.name == "Jewel Socket" and node.nodesInRadius then
			local clock = m_floor((math.deg(math.atan2(node.x, -node.y)) % 360) / 30 + 0.5) % 12
			local socket = { id = id, clock = clock == 0 and 12 or clock }
			t_insert(self.sockets, socket)
			self.socketById[id] = socket
		end
	end
	table.sort(self.sockets, function(a, b) return a.clock % 12 < b.clock % 12 end)
	for index, socket in ipairs(self.sockets) do
		socket.index = index
	end

	self.rows = { }
	self.logged = { } -- [jewel name][souls][socket id] = hidden value
	self:Load()
	return self
end

function UndyingHateSurveyClass:Load()
	for _, row in ipairs(UndyingHate.readSurveyLog(self.logPath)) do
		self:Remember(row)
	end
end

function UndyingHateSurveyClass:Remember(row)
	t_insert(self.rows, row)
	local bySouls = self.logged[row.jewel] or { }
	self.logged[row.jewel] = bySouls
	bySouls[row.souls] = bySouls[row.souls] or { }
	bySouls[row.souls][row.socket] = row.hidden
end

---Hidden values logged for one jewel and number, by socket id
function UndyingHateSurveyClass:LoggedFor(jewel, souls)
	return self.logged[jewel] and self.logged[jewel][souls] or { }
end

function UndyingHateSurveyClass:Append(row)
	local file, errMsg = io.open(self.logPath, "a")
	if not file then
		return errMsg or "can't open the log"
	end
	if file:seek("end") == 0 then
		file:write(HEADER, "\n")
	end
	file:write(s_format("%s,%s,%d,%s,%d,%d,%d\n", row.time, row.character, row.souls, row.conqueror, row.socket, row.clock, row.hidden))
	file:close()
	self:Remember(row)
	-- So any such jewel picks it up in this socket without a restart
	UndyingHate.addKnown(row.jewel, row.souls, row.socket, row.hidden, "survey")
end

---The Undying Hates and Heroic Tragedies socketed in a character fetched from the API:
---{ { jewel, souls, conqueror, hidden, socket }, ... }, or nil and the reason there are none
function UndyingHateSurveyClass:FindJewels(charData)
	local found, why = { }, nil
	for _, item in ipairs(charData.jewels or { }) do
		for _, mod in ipairs(item.mods and item.mods.explicit or { }) do
			local stats = mod.stats
			local jewel = stats and stats.local_unique_jewel_alternate_tree_seed
				and (UndyingHate.jewelByVersion[stats.local_unique_jewel_alternate_tree_version] or UndyingHate.jewels[item.name])
			if jewel then
				local hidden = stats.local_unique_jewel_break_timeless_jewel_calculators
				if hidden then
					local keystone = stats.local_unique_jewel_alternate_tree_keystone
					t_insert(found, {
						jewel = jewel.name,
						souls = stats.local_unique_jewel_alternate_tree_seed,
						conqueror = jewel.conquerors[keystone] or tostring(keystone),
						hidden = hidden,
						socket = item.x and self.tree.jewelSlots[item.x + 1],
					})
				else
					why = "The fetch has the "..jewel.name.." but not its hidden value."
				end
				break
			end
		end
	end
	if found[1] then
		return found
	end
	return nil, why or "No Undying Hate or Heroic Tragedy is socketed. Socket it, log out, Fetch."
end

function UndyingHateSurveyClass:IsAllocated(socketId)
	return not self.allocated or self.allocated[socketId]
end

---Next socket clockwise from the jewel's current one that this round hasn't logged yet, or nil when the round is done
function UndyingHateSurveyClass:NextSocket()
	local current = self.current
	if not current then
		return nil
	end
	local done = self:LoggedFor(current.jewel, current.souls)
	local start = self.socketById[current.socket].index
	for step = 1, #self.sockets do
		local socket = self.sockets[(start + step - 1) % #self.sockets + 1]
		if self:IsAllocated(socket.id) and not done[socket.id] then
			return socket
		end
	end
end

---First allocated socket clockwise from 12 o'clock, where a new round starts
function UndyingHateSurveyClass:FirstSocket()
	for _, socket in ipairs(self.sockets) do
		if self:IsAllocated(socket.id) then
			return socket
		end
	end
end

---Hidden values logged for one jewel and number, clockwise from 12 o'clock: { { socket, hidden }, ... }
function UndyingHateSurveyClass:LoggedSockets(jewel, souls)
	local done = self:LoggedFor(jewel, souls)
	local list = { }
	for _, socket in ipairs(self.sockets) do
		if done[socket.id] then
			t_insert(list, { socket = socket.id, hidden = done[socket.id] })
		end
	end
	return list
end

---Notables the jewel gives in a socket, most copies first: { { name, count }, ... }
function UndyingHateSurveyClass:Notables(socketId, hidden, jewel)
	local conquerorType = UndyingHate.jewels[jewel or "Undying Hate"].conquerorType
	local seed = UndyingHate.seedFromHidden(hidden)
	local counts = { }
	for nodeId, node in pairs(self.tree.nodes[socketId].nodesInRadius[self.radiusIndex]) do
		if node.type == "Notable" then
			local picked = self.tree.legion.nodeById[UndyingHate.notableId(nodeId, seed, conquerorType)]
			local name = picked and picked.dn or "?"
			counts[name] = (counts[name] or 0) + 1
		end
	end
	local list = { }
	for name, count in pairs(counts) do
		t_insert(list, { name = name, count = count })
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.name < b.name
	end)
	return list
end

---Logs the timeless jewels in a fetched character and returns a status line about the one being walked round
function UndyingHateSurveyClass:Record(charData, character)
	if charData.passives and charData.passives.hashes then
		self.allocated = { }
		for _, id in ipairs(charData.passives.hashes) do
			self.allocated[id] = true
		end
	end
	local jewels, why = self:FindJewels(charData)
	if not jewels then
		return colorCodes.WARNING..why
	end

	-- Every placement in the fetch is worth logging, even of a jewel that just sits in the build
	local results = { }
	for _, jewel in ipairs(jewels) do
		local socket = jewel.socket and self.socketById[jewel.socket]
		if socket then
			jewel.clock = socket.clock
			local result = { jewel = jewel, known = self:LoggedFor(jewel.jewel, jewel.souls)[jewel.socket] }
			if result.known ~= jewel.hidden then
				result.new = true
				result.err = self:Append({ time = os.date("!%Y-%m-%dT%H:%M:%SZ"), character = character or "", souls = jewel.souls,
					conqueror = jewel.conqueror, socket = jewel.socket, clock = socket.clock, hidden = jewel.hidden, jewel = jewel.jewel })
			end
			t_insert(results, result)
		end
	end
	if not results[1] then
		return colorCodes.WARNING.."The jewel is in socket "..tostring(jewels[1].socket)..", not one of the 12 jewel sockets."
	end

	-- Follow the jewel that's new here, else the one this round was following, else the first
	local previous = self.current
	local follow
	for _, result in ipairs(results) do
		if result.new then
			follow = follow or result
		end
	end
	for _, result in ipairs(results) do
		if not follow and previous and result.jewel.jewel == previous.jewel then
			follow = result
		end
	end
	follow = follow or results[1]
	local others = 0
	for _, result in ipairs(results) do
		if result.new and result ~= follow then
			others = others + 1
		end
	end
	local jewel = follow.jewel
	self.current = jewel
	local where = s_format("%d %s at %d o'clock", jewel.souls, UndyingHate.jewels[jewel.jewel].number, jewel.clock)
	if follow.err then
		return colorCodes.NEGATIVE.."Couldn't write the log: "..follow.err
	end
	if not follow.new then
		if previous and previous.jewel == jewel.jewel and previous.souls == jewel.souls and previous.socket == jewel.socket then
			-- The API only sees a move once the character logs out
			return colorCodes.WARNING..s_format("Still at %d o'clock. Moved it? Log the character out, then Fetch.", jewel.clock)
		end
		return "^7"..where.." is already logged (hidden "..jewel.hidden..")."
	end
	local also = others > 0 and s_format(" Also logged %d other jewel%s.", others, others > 1 and "s" or "") or ""
	if follow.known then
		-- Every placement seen so far fits value = f(souls, socket); a mismatch is worth knowing about
		return colorCodes.NEGATIVE..where..": hidden "..jewel.hidden..", but the log has "..follow.known..". Logged both."
	end
	return colorCodes.POSITIVE.."Logged "..where..": hidden "..jewel.hidden.."."..also
end

---Allocated sockets this round has logged, and how many are allocated
function UndyingHateSurveyClass:RoundProgress()
	local done = self.current and self:LoggedFor(self.current.jewel, self.current.souls) or { }
	local logged, total = 0, 0
	for _, socket in ipairs(self.sockets) do
		if self:IsAllocated(socket.id) then
			total = total + 1
			if done[socket.id] then
				logged = logged + 1
			end
		end
	end
	return logged, total
end

---Clock positions colored by state: logged this round, next, not allocated, still to do
function UndyingHateSurveyClass:RoundLine()
	local done = self.current and self:LoggedFor(self.current.jewel, self.current.souls) or { }
	local nextSocket = self:NextSocket()
	local parts = { }
	for _, socket in ipairs(self.sockets) do
		local color = "^7"
		if not self:IsAllocated(socket.id) then
			color = "^x606060"
		elseif done[socket.id] then
			color = colorCodes.POSITIVE
		elseif socket == nextSocket then
			color = colorCodes.WARNING
		end
		t_insert(parts, color..socket.clock)
	end
	return t_concat(parts, "  ")
end

---How many jewel numbers (souls or deeds) the log has
function UndyingHateSurveyClass:SoulsCount()
	local count = 0
	for _, bySouls in pairs(self.logged) do
		for _ in pairs(bySouls) do
			count = count + 1
		end
	end
	return count
end

---The log as JSON for the Undying Hate Solver page (no character names)
function UndyingHateSurveyClass:ExportJson()
	local rows = { }
	for _, row in ipairs(self.rows) do
		t_insert(rows, { jewel = row.jewel, souls = row.souls, conqueror = row.conqueror, socket = row.socket, hidden = row.hidden, time = row.time })
	end
	return dkjson.encode({ format = "undying-hate-survey/1", rows = rows })
end
