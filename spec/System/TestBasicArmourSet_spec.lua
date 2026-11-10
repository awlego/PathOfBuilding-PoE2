describe("TestBasicArmourSet", function()
	before_each(function()
		newBuild()
	end)

	-- Tier as the item tooltip counts it: 1 is the highest tier of the series that can roll on the item
	local function affixTier(item, modId)
		local stem = modId:gsub("%d+_*$", "")
		local tier = 1
		for otherId, mod in pairs(item.affixes) do
			if otherId:match("^" .. stem .. "%d+_*$") and item:GetModSpawnWeight(mod) > 0 and mod.level > item.affixes[modId].level then
				tier = tier + 1
			end
		end
		return tier
	end

	it("builds four rares of a single tier on the top base of every defence type", function()
		local types = build.itemsTab:GetBasicArmourSetTypes()
		assert.are.equal(6, #types)
		for _, case in ipairs({ { false, 3 }, { true, 3 }, { false, 1 }, { true, 2 } }) do
			local runeforged, tier = case[1], case[2]
			for _, subType in ipairs(types) do
				local items = build.itemsTab:CreateBasicArmourSet(subType, runeforged, tier)
				assert.are.equal(4, #items)
				for _, item in ipairs(items) do
					assert.are.equal("RARE", item.rarity)
					assert.are.equal(subType, item.base.subType)
					assert.are.equal(runeforged, item.baseName:find("Runeforged", 1, true) ~= nil)
					-- The rare templates list the same top bases
					assert.is_not_nil(main.rareDB.list[item.name:gsub("^T" .. tier .. " ", "")])
					assert.are.equal("T" .. tier .. " " .. subType, item.title:sub(1, #subType + 3))
					for _, affixList in ipairs({ item.prefixes, item.suffixes }) do
						for index = 1, 3 do
							assert.are.equal(tier, affixTier(item, affixList[index].modId))
						end
					end
				end
			end
		end
	end)

	it("defaults to tier 3 and rolls more on tier 1", function()
		local function life(tier)
			local body = build.itemsTab:CreateBasicArmourSet("Armour", false, tier)[2]
			return body.affixes[body.prefixes[3].modId].level
		end
		assert.are.equal(life(3), life(nil))
		assert.is_true(life(1) > life(3))
	end)

	it("spreads the four resistances evenly over the set", function()
		local count = { }
		for _, item in ipairs(build.itemsTab:CreateBasicArmourSet("Armour/Evasion", false)) do
			for index = 1, 3 do
				local stem = item.suffixes[index].modId:gsub("%d+_*$", "")
				count[stem] = (count[stem] or 0) + 1
			end
		end
		assert.are.same({ FireResist = 3, ColdResist = 3, LightningResist = 3, ChaosResist = 3 }, count)
	end)

	it("adds the set to the build, equips it and undoes in one step", function()
		build.itemsTab:AddBasicArmourSet("Energy Shield", false)
		runCallback("OnFrame")
		local baseEnergyShield = build.calcsTab.mainOutput.EnergyShield
		assert.is_true(baseEnergyShield > 1000)
		assert.are.equal(build.calcsTab.mainOutput.FireResist, build.calcsTab.mainOutput.ColdResist)

		build.itemsTab:AddBasicArmourSet("Armour", true)
		runCallback("OnFrame")
		for _, slotName in ipairs({ "Helmet", "Body Armour", "Gloves", "Boots" }) do
			local item = build.itemsTab.items[build.itemsTab.slots[slotName].selItemId]
			assert.are.equal("Armour", item.base.subType)
			assert.is_true(item.base.tags.runeforged)
		end
		assert.is_true(build.calcsTab.mainOutput.Ward > 0)

		build.itemsTab:Undo()
		build.buildFlag = true
		runCallback("OnFrame")
		assert.are.equal("Energy Shield", build.itemsTab.items[build.itemsTab.slots["Helmet"].selItemId].base.subType)
		assert.are.equal(baseEnergyShield, build.calcsTab.mainOutput.EnergyShield)
	end)
end)
