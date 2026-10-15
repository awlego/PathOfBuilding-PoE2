describe("TestTravellersWisdom", function()
	before_each(function()
		newBuild()
	end)

	-- Pathfinder's Traveller's Wisdom notable
	local TRAVELLERS_WISDOM = 46454

	local function recalc()
		build.buildFlag = true
		runCallback("OnFrame")
	end

	local function incDamage()
		return build.calcsTab.mainEnv.modDB:Sum("INC", nil, "Damage")
	end

	-- Closest unallocated small attribute node
	local function pickAttributeNode(spec)
		local best, bestLen
		for id, node in pairs(spec.nodes) do
			if node.isAttribute and node.type == "Normal" and not node.ascendancyName and not node.alloc and node.path and #node.path > 0 then
				if not bestLen or #node.path < bestLen or (#node.path == bestLen and id < best) then
					best, bestLen = id, #node.path
				end
			end
		end
		return best
	end

	it("offers, applies, saves and reverts Traveller's Wisdom attribute options", function()
		local spec = build.spec
		local classId, ascendClassId
		for id, class in pairs(spec.tree.classes) do
			for ascId, ascendClass in pairs(class.classes or { }) do
				if ascendClass.name == "Pathfinder" then
					classId, ascendClassId = id, ascId
				end
			end
		end
		spec:SelectClass(classId)
		spec:SelectAscendClass(ascendClassId)
		local travellersWisdom = spec.nodes[TRAVELLERS_WISDOM]
		assert.is_not_nil(travellersWisdom)
		local optionMods = 0
		for _, mod in ipairs(travellersWisdom.modList) do
			if mod.name == "AttributeOption" then
				optionMods = optionMods + 1
			end
		end
		assert.are.equals(3, optionMods)

		spec:AllocNode(travellersWisdom)
		recalc()
		local options = spec:GetDynamicAttributeOptions()
		assert.are.equals(3, #options)
		local damageIndex
		for i, option in ipairs(options) do
			if option == "5% increased damage" then
				damageIndex = i + 3
			end
		end
		assert.is_not_nil(damageIndex)

		local baseInc = incDamage()
		local attributeId = pickAttributeNode(spec)
		spec:SwitchAttributeNode(attributeId, damageIndex)
		spec.attributeIndex = damageIndex
		spec:AllocNode(spec.nodes[attributeId])
		recalc()
		assert.are.equals("5% increased damage", spec.nodes[attributeId].sd[1])
		assert.are.equals(baseInc + 5, incDamage())

		-- Save and load round trip
		local xml = build:SaveDB("test")
		assert.is_truthy(xml:find("<Custom", 1, true))
		loadBuildFromXML(xml)
		recalc()
		assert.are.equals("5% increased damage", build.spec.nodes[attributeId].sd[1])
		assert.are.equals(baseInc + 5, incDamage())

		-- Deallocating the source reverts the override
		build.spec:DeallocNode(build.spec.nodes[TRAVELLERS_WISDOM])
		recalc()
		assert.is_nil(build.spec.hashOverrides[attributeId])
		assert.are.equals(baseInc, incDamage())
	end)

	it("supports a custom modifier source and reverts when it is removed", function()
		local spec = build.spec
		build.configTab.input.customMods = "Attribute Passive Skills can instead grant 8% increased Evasion Rating"
		build.configTab:BuildModList()
		recalc()
		assert.are.equals(1, #spec:GetDynamicAttributeOptions())
		local attributeId = pickAttributeNode(spec)
		spec:SwitchAttributeNode(attributeId, 4)
		spec.attributeIndex = 4
		spec:AllocNode(spec.nodes[attributeId])
		recalc()
		assert.are.equals("8% increased evasion rating", spec.nodes[attributeId].sd[1])
		build.configTab.input.customMods = ""
		build.configTab:BuildModList()
		recalc()
		assert.is_nil(spec.hashOverrides[attributeId])
	end)
end)
