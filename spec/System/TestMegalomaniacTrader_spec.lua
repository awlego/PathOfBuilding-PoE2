describe("TestMegalomaniacTrader", function()
	before_each(function()
		newBuild()
	end)

	it("scores a Megalomaniac by the notables it allocates", function()
		build.spec:SelectClass(build.spec.tree.classNameMap["Warrior"])
		build.buildFlag = true
		runCallback("OnFrame")
		local calcFunc, baseOutput = build.calcsTab:GetMiscCalculator()
		-- Pick the first Megalomaniac notable (by node id) that adds Life when allocated
		local candidates = { }
		for _, node in pairs(build.spec.tree.notableMap) do
			if node.recipe and not node.alloc then
				for _, line in ipairs(node.sd or { }) do
					if line:match("increased maximum Life") then
						table.insert(candidates, node)
						break
					end
				end
			end
		end
		table.sort(candidates, function(a, b) return a.id < b.id end)
		local target, direct
		for _, node in ipairs(candidates) do
			local output = calcFunc({ addNodes = { [node] = true } })
			if output.Life > baseOutput.Life then
				target, direct = node, output
				break
			end
		end
		assert.is_not_nil(target)

		local tradeQuery = new("TradeQuery"):TradeQuery(build.itemsTab)
		tradeQuery.tradeQueryGenerator = new("TradeQueryGenerator"):TradeQueryGenerator(tradeQuery)
		tradeQuery.slotTables = { { slotName = "Megalomaniac", unique = true } }
		tradeQuery.statSortSelectionList = { { stat = "Life", label = "Life", weightMult = 1 } }
		tradeQuery.resultTbl = { { { item_string = "Rarity: UNIQUE\nMegalomaniac\nDiamond\nAllocates " .. target.dn .. "\n" } } }
		local evaluation = tradeQuery:GetResultEvaluation(1, 1, calcFunc, baseOutput)
		assert.are.near(direct.Life, evaluation[1].output.Life, 1e-6)
	end)
end)
