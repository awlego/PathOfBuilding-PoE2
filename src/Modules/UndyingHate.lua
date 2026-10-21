-- Path of Building
--
-- Module: Undying Hate
-- Picks the Abyss notable that replaces a notable conquered by Undying Hate.
--
-- The game seeds the pick with the jewel's hidden per-socket value (item stat
-- local_unique_jewel_break_timeless_jewel_calculators), not with the souls number on the item, so it has to
-- be typed into the item as a "Hidden Seed: <value>" line. The RNG is GGG's TinyMT32 variant feeding MSVC's
-- uniform_int_distribution, as in TimelessEmulator / Vilsol's timeless-jewels (GPL-3.0); constants and pool
-- order were re-verified against the PoE2 0.5 client and in-game recordings.
--
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
M.notablePool = {
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

-- 1-based index into M.notablePool of the notable that replaces tree notable `graphId` for RNG seed `seed`
local function pickNotable(graphId, seed)
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
	below(101) -- Generate(0, 100) notable replacement roll, always drawn and always passes for Abyss
	local picked, total = 1, 0
	for i, entry in ipairs(M.notablePool) do
		total = total + entry.weight
		if below(total) < entry.weight then
			picked = i
		end
	end
	return picked
end

-- BuildAllDependsAndPaths runs on every allocation change, so the picks are memoised
local pickCache = { }
function M.notableIndex(graphId, seed)
	local key = graphId * 65536 + seed
	local index = pickCache[key]
	if not index then
		index = pickNotable(graphId, seed)
		pickCache[key] = index
	end
	return index
end

-- LegionPassives id ("abyss_notable_N") of the notable that replaces tree notable `graphId` for RNG seed `seed`
function M.notableId(graphId, seed)
	return M.notablePool[M.notableIndex(graphId, seed)].id
end

return M
