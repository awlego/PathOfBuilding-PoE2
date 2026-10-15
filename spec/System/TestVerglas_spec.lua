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

	local function enableVerglasBuff()
		build.configTab.input.conditionDestroyedIceCrystalPast6Seconds = true
		build.configTab:BuildModList()
		build.buildFlag = true
		runCallback("OnFrame")
	end

	local function findSkill(name)
		for _, activeSkill in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
			if activeSkill.activeEffect.grantedEffect.name == name then
				return activeSkill
			end
		end
	end

	local function coldGain(skill)
		return skill.skillModList:Sum("BASE", skill.skillCfg, "DamageGainAsCold")
	end

	it("does not grant Cold when the Verglas buff is inactive", function()
		setupVerglasBuild()
		assert.are.equals(0, coldGain(findSkill("Fireball")))
	end)

	it("grants 1% Cold per full 2000 destroyed Ice Crystal Life when the buff is active", function()
		setupVerglasBuild()
		build.configTab.input.customMods = "1000% increased Ice Crystal Life"
		enableVerglasBuff()

		local crystalLife = build.calcsTab.mainEnv.player.destroyedIceCrystalLife
		assert.is_true(crystalLife >= 2000)
		assert.are.equals(math.floor(crystalLife / 2000), coldGain(findSkill("Fireball")))
		-- Only the supported skill gains Cold
		assert.are.equals(0, coldGain(findSkill("Frost Wall")))
	end)

	it("scales the Verglas buff with increased Ice Crystal Life", function()
		setupVerglasBuild()
		build.configTab.input.customMods = "1000% increased Ice Crystal Life"
		enableVerglasBuff()
		local baseLife = build.calcsTab.mainEnv.player.destroyedIceCrystalLife

		build.configTab.input.customMods = "2100% increased Ice Crystal Life"
		enableVerglasBuff()
		local crystalLife = build.calcsTab.mainEnv.player.destroyedIceCrystalLife
		assert.is_true(math.abs(crystalLife - baseLife * 2) < 1)
		assert.are.equals(math.floor(crystalLife / 2000), coldGain(findSkill("Fireball")))
	end)

	it("does not change other skills' duration when the buff is active", function()
		setupVerglasBuild()
		local frostWall = findSkill("Frost Wall")
		local baseDuration = frostWall.skillModList:Sum("BASE", frostWall.skillCfg, "Duration")

		enableVerglasBuff()
		frostWall = findSkill("Frost Wall")
		assert.are.equals(baseDuration, frostWall.skillModList:Sum("BASE", frostWall.skillCfg, "Duration"))
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
