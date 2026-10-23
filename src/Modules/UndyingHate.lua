-- Path of Building
--
-- Module: Undying Hate
-- Picks the notable that replaces a notable conquered by a PoE2 timeless jewel: an Abyss notable for Undying
-- Hate, a Kalguuran notable for Heroic Tragedy. Both go through the same client code.
--
-- The game seeds the pick with the jewel's hidden per-socket value (item stat
-- local_unique_jewel_break_timeless_jewel_calculators), not with the souls or deeds number on the item, so it
-- has to come from the item's "Hidden Seed: <value>" lines (character import writes them) or from the known
-- values at the end of this file. The RNG is GGG's TinyMT32 variant feeding MSVC's
-- uniform_int_distribution, as in TimelessEmulator / Vilsol's timeless-jewels (GPL-3.0); constants and pool
-- order were re-verified against the PoE2 0.5 client and in-game recordings.
--
local dkjson = require "dkjson"
local bxor = bit.bxor
local band = bit.band
local lshift = bit.lshift
local rshift = bit.rshift
local m_floor = math.floor

local TWO32 = 4294967296
local UINT_MAX = 4294967295

local M = { }

-- AlternatePassiveSkills notable rows for the abyss tree version with SpawnWeight > 0, in table order.
-- The pick is positional, so keep this order. abyss_notable_22 (Buried Animosity) has SpawnWeight 0 and is
-- skipped without a draw. No 0.5 notable is conqueror-specific, so the conqueror doesn't affect the pick.
M.abyssPool = {
	{ id = "abyss_notable_1", weight = 100 }, -- Disciple of Darkness
	{ id = "abyss_notable_2", weight = 100 }, -- Creature of Death
	{ id = "abyss_notable_3", weight = 100 }, -- Creature of Magic
	{ id = "abyss_notable_4", weight = 100 }, -- Quickened Corpses
	{ id = "abyss_notable_5", weight = 100 }, -- Ambivalent Command
	{ id = "abyss_notable_6", weight = 100 }, -- Boneshedder
	{ id = "abyss_notable_7", weight = 100 }, -- Unfiltered Brutality
	{ id = "abyss_notable_8", weight = 100 }, -- Derogatory Gaze
	{ id = "abyss_notable_9", weight = 100 }, -- Abyssal Conduit
	{ id = "abyss_notable_10", weight = 100 }, -- Expedited Horrors
	{ id = "abyss_notable_11", weight = 100 }, -- Confined Exaltation
	{ id = "abyss_notable_12", weight = 100 }, -- Arcane Ascension
	{ id = "abyss_notable_13", weight = 100 }, -- Ravenous Mind
	{ id = "abyss_notable_14", weight = 100 }, -- Gluttonous Presence
	{ id = "abyss_notable_15", weight = 100 }, -- Unrestrained Intellect
	{ id = "abyss_notable_16", weight = 100 }, -- Cruel Strength
	{ id = "abyss_notable_17", weight = 100 }, -- Opportunistic Dexterity
	{ id = "abyss_notable_18", weight = 100 }, -- Unreal Potential
	{ id = "abyss_notable_19", weight = 100 }, -- I Have Darkvision
	{ id = "abyss_notable_20", weight = 100 }, -- Domineering Commands
	{ id = "abyss_notable_21", weight = 100 }, -- Worthy Tithes
	{ id = "abyss_notable_23", weight = 100 }, -- Fast Rot
	{ id = "abyss_notable_24", weight = 100 }, -- Hollow Bones
	{ id = "abyss_notable_25", weight = 100 }, -- Ancient Bastion
	{ id = "abyss_notable_26", weight = 100 }, -- Deformed Steel
	{ id = "abyss_notable_27", weight = 100 }, -- Mystic Brew
	{ id = "abyss_notable_28", weight = 100 }, -- Resilient Wards
	{ id = "abyss_notable_29", weight = 100 }, -- Dreadful Fortitude
	{ id = "abyss_notable_30", weight = 100 }, -- Barbed Allegiance
}

