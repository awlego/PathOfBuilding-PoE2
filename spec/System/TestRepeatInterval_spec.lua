describe("Repeat interval skills", function()
	before_each(function()
		newBuild()
	end)

	local function rebuild()
		build.configTab:BuildModList()
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput, build.calcsTab.mainEnv
	end

	local function roundUpToServerTick(value)
		return math.ceil(value * data.misc.ServerTickRate) / data.misc.ServerTickRate
	end

	-- Equip a staff granting level 20 Mirror of Refraction and make it the main skill
	local function equipMirrorOfRefraction()
		-- Granted skill levels are capped by character level and attributes
		build.characterLevel = 90
		build.characterLevelAutoMode = false
		local item = new("Item"):Item("New Item\nReflecting Staff\nImplicits: 1\nGrants Skill: Level 20 Mirror of Refraction\n+400 to Intelligence")
		build.itemsTab:AddItem(item, true)
		build.itemsTab.slots["Weapon 1"]:SetSelItemId(item.id)
		rebuild()
		for index, group in ipairs(build.skillsTab.socketGroupList) do
			if group.sourceItem == item then
				build.mainSocketGroup = index
			end
		end
		local output, env = rebuild()
		assert.are.equals("Mirror of Refraction", env.player.mainSkill.activeEffect.grantedEffect.name)
		assert.are.equals(20, env.player.mainSkill.activeEffect.level)
		return output, env
	end

	it("maps the Mirror of Refraction cooldown recovery line to a supported stat", function()
		assert.is_not_nil(data.skillStatMap["cooldown_recovery_modifiers_also_apply_to_repeat_interval"])
		local statSet = data.skills["MirrorOfRefractionPlayer"].statSets[1]
		assert.is_not_nil(statSet.statMap["cooldown_recovery_modifiers_also_apply_to_repeat_interval"])
	end)

	it("calculates the Mirror of Refraction appearance interval instead of a skill cooldown", function()
		local output, env = equipMirrorOfRefraction()
		assert.is_truthy(env.player.mainSkill.skillData.repeatIntervalUsesCooldownRecovery)
		assert.are.near(roundUpToServerTick(2), output.RepeatInterval, 0.0001)
		assert.is_nil(output.Cooldown)
	end)

	it("applies increased and more cooldown recovery rate to Mirror appearance frequency", function()
		equipMirrorOfRefraction()
		build.configTab.input.customMods = "50% increased Cooldown Recovery Rate"
		local output = rebuild()
		assert.are.near(roundUpToServerTick(2 / 1.5), output.RepeatInterval, 0.0001)

		build.configTab.input.customMods = "50% increased Cooldown Recovery Rate\n20% more Cooldown Recovery Rate"
		output = rebuild()
		assert.are.near(roundUpToServerTick(2 / (1.5 * 1.2)), output.RepeatInterval, 0.0001)
	end)

	it("ignores cooldown recovery for repeat intervals without the cooldown recovery line", function()
		-- No current skill has a non-zero repeat interval without the line, so drop it from Mirror of Refraction temporarily
		local stats = data.skills["MirrorOfRefractionPlayer"].statSets[1].stats
		local lineIndex
		for index, stat in ipairs(stats) do
			if stat == "cooldown_recovery_modifiers_also_apply_to_repeat_interval" then
				lineIndex = index
			end
		end
		assert.are.equals(#stats, lineIndex) -- removing the last stat keeps the level values aligned
		table.remove(stats, lineIndex)
		local ok, err = pcall(function()
			local _, env = equipMirrorOfRefraction()
			assert.is_nil(env.player.mainSkill.skillData.repeatIntervalUsesCooldownRecovery)
			build.configTab.input.customMods = "50% increased Cooldown Recovery Rate"
			local output = rebuild()
			assert.are.near(roundUpToServerTick(2), output.RepeatInterval, 0.0001)
		end)
		table.insert(stats, lineIndex, "cooldown_recovery_modifiers_also_apply_to_repeat_interval")
		assert(ok, err)
	end)
end)
