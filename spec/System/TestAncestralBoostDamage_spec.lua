describe("TestAncestralBoostDamage", function()
	before_each(function()
		newBuild()
	end)

	local function slamOutput(gems)
		newBuild()
		build.itemsTab:CreateDisplayItemFromRaw("New Item\nPlated Mace")
		build.itemsTab:AddDisplayItem()
		build.skillsTab:PasteSocketGroup(gems)
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end

	it("applies Fist of War's averaged Ancestral Boost to attack damage", function()
		local base = slamOutput("Rolling Slam 20/0  1")
		local boosted = slamOutput("Rolling Slam 20/0  1\nFist of War I 1/0  1")
		assert.is_true(boosted.AvgFistOfWarDamageEffect > 1)
		-- The averaged boost multiplies the slam's damage on top of the support's own effects
		assert.is_true(boosted.TotalDPS / base.TotalDPS >= boosted.AvgFistOfWarDamageEffect)
	end)
end)
