describe("TestVerglas", function()
	before_each(function()
		newBuild()
	end)

	teardown(function()
		-- newBuild() takes care of resetting everything in setup()
	end)

	-- Sets up a build with a Frost Wall (Ice Crystal source) group and a
	-- Fireball group supported by Verglas, and makes Fireball the main skill.
	local function setupVerglasBuild()
		build.skillsTab:PasteSocketGroup("Frost Wall 20/0  1")
		build.skillsTab:PasteSocketGroup("Fireball 20/0  1\nVerglas 1/0  1")
		for i, group in ipairs(build.skillsTab.socketGroupList) do
			for _, activeSkill in ipairs(group.displaySkillList or {}) do
				if activeSkill.activeEffect.grantedEffect.name == "Fireball" then
					build.mainSocketGroup = i
					build.calcsTab.input.skill_number = i
				end
			end
		end
		build.buildFlag = true
		runCallback("OnFrame")
	end

	it("does not grant Cold when the Verglas buff is inactive", function()
		setupVerglasBuild()
		build.calcsTab:BuildOutput()
		runCallback("OnFrame")
		assert.is_nil(build.calcsTab.mainOutput.VerglasColdGain)

		local mainSkill = build.calcsTab.calcsEnv.player.mainSkill
		assert.are.equals(0, mainSkill.skillModList:Sum("BASE", mainSkill.skillCfg, "DamageGainAsCold"))
	end)

	it("grants Cold based on destroyed Ice Crystal Life when the buff is active", function()
		setupVerglasBuild()

		-- Enable the Verglas buff via the Configuration toggle
		build.configTab.input.conditionDestroyedIceCrystalRecently = true
		build.configTab:BuildModList()
		build.buildFlag = true
		runCallback("OnFrame")
		build.calcsTab:BuildOutput()
		runCallback("OnFrame")

		local output = build.calcsTab.mainOutput
		assert.is_not_nil(output.VerglasCrystalLife)
		assert.is_true(output.VerglasCrystalLife > 0)

		-- Verglas grants 1% of Damage as extra Cold per 2000 Ice Crystal Life
		local expectedGain = output.VerglasCrystalLife / 2000
		assert.is_true(math.abs(expectedGain - output.VerglasColdGain) < 1e-6)

		-- The gain is applied as a DamageGainAsCold modifier on the supported skill
		local mainSkill = build.calcsTab.calcsEnv.player.mainSkill
		assert.is_true(math.abs(expectedGain - mainSkill.skillModList:Sum("BASE", mainSkill.skillCfg, "DamageGainAsCold")) < 1e-6)
	end)

	local function enableVerglasBuff()
		build.configTab.input.conditionDestroyedIceCrystalRecently = true
		build.configTab:BuildModList()
		build.buildFlag = true
		runCallback("OnFrame")
		build.calcsTab:BuildOutput()
		runCallback("OnFrame")
	end

	it("scales the Verglas buff with increased Ice Crystal Life", function()
		setupVerglasBuild()
		enableVerglasBuff()
		local baseLife = build.calcsTab.mainOutput.VerglasCrystalLife
		local baseGain = build.calcsTab.mainOutput.VerglasColdGain
		assert.is_true(baseLife > 0)

		build.configTab.input.customMods = "100% increased Ice Crystal Life"
		enableVerglasBuff()

		-- 100% increased Ice Crystal Life doubles both the crystal life and the cold gain
		assert.is_true(math.abs(build.calcsTab.mainOutput.VerglasCrystalLife - baseLife * 2) < 1)
		assert.is_true(math.abs(build.calcsTab.mainOutput.VerglasColdGain - baseGain * 2) < 1e-4)
	end)

	it("maps the Frost Wall ice_crystal_maximum_life_+% quality stat to IceCrystalLife", function()
		local statMap = data.skillStatMap["ice_crystal_maximum_life_+%"]
		assert.is_not_nil(statMap)
		assert.are.equals("IceCrystalLife", statMap[1].name)
		assert.are.equals("INC", statMap[1].type)
	end)

	it("parses 'Ice Crystals have #% reduced maximum Life per 5% Cold Resistance' into IceCrystalLife", function()
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Stellar Amulet
			Ice Crystals have -10% reduced maximum Life per 5% Cold Resistance you have
		]])
		local item = build.itemsTab.displayItem
		local found
		for _, modLine in ipairs(item.explicitModLines) do
			for _, m in ipairs(modLine.modList or {}) do
				if m.name == "IceCrystalLife" and m.type == "INC" then
					found = m
				end
			end
		end
		assert.is_not_nil(found)
		-- -10% reduced == +10% increased, scaled per 5% Cold Resistance
		assert.are.equals(10, found.value)
		assert.are.equals("PerStat", found[1].type)
		assert.are.equals("ColdResist", found[1].stat)
		assert.are.equals(5, found[1].div)
	end)
end)
