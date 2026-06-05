describe("TimeLostSolver", function()
	local TradeQueryGeneratorClass

	before_each(function()
		newBuild()
		-- Trigger lazy class load via getClass, then bind the class table for
		-- access to its static helpers (BuildTimeLostAffixLine etc.).
		new("TradeQueryGenerator", { itemsTab = { } })
		TradeQueryGeneratorClass = common.classes["TradeQueryGenerator"]
	end)

	-- Pass: range syntax (15-25) at mid-roll becomes 20 (ceil of 15 + 0.5*(25-15))
	-- Fail: range substitution returns the original text or wrong numeric value,
	-- which would make every Time-Lost affix score at min or zero
	it("BuildTimeLostAffixLine substitutes (min-max) ranges at mid-roll", function()
		local originalQuality = main.defaultItemAffixQuality
		main.defaultItemAffixQuality = 0.5
		local line = TradeQueryGeneratorClass.BuildTimeLostAffixLine({
			mod = { [1] = "(15-25)% increased Effect of Small Passive Skills in Radius" }
		})
		assert.are.equal("20% increased Effect of Small Passive Skills in Radius", line)
		main.defaultItemAffixQuality = originalQuality
	end)

	-- Pass: literal text (no parens) passes through unchanged
	-- Fail: the gsub mangles non-range mods (e.g. radius-upgrade prefixes), which
	-- would break the radius-sweep dimension of the solver
	it("BuildTimeLostAffixLine passes literal text through unchanged", function()
		local line = TradeQueryGeneratorClass.BuildTimeLostAffixLine({
			mod = { [1] = "Upgrades Radius to Medium" }
		})
		assert.are.equal("Upgrades Radius to Medium", line)
	end)

	-- Pass: builds an Item whose base resolves to Time-Lost Ruby with jewel radius
	-- Fail: the synthetic raw fails to parse, indicating the "Stat Tester" prelude
	-- or Radius line is wrong, which would crash the solver before scoring
	it("BuildTimeLostTestItem produces a parseable radius jewel", function()
		local item = TradeQueryGeneratorClass.BuildTimeLostTestItem("Time-Lost Ruby", "Small")
		assert.are.equal("Time-Lost Ruby", item.baseName)
		assert.are.equal("Jewel", item.type)
		assert.are.equal("Radius", item.base.subType)
		assert.is_truthy(item.jewelRadiusIndex)
		assert.is_truthy(item.affixes)
	end)

	-- Pass: a Ruby (str_radius_jewel) enumerates JewelRadiusArmour but not
	-- JewelRadiusCastSpeed (int_radius_jewel only)
	-- Fail: base-tag gating is broken and an int-only mod leaks onto a Ruby; this
	-- would produce nonsense scores for "Cast Speed on a Ruby" rows
	it("EnumerateTimeLostAffixes filters by base tag", function()
		local gen = new("TradeQueryGenerator", { itemsTab = {} })
		local item = TradeQueryGeneratorClass.BuildTimeLostTestItem("Time-Lost Ruby", "Small")
		local prefixes, suffixes, radiusUpgrades = gen:EnumerateTimeLostAffixes(item)

		local function findById(list, id)
			for _, e in ipairs(list) do
				if e.modId == id then return e end
			end
			return nil
		end

		-- str_radius_jewel + radius_jewel mods must appear
		assert.is_truthy(findById(prefixes, "JewelRadiusArmour"))
		-- int-only mods must not appear on a Ruby
		assert.is_nil(findById(suffixes, "JewelRadiusCastSpeed"))
		-- Radius-upgrade prefixes are split into the third bucket
		assert.is_truthy(findById(radiusUpgrades, "JewelRadiusMediumSize"))
		assert.is_truthy(findById(radiusUpgrades, "JewelRadiusLargeSize"))
		-- And must NOT appear as scoring prefixes
		assert.is_nil(findById(prefixes, "JewelRadiusMediumSize"))
	end)

	-- Pass: two suffix entries sharing a group collapse to the best-scoring one
	-- Fail: tier-ladder variants of the same mod are paired twice in the combo
	-- sweep, polluting results with near-duplicate rows
	it("DedupeTimeLostByGroup keeps the best entry per group", function()
		local entries = {
			{ modId = "A", group = "G", soloDiff = 5 },
			{ modId = "B", group = "G", soloDiff = 12 },
			{ modId = "C", group = "H", soloDiff = 3 },
		}
		local result = TradeQueryGeneratorClass.DedupeTimeLostByGroup(entries)
		assert.are.equal(2, #result)
		local kept = { }
		for _, e in ipairs(result) do
			kept[e.group or e.modId] = e
		end
		assert.are.equal("B", kept["G"].modId)
		assert.are.equal("C", kept["H"].modId)
	end)

	-- Pass: rebuilding the test item at a different radius label resolves to a
	-- different jewelRadiusIndex, which is what the outer radius sweep relies on
	-- Fail: jewelRadiusIndex stays pinned to Small regardless of the requested
	-- radius, meaning the Medium/Large dimension of the solver has no effect
	it("BuildTimeLostTestItem honors radius label", function()
		local small = TradeQueryGeneratorClass.BuildTimeLostTestItem("Time-Lost Sapphire", "Small")
		local medium = TradeQueryGeneratorClass.BuildTimeLostTestItem("Time-Lost Sapphire", "Medium")
		local large = TradeQueryGeneratorClass.BuildTimeLostTestItem("Time-Lost Sapphire", "Large")
		assert.is_truthy(small.jewelRadiusIndex)
		assert.is_truthy(medium.jewelRadiusIndex)
		assert.is_truthy(large.jewelRadiusIndex)
		assert.are_not.equal(small.jewelRadiusIndex, medium.jewelRadiusIndex)
		assert.are_not.equal(medium.jewelRadiusIndex, large.jewelRadiusIndex)
	end)

	-- Pass: with maxAffixes=2 the config builder enumerates both singletons and
	-- distinct-group pairs ranked by solo sum; mutually exclusive entries (same
	-- group) never pair together
	-- Fail: pairs of same-group entries leak into the configuration list, which
	-- would yield illegal "two-prefixes-in-the-same-tier-ladder" results
	it("BuildTimeLostRoleConfigs produces singletons + legal pairs", function()
		local entries = {
			{ modId = "A", group = "G1", soloDiff = 10 },
			{ modId = "B", group = "G1", soloDiff = 8 },
			{ modId = "C", group = "G2", soloDiff = 5 },
			{ modId = "D", group = "G3", soloDiff = 3 },
		}
		local configs = TradeQueryGeneratorClass.BuildTimeLostRoleConfigs(entries, 2, 25)
		-- Walk every config to confirm no pair contains two same-group entries.
		local hasSingleton, hasPair = false, false
		for _, c in ipairs(configs) do
			if #c.entries == 1 then
				hasSingleton = true
			elseif #c.entries == 2 then
				hasPair = true
				assert.are_not.equal(c.entries[1].group, c.entries[2].group)
			end
		end
		assert.is_true(hasSingleton)
		assert.is_true(hasPair)
		-- Best singleton (A: solo 10) and best legal pair (A+C: solo 15) should
		-- both appear; A+B is illegal (same group) so the next-best pair is A+C.
		assert.are.equal(15, configs[1].soloSum)
	end)

	-- Pass: with maxAffixes=1 (Medium/Large radius), only singletons appear
	-- Fail: the radius-upgrade prefix dimension fails to constrain the prefix
	-- slot count, producing "2 prefix configurations" at Medium/Large radii
	-- which would over-represent prefix value in those rows
	it("BuildTimeLostRoleConfigs with maxAffixes=1 emits only singletons", function()
		local entries = {
			{ modId = "A", group = "G1", soloDiff = 10 },
			{ modId = "B", group = "G2", soloDiff = 8 },
		}
		local configs = TradeQueryGeneratorClass.BuildTimeLostRoleConfigs(entries, 1, 25)
		assert.are.equal(2, #configs)
		for _, c in ipairs(configs) do
			assert.are.equal(1, #c.entries)
		end
	end)
end)
