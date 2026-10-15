describe("TestAscendancyNotables", function()
	before_each(function()
		newBuild()
	end)

	local function moreDamage()
		build.configTab:BuildModList()
		runCallback("OnFrame")
		return build.calcsTab.mainEnv.player.modDB:More(nil, "Damage")
	end

	it("No Mercy scales with the enemy's missing Concentration", function()
		build.configTab.input.customMods = "Deal up to 40% more Damage to Enemies based on their missing Concentration"
		-- Defaults to 50% Concentration missing
		assert.are.near(1.2, moreDamage(), 1e-9)
		build.configTab.input.enemyConcentration = 100
		assert.are.near(1.4, moreDamage(), 1e-9)
		build.configTab.input.enemyConcentration = 150
		assert.are.near(1.4, moreDamage(), 1e-9)
		build.configTab.input.enemyConcentration = 0
		assert.are.near(1, moreDamage(), 1e-9)
	end)

	it("Corrupted Lifeforce applies against non-Unique enemies", function()
		build.configTab.input.customMods = "15% more Damage against Enemies affected by Blood Boils"
		build.configTab.input.enemyIsBoss = "None"
		assert.are.near(1.15, moreDamage(), 1e-9)
		build.configTab.input.enemyIsBoss = "Boss"
		assert.are.near(1, moreDamage(), 1e-9)
	end)
end)
