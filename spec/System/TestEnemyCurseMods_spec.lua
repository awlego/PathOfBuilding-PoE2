describe("TestEnemyCurseMods", function()
	before_each(function()
		newBuild()
	end)

	local function enemySum(modType, name)
		return build.calcsTab.mainEnv.enemyDB:Sum(modType, nil, name)
	end

	it("applies Enemies you Curse have mods to cursed enemies", function()
		build.configTab.input.customMods = "Enemies you Curse have -6% to Chaos Resistance"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local uncursed = enemySum("BASE", "ChaosResist")
		build.configTab.input.conditionEnemyCursed = true
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equals(-6, enemySum("BASE", "ChaosResist") - uncursed)
	end)

	it("applies them when a curse skill curses the enemy", function()
		build.skillsTab:PasteSocketGroup("Temporal Chains 20/0  1")
		build.skillsTab:PasteSocketGroup("Essence Drain 20/0  1")
		build.configTab.input.customMods = "Enemies you Curse have -6% to Chaos Resistance"
		build.configTab:BuildModList()
		build.buildFlag = true
		runCallback("OnFrame")
		assert.is_true(build.calcsTab.mainEnv.enemyDB:GetCondition("Cursed"))
		assert.are.equals(-6, enemySum("BASE", "ChaosResist"))
	end)

	it("keeps Electrocute and Mark mods working", function()
		build.configTab.input.customMods = "Enemies you Electrocute have 20% increased Damage taken\nEnemies you Mark have 10% reduced Accuracy Rating"
		build.configTab.input.conditionEnemyElectrocuted = true
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equals(20, enemySum("INC", "DamageTaken"))
		build.calcsTab.mainEnv.enemyDB.conditions["Marked"] = true
		assert.are.equals(-10, enemySum("INC", "Accuracy"))
	end)
end)
