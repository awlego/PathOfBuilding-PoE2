describe("Trader max budget", function()
	local function newGenerator(queryTab)
		queryTab.itemsTab = queryTab.itemsTab or { }
		return new("TradeQueryGenerator"):TradeQueryGenerator(queryTab)
	end

	it("adds no price filter without a budget", function()
		local gen = newGenerator({ })
		assert.is_nil(gen:GetBudgetPriceFilter())
		gen.queryTab.maxBudget = 0
		assert.is_nil(gen:GetBudgetPriceFilter())
	end)

	it("builds a price filter in the chosen currency", function()
		local gen = newGenerator({ maxBudget = 50, maxBudgetTypeIndex = 4 })
		assert.are.same({ option = "divine", max = 50 }, gen:GetBudgetPriceFilter())
		-- Exalted Orb Equivalent has no currency id
		gen.queryTab.maxBudgetTypeIndex = 1
		assert.are.same({ max = 50 }, gen:GetBudgetPriceFilter())
	end)

	it("applies the budget to Time-Lost solver searches", function()
		local gen = newGenerator({ maxBudget = 20, maxBudgetTypeIndex = 4 })
		local captured
		gen.requesterCallback = function(context, queryTable) captured = queryTable end
		local row = {
			base = "Time-Lost Sapphire",
			prefixes = { { mod = { tradeHashes = { [123] = true } } } },
			suffixes = { },
		}
		gen:BuildTradeQueryFromTimeLostRow(row)
		assert.are.same({ option = "divine", max = 20 }, captured.filters.trade_filters.filters.price)

		gen.queryTab.maxBudget = nil
		gen:BuildTradeQueryFromTimeLostRow(row)
		assert.is_nil(captured.filters.trade_filters)
	end)

	it("feeds the budget into Find best queries", function()
		local gen = newGenerator({ maxBudget = 300, maxBudgetTypeIndex = 2 })
		local options = { }
		-- StartQuery copies the budget into options before doing any item work
		pcall(gen.StartQuery, gen, nil, options)
		assert.are.equal(300, options.maxPrice)
		assert.are.equal("exalted", options.maxPriceType)
	end)
end)