-- The same for the Kalguuran tree version (Heroic Tragedy). Unlike Abyss the weights differ, and the weighted
-- walk below honours them (checked against Path of Building's PoE1 Heroic Tragedy LUT).
M.kalguurPool = {
	{ id = "kalguur_notable1", weight = 1000 }, -- Scorched Earth
	{ id = "kalguur_notable2", weight = 1000 }, -- War Tactics
	{ id = "kalguur_notable3", weight = 250 }, -- Kalguuran Forged
	{ id = "kalguur_notable4", weight = 1000 }, -- Born of Middengard
	{ id = "kalguur_notable5", weight = 500 }, -- Force of Will
	{ id = "kalguur_notable6", weight = 500 }, -- Runic Flows
	{ id = "kalguur_notable7", weight = 500 }, -- Siege Mentality
	{ id = "kalguur_notable8", weight = 500 }, -- Rune Knight
	{ id = "kalguur_notable9", weight = 500 }, -- Fiery Leadership
	{ id = "kalguur_notable10", weight = 500 }, -- Druidic Alliance
	{ id = "kalguur_notable11", weight = 500 }, -- Steel and Sorcery
	{ id = "kalguur_notable12", weight = 500 }, -- Triskelion's Light
	{ id = "kalguur_notable13", weight = 250 }, -- Stormtossed Voyager
	{ id = "kalguur_notable14", weight = 1000 }, -- Wrest Control
	{ id = "kalguur_notable15", weight = 1000 }, -- Firedancer
	{ id = "kalguur_notable16", weight = 500 }, -- Mercenary's Lot
	{ id = "kalguur_notable17", weight = 500 }, -- Vorana's Fury
	{ id = "kalguur_notable18", weight = 500 }, -- Sensible Precautions
	{ id = "kalguur_notable19", weight = 500 }, -- Aim for the Jugular
	{ id = "kalguur_notable20", weight = 500 }, -- Survival Plan
	{ id = "kalguur_notable21", weight = 500 }, -- War of Attrition
	{ id = "kalguur_notable22", weight = 500 }, -- Guerilla Warfare
	{ id = "kalguur_notable23", weight = 500 }, -- One for the Road
	{ id = "kalguur_notable24", weight = 500 }, -- Targeted Strike
	{ id = "kalguur_notable25", weight = 500 }, -- Steel Bastion
	{ id = "kalguur_notable26", weight = 500 }, -- Forceful Energies
	{ id = "kalguur_notable27", weight = 1000 }, -- Winter Forest
	{ id = "kalguur_notable28", weight = 500 }, -- Fight as One
	{ id = "kalguur_notable29", weight = 500 }, -- Summer Meadows
	{ id = "kalguur_notable30", weight = 500 }, -- Druidic Training
	{ id = "kalguur_notable31", weight = 500 }, -- Corrupted Vision
	{ id = "kalguur_notable32", weight = 500 }, -- Runic Tattoos
	{ id = "kalguur_notable33", weight = 250 }, -- Furs and Leather
	{ id = "kalguur_notable34", weight = 500 }, -- Sudden Hail
	{ id = "kalguur_notable35", weight = 1000 }, -- Natural Energies
	{ id = "kalguur_notable36", weight = 500 }, -- Oaken Form
	{ id = "kalguur_notable37", weight = 500 }, -- Spider's Lesson
}

-- The timeless jewels whose notables follow the hidden value, by name, PoB conqueror type, tree version and conqueror
M.jewels = {
	["Undying Hate"] = { name = "Undying Hate", conquerorType = "abyss", version = 7, pool = M.abyssPool, notableKind = "Abyss",
		number = "souls", conquerors = { "Amanamu", "Kulemak", "Kurgal", "Tecrod", "Ulaman" } },
	["Heroic Tragedy"] = { name = "Heroic Tragedy", conquerorType = "kalguur", version = 6, pool = M.kalguurPool, notableKind = "Kalguuran",
		number = "deeds", conquerors = { "Vorana", "Medved", "Olroth" } },
}
M.jewelByType = { }
M.jewelByVersion = { }
M.jewelByConqueror = { }
for _, jewel in pairs(M.jewels) do
	M.jewelByType[jewel.conquerorType] = jewel
	M.jewelByVersion[jewel.version] = jewel
	for _, conqueror in ipairs(jewel.conquerors) do
		M.jewelByConqueror[conqueror] = jewel
	end
end

-- (a * b) mod 2^32 for a, b in [0, 2^32): split into 16-bit halves so every partial product stays exact in a double
local function mul32(a, b)
	local al, bl = a % 65536, b % 65536
	local ah, bh = (a - al) / 65536, (b - bl) / 65536
	return ((ah * bl + al * bh) % 65536 * 65536 + al * bl) % TWO32
end

-- RNG seed (0..65535) for a hidden value as poe.ninja shows it (signed 16-bit, -32768..32767) or as a seed already
function M.seedFromHidden(hidden)
	return hidden % 65536
end

-- Clock position (1-12) of a jewel socket, from its place on the tree: 12 o'clock is straight up
function M.socketClock(node)
	local clock = m_floor((math.deg(math.atan2(node.x, -node.y)) % 360) / 30 + 0.5) % 12
	return clock == 0 and 12 or clock
end

-- 1-based index into `pool` of the notable that replaces tree notable `graphId` for RNG seed `seed`
local function pickNotable(graphId, seed, pool)
	-- Seeding: state words 1..4, seed words { graph id, seed, 12345 }, 7 "alpha" and 4 "bravo" mixing rounds.
	-- State values are kept congruent mod 2^32 and normalised with % TWO32 before any arithmetic that needs it.
	local st = { 0x40336051, 0xCFA3723C, 0x3CAC5F70, 0x3793FDFF }
	local words = { graphId, seed, 12345 }
	local idx = 1
	for i = 0, 6 do
		local i0, i1, i2, i3 = idx % 4 + 1, (idx + 1) % 4 + 1, (idx + 2) % 4 + 1, (idx + 3) % 4 + 1
		local v = bxor(st[i0], st[i1], st[i3]) % TWO32
		local r = mul32(bxor(v, rshift(v, 27)) % TWO32, 0x19660D)
		st[i1] = (st[i1] + r) % TWO32
		r = (r + (words[i + 1] or 0) + idx) % TWO32
		st[i2] = (st[i2] + r) % TWO32
		st[i0] = r
		idx = (idx + 1) % 4
	end
	for _ = 0, 3 do
		local i0, i1, i2, i3 = idx % 4 + 1, (idx + 1) % 4 + 1, (idx + 2) % 4 + 1, (idx + 3) % 4 + 1
		local v = (st[i0] + st[i1] + st[i3]) % TWO32
		local r = mul32(bxor(v, rshift(v, 27)) % TWO32, 0x5D588B65)
		st[i1] = bxor(st[i1], r) % TWO32
		r = (r - idx) % TWO32
		st[i2] = bxor(st[i2], r) % TWO32
		st[i0] = r
		idx = (idx + 1) % 4
	end
	local s0, s1, s2, s3 = st[1], st[2], st[3], st[4]

	-- The generator itself only needs bit operations, so the state is held as signed int32 here
	local function step()
		local a = bxor(s3, lshift(s3, 1))
		local b = bxor(band(s0, 0x7FFFFFFF), s1, s2)
		b = bxor(b, rshift(b, 1), a)
		s0, s1, s2, s3 = s1, s2, bxor(a, lshift(b, 10)), b
		if band(b, 1) == 1 then
			s1 = bxor(s1, 0x8F7011EE)
			s2 = bxor(s2, 0xFC78FF1F)
		end
	end
	local function uint()
		step()
		local t = (s0 % TWO32 + rshift(s2, 8)) % TWO32
		local a = bxor(s3, t)
		if t % 2 == 1 then
			a = bxor(a, 0x3793FDFF)
		end
		return a % TWO32
	end
	-- MSVC _Rng_from_urng: no draw for n <= 1, otherwise redraw from the biased tail
	local function below(n)
		if n <= 1 then
			return 0
		end
		local lim = m_floor(UINT_MAX / n)
		local exact = UINT_MAX % n == n - 1
		while true do
			local x = uint()
			if exact or m_floor(x / n) < lim then
				return x % n
			end
		end
	end

	for _ = 1, 8 do
		step()
	end
	below(101) -- Generate(0, 100) notable replacement roll, always drawn and always passes for Abyss and Kalguur
	local picked, total = 1, 0
	for i, entry in ipairs(pool) do
		total = total + entry.weight
		if below(total) < entry.weight then
			picked = i
		end
	end
	return picked
end

-- BuildAllDependsAndPaths runs on every allocation change, so the picks are memoised, per pool
local pickCaches = { }
function M.notableIndex(graphId, seed, pool)
	pool = pool or M.abyssPool
	local cache = pickCaches[pool]
	if not cache then
		cache = { }
		pickCaches[pool] = cache
	end
	local key = graphId * 65536 + seed
	local index = cache[key]
	if not index then
		index = pickNotable(graphId, seed, pool)
		cache[key] = index
	end
	return index
end

-- LegionPassives id ("abyss_notable_N", "kalguur_notableN") of the notable that replaces tree notable `graphId`
-- for RNG seed `seed`, for the jewel with PoB conqueror type `conquerorType` (default Undying Hate's "abyss")
function M.notableId(graphId, seed, conquerorType)
	local pool = M.jewelByType[conquerorType or "abyss"].pool
	return pool[M.notableIndex(graphId, seed, pool)].id
end

-- Hidden values known from outside the item, for jewels that don't carry one for their socket. They come from
-- UndyingHateKnown.json in the user folder (written by an external dataset's exporter; PoB doesn't ship one)
-- and from the survey's log. Both cover Undying Hate and Heroic Tragedy, keyed by jewel name, the number on
-- the jewel (souls or deeds, called "souls" throughout) and socket. LoadModule runs this file afresh for
-- each caller, so the store hangs off main and is read once.
M.knownFile = "UndyingHateKnown.json"
M.surveyFile = "UndyingHateSurvey.csv"
M.knownFormat = "undying-hate-known/2"
-- /1 predates Heroic Tragedy: its placements have no "jewel" and are all Undying Hates
local knownFormats = { ["undying-hate-known/1"] = true, ["undying-hate-known/2"] = true }

---Reads a survey log: { { time, character, souls, conqueror, socket, clock, hidden, jewel }, ... }. The log has
---no jewel column: the conqueror names differ between the jewels, so they tell them apart.
function M.readSurveyLog(path)
	local rows = { }
	local file = path and io.open(path, "r")
	if not file then
		return rows
	end
	for line in file:lines() do
		local time, character, souls, conqueror, socket, clock, hidden = line:match("^([^,]*),([^,]*),(%d+),([^,]*),(%d+),(%d+),(%-?%d+)")
		if time then
			local jewel = M.jewelByConqueror[conqueror] or M.jewels["Undying Hate"]
			table.insert(rows, { time = time, character = character, souls = tonumber(souls), conqueror = conqueror,
				socket = tonumber(socket), clock = tonumber(clock), hidden = tonumber(hidden), jewel = jewel.name })
		end
	end
	file:close()
	return rows
end

---Rereads the known hidden values from the user folder
function M.reloadKnown()
	local known = { byJewel = { }, placements = 0, numbers = 0 }
	main.undyingHateKnown = known
	local userPath = main.userPath or ""
	local file = io.open(userPath..M.knownFile, "r")
	if file then
		local doc = dkjson.decode(file:read("*a"))
		file:close()
		if type(doc) == "table" and knownFormats[doc.format] and type(doc.placements) == "table" then
			for _, placement in ipairs(doc.placements) do
				local jewel = M.jewels[placement.jewel or "Undying Hate"]
				local souls, socket, hidden = tonumber(placement.souls), tonumber(placement.socket), tonumber(placement.hidden)
				if jewel and souls and socket and hidden then
					M.addKnown(jewel.name, souls, socket, hidden, placement.source or M.knownFile)
				end
			end
		else
			known.error = M.knownFile.." isn't an "..M.knownFormat.." file"
		end
	end
	-- The survey's own reads of the game come last, so they win over any other source
	for _, row in ipairs(M.readSurveyLog(userPath..M.surveyFile)) do
		M.addKnown(row.jewel, row.souls, row.socket, row.hidden, "survey")
	end
	return known
end

---The known hidden values: { byJewel = { [jewel name] = { [souls] = { [socket id] = { hidden, source } } } },
---placements, numbers (distinct jewel and souls pairs), error }
function M.known()
	return main.undyingHateKnown or M.reloadKnown()
end

function M.addKnown(jewel, souls, socket, hidden, source)
	local known = M.known()
	local bySouls = known.byJewel[jewel]
	if not bySouls then
		bySouls = { }
		known.byJewel[jewel] = bySouls
	end
	local bySocket = bySouls[souls]
	if not bySocket then
		bySocket = { }
		bySouls[souls] = bySocket
		known.numbers = known.numbers + 1
	end
	if not bySocket[socket] then
		known.placements = known.placements + 1
	end
	bySocket[socket] = { hidden = hidden, source = source }
end

---Known hidden value and its source for this jewel with this many souls (or deeds) in this socket, or nil
function M.knownHidden(jewel, souls, socket)
	local bySouls = M.known().byJewel[jewel]
	local bySocket = bySouls and souls and bySouls[souls]
	local entry = bySocket and bySocket[socket]
	if entry then
		return entry.hidden, entry.source
	end
end

return M
