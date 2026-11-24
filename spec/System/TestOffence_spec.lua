describe("TestOffence", function()
	before_each(function()
		newBuild()
	end)

	teardown(function()
		-- newBuild() takes care of resetting everything in setup()
	end)

	it("rounds each scaled damage conversion to a whole percent", function()
		build.skillsTab:PasteSocketGroup("Fireball 20/0  1")
		build.configTab.input.customMods = [[
		40% of Physical Damage Converted to Lightning Damage
		40% of Physical Damage Converted to Cold Damage
		40% of Physical Damage Converted to Fire Damage
		]]
		build.configTab:BuildModList()
		runCallback("OnFrame")

		local conversion = build.calcsTab.mainEnv.player.mainSkill.conversionTable.Physical
		assert.are.equals(0.33, conversion.Lightning)
		assert.are.equals(0.33, conversion.Cold)
		assert.are.equals(0.33, conversion.Fire)
		assert.is_true(math.abs(conversion.mult - 0.01) < 0.000001)
	end)

	it("keeps converted damage fractional until destination calculation", function()
		build.itemsTab:CreateDisplayItemFromRaw([[
		New Item
		Attuned Wand
		Adds 2 to 2 Physical Damage to Spells
		]])
		build.itemsTab:AddDisplayItem()
		build.skillsTab:PasteSocketGroup("Fireball 20/0  1")
		build.configTab.input.customMods = [[
		25% of Physical Damage Converted to Cold Damage
		]]
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(2, build.calcsTab.mainOutput.PhysicalMinBase)
		assert.are.equals(0.5, build.calcsTab.mainOutput.ColdSummedMinBase)
	end)

	it("applies a global conversion on top of a skill conversion to the same type independently of table order", function()
		build.skillsTab:PasteSocketGroup("Exsanguinate 20/0  1")
		build.configTab.input.customMods = [[
		20% of Exsanguinate and Reap Physical Damage Converted to Fire Damage
		75% of Damage Converted to Fire Damage
		]]
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- Skill conversion first: 20% of Physical to Fire; then 75% of the remaining 80% to Fire.
		-- The Fire part stays Fire (75% of Fire to Fire is no conversion).
		local conversion = build.calcsTab.mainEnv.player.mainSkill.conversionTable.Physical
		assert.are.equals(0.8, conversion.Fire)
		assert.is_true(math.abs(conversion.mult - 0.2) < 0.000001)
	end)

	-- Gains inherent to the skill (e.g. Twister, Eye of Winter) happen in the skill conversion step, so the
	-- damage they gain is converted by global conversion and is a source for global gains.
	local function setupSkillGain(customMods, skillGainMods)
		build.itemsTab:CreateDisplayItemFromRaw([[
		New Item
		Attuned Wand
		Adds 2 to 2 Physical Damage to Spells
		]])
		build.itemsTab:AddDisplayItem()
		build.skillsTab:PasteSocketGroup("Fireball 20/0  1")
		build.configTab.input.customMods = customMods
		build.configTab:BuildModList()
		for _, gain in ipairs(skillGainMods) do
			build.configTab.modList:NewMod(gain[1], "BASE", gain[2], "Test")
		end
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end

	local function near(expected, actual)
		assert.is_true(math.abs(expected - actual) < 0.0001, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
	end

	it("converts damage gained by the skill with global conversion", function()
		local output = setupSkillGain([[
		100% of Cold Damage Converted to Lightning Damage
		]], { { "SkillDamageGainAsCold", 50 } })

		local totalMin = output.PhysicalMinBase + output.FireMinBase
		assert.is_true(totalMin > 0)
		near(0, output.ColdSummedMinBase)
		near(0.5 * totalMin, output.LightningSummedMinBase)
	end)

	it("uses damage gained by the skill as a source for global gains", function()
		local output = setupSkillGain([[
		Gain 20% of Damage as Extra Chaos Damage
		]], { { "SkillDamageGainAsCold", 50 } })

		local totalMin = output.PhysicalMinBase + output.FireMinBase
		near(0.5 * totalMin, output.ColdSummedMinBase)
		near(0.2 * (totalMin + 0.5 * totalMin), output.ChaosSummedMinBase)
	end)

	it("sources skill gains from damage after skill conversion but before global conversion", function()
		local output = setupSkillGain([[
		100% of Physical Damage Converted to Fire Damage
		]], { { "SkillPhysicalDamageGainAsCold", 50 } })

		near(0.5 * output.PhysicalMinBase, output.ColdSummedMinBase)
		near(0, output.PhysicalSummedMinBase)
		near(output.PhysicalMinBase + output.FireMinBase, output.FireSummedMinBase)
	end)

	it("does not chain global gains within the same step", function()
		local output = setupSkillGain([[
		Gain 50% of Damage as Extra Cold Damage
		Gain 20% of Damage as Extra Chaos Damage
		]], { })

		local totalMin = output.PhysicalMinBase + output.FireMinBase
		near(0.5 * totalMin, output.ColdSummedMinBase)
		near(0.2 * totalMin, output.ChaosSummedMinBase)
	end)
end)
