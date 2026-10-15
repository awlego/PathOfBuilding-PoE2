describe("TestRecoup", function()
	before_each(function()
		newBuild()
	end)

	local function run(mods)
		build.configTab.input.customMods = mods
		build.configTab:BuildModList()
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end

	it("shortens recoup with increased speed of Recoup Effects", function()
		local base = run("+1000 to Armour\n20% of Damage taken Recouped as Life")
		assert.is_true(base.LifeRecoupRecoveryMax > 0)
		local faster = run("+1000 to Armour\n20% of Damage taken Recouped as Life\n100% increased speed of Recoup Effects")
		assert.are.near(base.LifeRecoupRecoveryMax * 2, faster.LifeRecoupRecoveryMax, base.LifeRecoupRecoveryMax * 0.01)
		assert.is_true(faster.LifeRecoupRecoveryAvg > base.LifeRecoupRecoveryAvg)
	end)

	it("recoups Physical Damage prevented as Life", function()
		local base = run("+3000 to Armour\n50% of Physical Damage prevented Recouped as Life")
		assert.are.equals(50, base.PhysicalDamageMitigatedLifeRecoup)
		assert.is_true(base.LifeRecoupRecoveryMax > 0)
		local faster = run("+3000 to Armour\n50% of Physical Damage prevented Recouped as Life\n25% increased speed of Recoup Effects")
		assert.are.near(base.LifeRecoupRecoveryMax * 1.25, faster.LifeRecoupRecoveryMax, base.LifeRecoupRecoveryMax * 0.01)
	end)

	it("keeps per damage type recoup", function()
		local output = run("+1000 to Armour\n20% of Physical Damage taken Recouped as Life")
		assert.are.equals(20, output.PhysicalLifeRecoup)
		assert.is_true(output.LifeRecoupRecoveryMax > 0)
	end)
end)
