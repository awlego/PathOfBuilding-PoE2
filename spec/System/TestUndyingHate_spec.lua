describe("UndyingHate", function()
	local UndyingHate = LoadModule("Modules/UndyingHate")

	-- Notables hovered in game, read from recordings (poe2-timeless/data/observed), with each placement's hidden seed
	local recordings = {
		{
			souls = 15473, socket = 46882, seed = "21603",
			notables = {
				[5191] = "Ravenous Mind",
				[30392] = "Confined Exaltation",
				[45244] = "Ravenous Mind",
				[16816] = "Worthy Tithes",
				[8791] = "Ravenous Mind",
				[32799] = "Abyssal Conduit",
				[14343] = "Mystic Brew",
				[29899] = "Ancient Bastion",
				[23244] = "Disciple of Darkness",
				[23736] = "Ravenous Mind",
				[53566] = "Creature of Death",
				[21349] = "Derogatory Gaze",
				[4238] = "I Have Darkvision",
				[14383] = "Resilient Wards",
				[33099] = "Ravenous Mind",
				[59303] = "Unfiltered Brutality",
				[60273] = "Derogatory Gaze",
				[65256] = "Resilient Wards",
				[45329] = "Ambivalent Command",
				[37244] = "Worthy Tithes",
				[36808] = "Ravenous Mind",
			},
		},
		{
			-- the same jewel moved to another socket: the hidden value changes with the socket
			souls = 15473, socket = 60735, seed = "-20616",
			notables = {
				[51606] = "Quickened Corpses",
				[35809] = "Unrestrained Intellect",
				[56776] = "Boneshedder",
				[17854] = "Ravenous Mind",
				[61741] = "Disciple of Darkness",
				[63759] = "Creature of Magic",
				[32655] = "Quickened Corpses",
				[4534] = "Derogatory Gaze",
				[65265] = "Arcane Ascension",
				[1448] = "Unrestrained Intellect",
				[8904] = "Unrestrained Intellect",
				[34908] = "Creature of Death",
				[5802] = "Unreal Potential",
				[62185] = "Hollow Bones",
				[31433] = "Mystic Brew",
				[9968] = "Unreal Potential",
				[7163] = "Creature of Magic",
			},
		},
		{
			souls = 21072, socket = 7960, seed = "2818",
			notables = {
				[8957] = "Expedited Horrors",
				[38965] = "Expedited Horrors",
				[24764] = "Abyssal Conduit",
				[58215] = "Boneshedder",
				[9896] = "Domineering Commands",
				[58183] = "Ravenous Mind",
				[5284] = "Boneshedder",
				[62210] = "Quickened Corpses",
				[33852] = "Abyssal Conduit",
				[14265] = "Boneshedder",
				[27626] = "Mystic Brew",
				[38535] = "Unreal Potential",
				[31925] = "Unrestrained Intellect",
				[58198] = "Deformed Steel",
				[47420] = "Mystic Brew",
				[44005] = "Abyssal Conduit",
				[10295] = "Deformed Steel",
				[2999] = "Confined Exaltation",
				[48925] = "Mystic Brew",
			},
		},
	}

	local function undyingHate(souls, conqueror, extraLines)
		local lines = { "Rarity: UNIQUE", "Undying Hate", "Timeless Jewel", "Radius: Very Large", "Limited to: 1 Historic",
			"Glorifying the defilement of "..souls.." souls in tribute to "..conqueror,
			"Passives in radius are Conquered by the Abyssals", "Historic" }
		for _, line in ipairs(extraLines or { }) do
			table.insert(lines, line)
		end
		local item = new("Item"):Item(table.concat(lines, "\n"))
		item:BuildAndParseRaw()
		return item
	end

	local function socketJewel(socketId, item)
		build.spec:BuildAllDependsAndPaths()
		build.spec:AllocNode(build.spec.nodes[socketId])
		build.itemsTab:AddItem(item, true)
		build.itemsTab.sockets[socketId]:SetSelItemId(item.id)
		build.spec:BuildAllDependsAndPaths()
	end

	before_each(function()
		newBuild()
	end)

	teardown(function()
		-- newBuild() takes care of resetting everything in setup()
	end)

	it("matches the game's RNG", function()
		-- { graph id, seed, 0-based pool index }, from the reference engine's test vectors
		local vectors = {
			{ 60878, 36834, 22 }, { 38537, 15176, 14 }, { 43633, 59271, 17 }, { 58183, 32282, 10 },
			{ 36623, 27103, 5 }, { 50253, 61745, 14 }, { 52669, 30005, 8 }, { 14343, 47766, 20 },
			{ 4238, 28590, 5 }, { 20251, 36960, 6 }, { 18496, 32602, 16 }, { 56112, 34158, 19 },
			{ 58215, 28586, 21 }, { 1104, 45443, 3 }, { 32799, 31144, 9 }, { 52199, 41056, 10 },
			{ 7847, 47557, 2 }, { 51606, 22040, 6 }, { 7395, 11143, 15 }, { 31433, 6077, 26 },
			{ 52191, 39227, 27 }, { 20511, 13167, 16 }, { 22967, 23464, 9 }, { 18157, 51295, 10 },
			{ 45632, 30247, 11 }, { 17254, 41579, 26 }, { 64119, 9709, 0 }, { 28963, 52243, 17 },
			{ 31955, 38938, 0 }, { 33099, 2915, 12 }, { 36808, 30787, 5 }, { 35809, 59036, 2 },
			{ 33216, 30962, 3 }, { 65256, 25051, 17 }, { 51871, 1838, 8 }, { 51394, 60697, 5 },
			{ 43944, 14740, 1 }, { 38535, 38962, 18 }, { 22967, 27961, 17 }, { 64119, 35868, 20 },
			{ 30748, 7913, 20 }, { 14258, 53613, 22 }, { 53921, 10613, 21 }, { 8957, 40988, 28 },
			{ 54998, 16759, 20 }, { 38342, 44208, 4 }, { 7341, 6168, 17 }, { 3188, 10328, 19 },
			{ 28963, 59151, 17 }, { 2335, 39613, 7 }, { 8791, 53251, 26 }, { 33542, 23363, 2 },
			{ 62210, 50000, 27 }, { 30748, 4953, 13 }, { 51871, 46998, 5 }, { 59208, 8728, 0 },
			{ 52392, 42183, 10 }, { 38628, 31444, 26 }, { 28542, 41406, 21 }, { 33542, 17203, 13 },
			{ 17854, 6882, 27 }, { 32721, 50156, 25 }, { 25362, 30214, 4 }, { 16816, 8021, 19 },
			{ 934, 0, 11 }, { 934, 255, 17 }, { 934, 32767, 10 }, { 934, 65535, 22 },
			{ 33216, 1, 3 }, { 33216, 4096, 0 }, { 33216, 32768, 18 }, { 33216, 44920, 7 },
		}
		for _, v in ipairs(vectors) do
			assert.are.equals(v[3] + 1, UndyingHate.notableIndex(v[1], v[2]))
		end
		assert.are.equals(29, #UndyingHate.abyssPool)
		for _, entry in ipairs(UndyingHate.abyssPool) do
			assert.is_not_nil(build.spec.tree.legion.nodeById[entry.id])
		end
		assert.are.equals(44920, UndyingHate.seedFromHidden(-20616))
		assert.are.equals(21603, UndyingHate.seedFromHidden(21603))
	end)

	it("parses the Hidden Seed line", function()
		local mods = modLib.parseMod("Hidden Seed: -20616")
		assert.are.same({ key = "hiddenSeed", value = { seed = 44920 } }, mods[1].value)
		mods = modLib.parseMod("Hidden Seed: 2818 @7960")
		assert.are.same({ key = "hiddenSeed", value = { seed = 2818, socket = 7960 } }, mods[1].value)
		assert.is_nil(modLib.parseMod("Hidden Seed: 65536"))
		assert.is_nil(modLib.parseMod("Hidden Seed: -32769"))

		-- 1-12 is a clock position (jewel socket ids are all far higher), with or without "o'clock"
		mods = modLib.parseMod("Hidden Seed: -20616 @4")
		assert.are.same({ key = "hiddenSeed", value = { seed = 44920, clock = 4 } }, mods[1].value)
		mods = modLib.parseMod("Hidden Seed: 2818 @12")
		assert.are.same({ key = "hiddenSeed", value = { seed = 2818, clock = 12 } }, mods[1].value)
		mods = modLib.parseMod("Hidden Seed: 2818 @1 o'clock")
		assert.are.same({ key = "hiddenSeed", value = { seed = 2818, clock = 1 } }, mods[1].value)
		assert.is_nil(modLib.parseMod("Hidden Seed: 2818 @13 o'clock"))
		assert.is_nil(modLib.parseMod("Hidden Seed: 2818 @7960 o'clock"))
		assert.is_nil(modLib.parseMod("Hidden Seed: 65536 @3"))

		local item = undyingHate(15473, "Kurgal", { "Hidden Seed: 21603 @46882", "Hidden Seed: -20616 @60735", "Hidden Seed: 7" })
		assert.are.same({ [46882] = 21603, [60735] = 44920, any = 7 }, item.jewelData.conqueredBy.hiddenSeeds)
		assert.are.equals(3, item.jewelData.conqueredBy.conqueror.id)
		local reparsed = new("Item"):Item(item:BuildRaw())
		reparsed:BuildAndParseRaw()
		assert.are.same(item.jewelData.conqueredBy.hiddenSeeds, reparsed.jewelData.conqueredBy.hiddenSeeds)

		item = undyingHate(15473, "Kurgal", { "Hidden Seed: 21603 @5", "Hidden Seed: -20616 @4 o'clock", "Hidden Seed: 2818 @7960" })
		assert.are.same({ ["5 o'clock"] = 21603, ["4 o'clock"] = 44920, [7960] = 2818 }, item.jewelData.conqueredBy.hiddenSeeds)
		reparsed = new("Item"):Item(item:BuildRaw())
		reparsed:BuildAndParseRaw()
		assert.are.same(item.jewelData.conqueredBy.hiddenSeeds, reparsed.jewelData.conqueredBy.hiddenSeeds)
	end)

	it("knows each jewel socket's clock position", function()
		local clocks = { [61419] = 12, [21984] = 1, [61834] = 2, [32763] = 3, [60735] = 4, [46882] = 5,
			[54127] = 6, [2491] = 7, [26725] = 8, [55190] = 9, [26196] = 10, [7960] = 11 }
		for socketId, clock in pairs(clocks) do
			assert.are.equals(clock, UndyingHate.socketClock(build.spec.tree.nodes[socketId]))
		end
	end)

	for _, rec in ipairs(recordings) do
		it("reproduces the in-game notables in socket "..rec.socket, function()
			socketJewel(rec.socket, undyingHate(rec.souls, "Kurgal", { "Hidden Seed: "..rec.seed }))
			for nodeId, name in pairs(rec.notables) do
				assert.are.equals(name, build.spec.nodes[nodeId].dn)
			end
		end)
	end

	it("uses the seed given for the jewel's socket", function()
		local lines = { "Hidden Seed: 21603 @46882", "Hidden Seed: -20616 @60735" }
		socketJewel(60735, undyingHate(15473, "Kurgal", lines))
		for nodeId, name in pairs(recordings[2].notables) do
			assert.are.equals(name, build.spec.nodes[nodeId].dn)
		end

		-- no seed for this socket: notables keep their own stats and say why
		newBuild()
		local treeName = build.spec.tree.nodes[8957].dn
		socketJewel(7960, undyingHate(15473, "Kurgal", lines))
		assert.are.equals(treeName, build.spec.nodes[8957].dn)
		assert.is_truthy(build.spec.nodes[8957].conquestNote[1]:find("46882, 60735", 1, true))

		-- removing the jewel clears the note
		build.itemsTab.sockets[7960]:SetSelItemId(0)
		build.spec:BuildAllDependsAndPaths()
		assert.is_nil(build.spec.nodes[8957].conquestNote)
		assert.is_nil(build.spec.nodes[8957].conqueredBy)
	end)

	it("uses the seed given for the jewel's clock position", function()
		-- 46882 is 5 o'clock, 60735 is 4 o'clock
		socketJewel(46882, undyingHate(15473, "Kurgal", { "Hidden Seed: 21603 @5", "Hidden Seed: -20616 @4 o'clock" }))
		for nodeId, name in pairs(recordings[1].notables) do
			assert.are.equals(name, build.spec.nodes[nodeId].dn)
		end
		newBuild()
		socketJewel(60735, undyingHate(15473, "Kurgal", { "Hidden Seed: 21603 @5", "Hidden Seed: -20616 @4 o'clock" }))
		for nodeId, name in pairs(recordings[2].notables) do
			assert.are.equals(name, build.spec.nodes[nodeId].dn)
		end

		-- a seed for the socket's node id comes before one for its clock position, which comes before a general one
		newBuild()
		socketJewel(46882, undyingHate(15473, "Kurgal", { "Hidden Seed: 7", "Hidden Seed: 2818 @5", "Hidden Seed: 21603 @46882" }))
		for nodeId, name in pairs(recordings[1].notables) do
			assert.are.equals(name, build.spec.nodes[nodeId].dn)
		end
		newBuild()
		socketJewel(60735, undyingHate(15473, "Kurgal", { "Hidden Seed: 7", "Hidden Seed: -20616 @4" }))
		for nodeId, name in pairs(recordings[2].notables) do
			assert.are.equals(name, build.spec.nodes[nodeId].dn)
		end

		-- no seed for this socket (11 o'clock): the note lists where there are seeds and asks for one here by clock position
		newBuild()
		local treeName = build.spec.tree.nodes[8957].dn
		socketJewel(7960, undyingHate(15473, "Kurgal", { "Hidden Seed: 21603 @5", "Hidden Seed: -20616 @60735", "Hidden Seed: 1 @12" }))
		assert.are.equals(treeName, build.spec.nodes[8957].dn)
		local note = build.spec.nodes[8957].conquestNote
		assert.is_truthy(note[1]:find("set for socket 60735 and 5, 12 o'clock,", 1, true))
		assert.is_truthy(note[2]:find("\"Hidden Seed: <value> @11\"", 1, true))
		assert.is_truthy(note[2]:find("11 o'clock, node 7960", 1, true))
	end)

	it("reads the hidden seed from the character import", function()
		build.spec:BuildAllDependsAndPaths()
		build.spec:AllocNode(build.spec.nodes[60735])
		-- trimmed from a real GET /character/poe2/<name> response: the raw mod stats carry the hidden value
		build.importTab:ImportItem({
			id = "407a009ba0f303d6b31f4f53aafc6aedf35f5fa5172ba8330f06f21743bc735a",
			name = "Undying Hate",
			typeLine = "Timeless Jewel",
			baseType = "Timeless Jewel",
			frameType = 3,
			ilvl = 83,
			properties = {
				{ name = "Limited to", values = { { "1 Historic", 0 } } },
				{ name = "Radius", values = { { "Very Large", 0 } } },
			},
			explicitMods = {
				{ description = "Glorifying the defilement of 15473 souls in tribute to Kurgal\nPassives in radius are Conquered by the Abyssals\n[UnstableDesecration|Desecration makes this item unstable]" },
				{ description = "[Historic]" },
			},
			mods = {
				explicit = {
					{
						id = "UniqueJewelAlternateTreeInRadiusAbyssal",
						stats = {
							local_unique_jewel_alternate_tree_version = 7,
							local_unique_jewel_alternate_tree_seed = 15473,
							local_unique_jewel_alternate_tree_keystone = 3,
							local_jewel_effect_base_radius = 1500,
							local_is_alternate_tree_jewel = 1,
							local_unique_jewel_alternate_tree_internal_revision = 1,
							local_unique_jewel_break_timeless_jewel_calculators = -20616,
						},
					},
				},
			},
			inventoryId = "PassiveJewels",
			x = 4,
			y = 0,
		})
		build.spec:BuildAllDependsAndPaths()

		local item = build.itemsTab.items[build.itemsTab.sockets[60735].selItemId]
		assert.are.equals("Hidden Seed: -20616 @60735", item.explicitModLines[#item.explicitModLines].line)
		assert.are.same({ [60735] = 44920 }, item.jewelData.conqueredBy.hiddenSeeds)
		for nodeId, name in pairs(recordings[2].notables) do
			assert.are.equals(name, build.spec.nodes[nodeId].dn)
		end
	end)

	it("keeps notables without a seed and still converts the rest", function()
		local treeName = build.spec.tree.nodes[35809].dn
		socketJewel(26725, undyingHate(15473, "Kurgal"))
		-- keystone, "+8 to Strength" small (not an attribute passive in game), "+5 to any Attribute" passive
		assert.are.equals("Sacrifice of Mind", build.spec.nodes[44017].dn)
		assert.are.equals("Tribute", build.spec.nodes[60620].dn)
		assert.are.same({ "+5 to Tribute" }, build.spec.nodes[60620].sd)
		assert.are.equals("+3 to Tribute", build.spec.nodes[4527].sd[#build.spec.nodes[4527].sd])
		assert.are_not.equals("Tribute", build.spec.nodes[4527].dn)

		newBuild()
		socketJewel(60735, undyingHate(15473, "Kurgal"))
		assert.are.equals(treeName, build.spec.nodes[35809].dn)
		assert.is_not_nil(build.spec.nodes[35809].conquestNote)
	end)

	it("picks Kalguuran notables for Heroic Tragedy", function()
		assert.are.equals(37, #UndyingHate.kalguurPool)
		for _, entry in ipairs(UndyingHate.kalguurPool) do
			assert.is_not_nil(build.spec.tree.legion.nodeById[entry.id])
		end

		local item = new("Item"):Item(table.concat({ "Rarity: UNIQUE", "Heroic Tragedy", "Timeless Jewel", "Radius: Very Large",
			"Limited to: 1 Historic", "Remembrancing 5000 songworthy deeds by the line of Medved",
			"Passives in radius are Conquered by the Kalguur", "Historic", "Hidden Seed: 7", "Hidden Seed: -20616 @4" }, "\n"))
		item:BuildAndParseRaw()
		socketJewel(60735, item) -- 4 o'clock
		for nodeId in pairs(recordings[2].notables) do
			local id = UndyingHate.notableId(nodeId, 44920, "kalguur")
			assert.is_truthy(id:match("^kalguur_notable%d+$"))
			assert.are.equals(build.spec.tree.legion.nodeById[id].dn, build.spec.nodes[nodeId].dn)
		end

		-- the survey tells the jewels apart by tree version
		local found = build.importTab.survey:FindJewels({ jewels = { { name = "Heroic Tragedy", x = 4, mods = { explicit = { { stats = {
			local_unique_jewel_alternate_tree_version = 6,
			local_unique_jewel_alternate_tree_seed = 5000,
			local_unique_jewel_alternate_tree_keystone = 2,
			local_unique_jewel_break_timeless_jewel_calculators = -20616,
		} } } } } } })
		assert.are.same({ jewel = "Heroic Tragedy", souls = 5000, conqueror = "Medved", hidden = -20616, socket = 60735 }, found[1])
	end)

	it("applies Tribute before attributes and counts increased Tribute", function()
		build.configTab.input.customMods = "+50 to Tribute\n20% increased Tribute"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local int = build.calcsTab.mainOutput.Int
		assert.are.equals(60, build.calcsTab.mainOutput.Tribute)

		build.configTab.input.customMods = "+50 to Tribute\n20% increased Tribute\n+2 to Intelligence per 25 Tribute"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equals(int + 4, build.calcsTab.mainOutput.Int)
	end)
end)
