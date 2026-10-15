describe("Archon of Undeath and Puppet Master", function()
	before_each(function()
		newBuild()
	end)

	local function parse(line)
		local list, extra = modLib.parseMod(line)
		assert.is_nil(extra)
		return list
	end

	local function rebuild()
		build.configTab:BuildModList()
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput, build.calcsTab.mainEnv
	end

	local function setMods(text)
		build.configTab.input.customMods = text
		return rebuild()
	end

	-- Sum of a player MinionModifier sub-mod (e.g. Damage MORE) contributed by the given source
	local function minionModifierSum(env, name, modType, source)
		local total = 0
		for _, row in ipairs(env.player.modDB:Tabulate("LIST", nil, "MinionModifier")) do
			local mod = row.value.mod
			if mod.name == name and mod.type == modType and mod.source == source then
				total = total + mod.value
			end
		end
		return total
	end

	describe("parsing", function()
		it("parses Archon Buff modifiers", function()
			assert.are.same("ArchonBuffDuration", parse("30% increased Archon Buff duration")[1].name)
			assert.are.equals(30, parse("30% increased Archon Buff duration")[1].value)
			assert.are.same("ArchonBuffEffect", parse("10% increased effect of Archon Buffs on you")[1].name)
			assert.are.equals(-50, parse("50% reduced effect of Archon Buffs on you")[1].value)
			assert.are.equals(25, parse("Archon recovery period expires 25% faster")[1].value)
			assert.are.equals(-30, parse("Archon recovery period expires 30% slower")[1].value)
			assert.are.same("ArchonNoRecoveryPeriod", parse("Archon Buffs have no recovery period after you lose one")[1].name)
		end)

		it("wraps Archon Buffs also grant modifiers", function()
			local mod = parse("Archon Buffs also grant +20% to all Elemental Resistances")[1]
			assert.are.same("ArchonBuffGrant", mod.name)
			assert.are.same("ElementalResist", mod.value.mod.name)
			assert.are.equals(20, mod.value.mod.value)
		end)

		it("tags while affected by an Archon Buff", function()
			local mod = parse("Immune to Shock while affected by an Archon Buff")[1]
			assert.are.same("ShockImmune", mod.name)
			assert.are.same("AffectedByArchonBuff", mod[1].var)
		end)

		it("parses Archon of Undeath and Puppet Master sources", function()
			local archon = parse("15% chance to gain Archon of Undeath when you use a Command skill")
			assert.are.same("ArchonOfUndeathChance", archon[1].name)
			assert.are.same("CanGainArchonOfUndeath", archon[2].name)
			local puppet = parse("35% Surpassing Chance to gain a Puppet Master stack whenever you use a Command Skill")
			assert.are.same("PuppetMasterChance", puppet[1].name)
			assert.are.same("CanGainPuppetMaster", puppet[2].name)
			assert.are.equals(4, parse("+4 maximum stacks of Puppet Master")[1].value)
			assert.are.same("PuppetMasterEffect", parse("15% increased Effect of Puppet Master")[1].name)
			assert.are.same("PuppetMasterDuration", parse("25% increased Duration of each Puppet Master stack")[1].name)
		end)
	end)

	describe("Archon of Undeath", function()
		local sourceMods = "15% chance to gain Archon of Undeath when you use a Command skill\n" ..
			"50% increased effect of Archon Buffs on you\n" ..
			"40% increased Archon Buff duration\n" ..
			"Archon recovery period expires 25% faster\n" ..
			"Archon Buffs also grant +20% to all Elemental Resistances\n" ..
			"Immune to Shock while affected by an Archon Buff"

		it("is only offered when you can gain it", function()
			rebuild()
			assert.is_false(build.configTab.varControls.conditionArchonOfUndeath.shown() and true or false)
			setMods(sourceMods)
			assert.is_true(build.configTab.varControls.conditionArchonOfUndeath.shown() and true or false)
		end)

		it("reports duration and recovery period", function()
			local output = setMods(sourceMods)
			assert.are.near(14, output.ArchonBuffDuration, 0.001)
			assert.are.near(16, output.ArchonRecoveryPeriod, 0.001)
		end)

		it("does nothing until enabled, then applies scaled buff and also-grant stats", function()
			local output, env = setMods(sourceMods)
			local fireBefore = output.FireResistTotal
			assert.are.equals(0, minionModifierSum(env, "Damage", "MORE", "Archon of Undeath"))
			assert.is_falsy(env.player.modDB:Flag(nil, "ShockImmune"))

			build.configTab.input.conditionArchonOfUndeath = true
			build.configTab.input.overrideArchonUptime = 100
			output, env = rebuild()
			-- 25% more Minion Damage and 200% more Command Skill cooldown recovery, both at 50% increased effect
			assert.are.equals(37, minionModifierSum(env, "Damage", "MORE", "Archon of Undeath"))
			assert.are.equals(300, minionModifierSum(env, "CooldownRecovery", "MORE", "Archon of Undeath"))
			-- "Archon Buffs also grant +20% to all Elemental Resistances" scaled by effect
			assert.are.equals(fireBefore + 30, output.FireResistTotal)
			assert.is_true(env.player.modDB:Flag(nil, "ShockImmune"))
			assert.are.near(1.5, output.ArchonBuffEffect, 0.001)
		end)

		it("applies its more damage to an active minion", function()
			setMods("15% chance to gain Archon of Undeath when you use a Command skill")
			local socketGroup = { enabled = true, gemList = { { gemId = "Metadata/Items/Gems/SkillGemSkeletalBrute", level = 20, quality = 0, enabled = true, count = 1, enableGlobal1 = true, enableGlobal2 = true } } }
			table.insert(build.skillsTab.socketGroupList, socketGroup)
			build.skillsTab:ProcessSocketGroup(socketGroup)
			build.mainSocketGroup = #build.skillsTab.socketGroupList
			local _, env = rebuild()
			local minion = env.minion
			assert.is_not_nil(minion)
			local before = minion.modDB:More(minion.mainSkill.skillCfg, "Damage")

			build.configTab.input.conditionArchonOfUndeath = true
			build.configTab.input.overrideArchonUptime = 100
			_, env = rebuild()
			minion = env.minion
			assert.are.near(before * 1.25, minion.modDB:More(minion.mainSkill.skillCfg, "Damage"), 0.0001)
		end)

		it("averages the buff over its uptime", function()
			setMods(sourceMods)
			build.configTab.input.conditionArchonOfUndeath = true
			local output, env = rebuild()
			-- 15% chance at 0.5 Command Skill uses per second: 13.33s to regain after the 16s recovery period
			assert.are.near(40 / 3, output.ArchonGainTime, 0.001)
			assert.are.near(14 / (14 + 16 + 40 / 3) * 100, output.ArchonUptime, 0.001)
			-- 25% more and 200% more at 50% increased effect, x 32.3% uptime
			assert.are.equals(12, minionModifierSum(env, "Damage", "MORE", "Archon of Undeath"))
			assert.are.equals(96, minionModifierSum(env, "CooldownRecovery", "MORE", "Archon of Undeath"))
			-- "While affected by an Archon Buff" modifiers need 100% uptime
			assert.is_falsy(env.player.modDB:Flag(nil, "ShockImmune"))

			build.configTab.input.commandSkillUsesPerSecond = 2
			output = rebuild()
			assert.are.near(14 / (14 + 16 + 10 / 3) * 100, output.ArchonUptime, 0.001)

			-- The time to regain it is still reported when the uptime is overridden
			build.configTab.input.overrideArchonUptime = 100
			output = rebuild()
			assert.are.equals(100, output.ArchonUptime)
			assert.are.near(10 / 3, output.ArchonGainTime, 0.001)
		end)

		it("includes Offerings when you can gain it on creating an Offering", function()
			setMods("40% to gain Archon of Undeath when you create an Offering")
			build.configTab.input.conditionArchonOfUndeath = true
			assert.is_true(build.configTab.varControls.archonOfferingsPerSecond.shown() and true or false)
			local output = rebuild()
			assert.are.equals(0, output.ArchonUptime)

			build.configTab.input.archonOfferingsPerSecond = 0.5
			output = rebuild()
			assert.are.near(5, output.ArchonGainTime, 0.001)
			assert.are.near(10 / (10 + 20 + 5) * 100, output.ArchonUptime, 0.001)
		end)

		it("supports the Dominion anoint", function()
			setMods(sourceMods .. "\nAllocates Dominion")
			build.configTab.input.conditionArchonOfUndeath = true
			local output, env = rebuild()
			-- 50% increased and 50% reduced effect cancel out, and there is no recovery period
			assert.are.near(1, output.ArchonBuffEffect, 0.001)
			assert.are.equals(0, output.ArchonRecoveryPeriod)
			assert.are.near(14 / (14 + 40 / 3) * 100, output.ArchonUptime, 0.001)
			assert.are.equals(102, minionModifierSum(env, "CooldownRecovery", "MORE", "Archon of Undeath"))
		end)
	end)

	describe("Puppet Master", function()
		local sourceMods = "15% Surpassing Chance to gain a Puppet Master stack whenever you use a Command Skill\n" ..
			"+2 maximum stacks of Puppet Master\n" ..
			"20% increased Effect of Puppet Master"

		it("is only offered when you can gain stacks", function()
			rebuild()
			assert.is_false(build.configTab.varControls.usePuppetMaster.shown() and true or false)
			setMods(sourceMods)
			assert.is_true(build.configTab.varControls.usePuppetMaster.shown() and true or false)
		end)

		-- E[min(N, cap)] for N ~ Poisson(mean)
		local function cappedPoissonMean(mean, cap)
			local total, probability, cumulative = 0, math.exp(-mean), 0
			for count = 0, cap - 1 do
				cumulative = cumulative + probability
				total = total + (1 - cumulative)
				probability = probability * mean / (count + 1)
			end
			return total
		end

		it("calculates average stacks from Command Skill uses", function()
			local output, env = setMods(sourceMods)
			assert.is_nil(output.PuppetMasterStacks)
			assert.are.equals(0, minionModifierSum(env, "Damage", "INC", "Puppet Master"))

			build.configTab.input.usePuppetMaster = true
			output = rebuild()
			assert.are.equals(7, output.PuppetMasterStacksMax)
			assert.are.near(8, output.PuppetMasterDuration, 0.001)
			-- 15% Surpassing Chance x 0.5 Command Skill uses per second x 8 seconds
			assert.are.near(cappedPoissonMean(0.6, 7), output.PuppetMasterStacks, 0.0001)

			build.configTab.input.commandSkillUsesPerSecond = 5
			output = rebuild()
			assert.are.near(cappedPoissonMean(6, 7), output.PuppetMasterStacks, 0.0001)
			assert.is_true(output.PuppetMasterStacks > 5 and output.PuppetMasterStacks < 7)
		end)

		it("scales per stack and by effect", function()
			setMods(sourceMods)
			build.configTab.input.usePuppetMaster = true
			build.configTab.input.overridePuppetMasterStacks = 7
			local output, env = rebuild()
			assert.are.equals(7, output.PuppetMasterStacks)
			-- 10% per stack with Command Skills, 7 stacks, 20% increased effect
			assert.are.equals(84, minionModifierSum(env, "Damage", "INC", "Puppet Master"))
		end)

		it("respects a configured stack count, capped at maximum", function()
			setMods(sourceMods)
			build.configTab.input.usePuppetMaster = true
			build.configTab.input.overridePuppetMasterStacks = 3
			local output, env = rebuild()
			assert.are.equals(3, output.PuppetMasterStacks)
			assert.are.equals(36, minionModifierSum(env, "Damage", "INC", "Puppet Master"))

			build.configTab.input.overridePuppetMasterStacks = 50
			output = rebuild()
			assert.are.equals(7, output.PuppetMasterStacks)
		end)
	end)
end)
