describe("TestImpale", function()
	before_each(function()
		newBuild()
	end)

	local function slamWithMods(mods)
		build.itemsTab:CreateDisplayItemFromRaw("New Item\nPlated Mace")
		build.itemsTab:AddDisplayItem()
		build.skillsTab:PasteSocketGroup("Rolling Slam 20/0  1")
		build.configTab.input.customMods = mods
		build.configTab:BuildModList()
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end

	it("uses the PoE2 Impale stored damage and maximum stacks", function()
		assert.are.equals(data.gameConstants["ImpalePercentage"], data.misc.ImpaleStoredDamageBase)
		runCallback("OnFrame")
		assert.are.equals(data.gameConstants["ImpaleMaximumStacks"], build.calcsTab.mainEnv.player.modDB:Sum("BASE", nil, "ImpaleStacksMax"))
	end)

	it("deals Impale damage from chance to Impale on Hit", function()
		local output = slamWithMods("50% chance to Impale Enemies on Hit")
		assert.are.equals(50, output.ImpaleChance)
		assert.is_true((output.ImpaleDPS or 0) > 0)
	end)

	it("only Impales on Critical Hits with Critical Hits inflict Impale", function()
		local output = slamWithMods("Critical Hits inflict Impale").MainHand
		assert.are.equals(0, output.ImpaleChance)
		assert.are.equals(100, output.ImpaleChanceOnCrit)
	end)
end)
