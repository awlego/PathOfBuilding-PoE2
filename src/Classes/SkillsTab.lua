-- Path of Building
--
-- Module: Skills Tab
-- Skills tab for the current build.
--
local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max

local supportGemSolver = LoadModule("Modules/SupportGemSolver")

local groupSlotDropList = {
	{ label = "None" },
	{ label = "Weapon 1", slotName = "Weapon 1" },
	{ label = "Weapon 2", slotName = "Weapon 2" },
	{ label = "Weapon 1 (Swap)", slotName = "Weapon 1 Swap" },
	{ label = "Weapon 2 (Swap)", slotName = "Weapon 2 Swap" },
	{ label = "Helmet", slotName = "Helmet" },
	{ label = "Body Armour", slotName = "Body Armour" },
	{ label = "Gloves", slotName = "Gloves" },
	{ label = "Boots", slotName = "Boots" },
	{ label = "Amulet", slotName = "Amulet" },
	{ label = "Ring 1", slotName = "Ring 1" },
	{ label = "Ring 2", slotName = "Ring 2" },
	{ label = "Ring 3", slotName = "Ring 3" },
	{ label = "Belt", slotName = "Belt" },
}

local defaultGemLevelList = {
	{
		label = "Normal Maximum",
		description = "All gems default to their highest valid non-corrupted gem level.",
		gemLevel = "normalMaximum",
	},
	{
		label = "Corrupted Maximum",
		description = [[Normal gems default to their highest valid corrupted gem level.
Awakened gems default to their highest valid non-corrupted gem level.]],
		gemLevel = "corruptedMaximum",
	},
	--{
	--	label = "Awakened Maximum",
	--	description = "All gems default to their highest valid corrupted gem level.",
	--	gemLevel = "awakenedMaximum",
	--},
	{
		label = "Match Character Level",
		description = [[All gems default to their highest valid non-corrupted gem level that your character meets the level requirement for.
This hides gems with a minimum level requirement above your character level, preventing them from showing up in the dropdown list.]],
		gemLevel = "characterLevel",
	},
}

local showSupportGemTypeList = {
	{ label = "All", show = "ALL" },
	{ label = "Lineage", show = "LINEAGE" },
	{ label = "Non-Lineage", show = "NORMAL" },
}

local corruptOption = {
	{ label = "Not Corrupted", level = 0 },
	{ label = "+1 to Gem Level", level = 1 },
	{ label = "Corrupted", level = 0 },
	{ label = "-1 to Gem Level", level = -1 },
}

local sortGemTypeList = {
	{ label = "Full DPS", type = "FullDPS" },
	{ label = "Combined DPS", type = "CombinedDPS" },
	{ label = "Hit DPS", type = "TotalDPS" },
	{ label = "Average Hit", type = "AverageDamage" },
	{ label = "DoT DPS", type = "TotalDot" },
	{ label = "Bleed DPS", type = "BleedDPS" },
	{ label = "Ignite DPS", type = "IgniteDPS" },
	{ label = "Poison DPS", type = "TotalPoisonDPS" },
	{ label = "Effective Hit Pool", type = "TotalEHP" },
}

local SkillsTabClass = newClass("SkillsTab", "UndoHandler", "ControlHost", "Control", function(self, build)
	self.UndoHandler()
	self.ControlHost()
	self.Control()

	self.build = build

	self.socketGroupList = { }

	self.sortGemsByDPS = true
	self.sortGemsByDPSField = "CombinedDPS"
	self.showSupportGemTypes = "ALL"
	self.showLegacyGems = false
	self.defaultGemLevel = "normalMaximum"
	self.defaultGemQuality = main.defaultGemQuality
	self.solveSupportsMetricIndex = 1
	self.solveSupportsCount = 5
	self.solveSupportsStatusText = nil
	self.solveSupportsCoroutine = nil
	self.solveSupportsGroup = nil
	self.solveSupportsSnapshot = nil
	-- Non-destructive preview from the last solve. Cleared when the user
	-- switches groups (see SetDisplayGroup) or after a successful Apply.
	-- Shape: { group, picks = { { gemId, gemData, name, level, quality, score }, ... },
	--          metric, baseScore, bestScore, evaluated }
	self.solveSupportsPreview = nil
	self.defaultCorruptionLevel = 0
	self.defaultCorruptionState = false

	-- Set selector
	self.controls.setSelect = new("DropDownControl", { "TOPLEFT", self, "TOPLEFT" }, { 76, 8, 210, 20 }, nil, function(index, value)
		self:SetActiveSkillSet(self.skillSetOrderList[index])
		self:AddUndoState()
	end)
	self.controls.setSelect.enableDroppedWidth = true
	self.controls.setSelect.enabled = function()
		return #self.skillSetOrderList > 1
	end
	self.controls.setLabel = new("LabelControl", { "RIGHT", self.controls.setSelect, "LEFT" }, { -2, 0, 0, 16 }, "^7Skill set:")
	self.controls.setManage = new("ButtonControl", { "LEFT", self.controls.setSelect, "RIGHT" }, { 4, 0, 90, 20 }, "Manage...", function()
		self:OpenSkillSetManagePopup()
	end)

	-- Socket group list
	self.controls.groupList = new("SkillListControl", { "TOPLEFT", self, "TOPLEFT" }, { 20, 54, 360, 300 }, self)
	self.controls.groupTip = new("LabelControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { 0, 8, 0, 14 },
[[
^7Usage Tips:
- You can copy/paste socket groups using Ctrl+C and Ctrl+V.
- Ctrl + Click to enable/disable socket groups.
- Ctrl + Right click to include/exclude in FullDPS calculations.
- Right click to set as the Main skill group.
]]
	)

	-- Gem options
	local optionInputsX = 170
	local optionInputsY = 45
	self.controls.optionSection = new("SectionControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { 0, optionInputsY + 50, 360, 150 }, "Gem Options")
	self.controls.sortGemsByDPS = new("CheckBoxControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { optionInputsX, optionInputsY + 70, 20 }, "Sort gems by DPS:", function(state)
		self.sortGemsByDPS = state
	end, nil, true)
	self.controls.sortGemsByDPSFieldControl = new("DropDownControl", { "LEFT", self.controls.sortGemsByDPS, "RIGHT" }, { 10, 0, 140, 20 }, sortGemTypeList, function(index, value)
		self.sortGemsByDPSField = value.type
	end)
	self.controls.defaultLevel = new("DropDownControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { optionInputsX, optionInputsY + 94, 170, 20 }, defaultGemLevelList, function(index, value)
		self.defaultGemLevel = value.gemLevel
	end)
	self.controls.defaultLevel.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode ~= "OUT" and value.description then
			tooltip:AddLine(16, "^7" .. value.description)
		end
	end
	self.controls.defaultLevelLabel = new("LabelControl", { "RIGHT", self.controls.defaultLevel, "LEFT" }, { -4, 0, 0, 16 }, "^7Default gem level:")
	self.controls.defaultQuality = new("EditControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { optionInputsX, optionInputsY + 118, 60, 20 }, nil, nil, "%D", 2, function(buf)
		self.defaultGemQuality = m_min(tonumber(buf) or 0, 23)
	end)
	self.controls.defaultQualityLabel = new("LabelControl", { "RIGHT", self.controls.defaultQuality, "LEFT" }, { -4, 0, 0, 16 }, "^7Default gem quality:")
	self.controls.showSupportGemTypes = new("DropDownControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { optionInputsX, optionInputsY + 142, 170, 20 }, showSupportGemTypeList, function(index, value)
		self.showSupportGemTypes = value.show
	end)
	self.controls.showSupportGemTypesLabel = new("LabelControl", { "RIGHT", self.controls.showSupportGemTypes, "LEFT" }, { -4, 0, 0, 16 }, "^7Show support gems:")
	self.controls.showLegacyGems = new("CheckBoxControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { optionInputsX, optionInputsY + 166, 20 }, "^7Show legacy gems:", function(state)
		self.showLegacyGems = state
	end)

	-- Socket group details
	if main.portraitMode then
		self.anchorGroupDetail = new("Control", { "TOPLEFT", self.controls.optionSection, "BOTTOMLEFT" }, { 0, 20, 0, 0 })
	else
		self.anchorGroupDetail = new("Control", { "TOPLEFT", self.controls.groupList, "TOPRIGHT" }, { 20, 0, 0, 0 })
	end
	self.anchorGroupDetail.shown = function()
		return self.displayGroup ~= nil
	end
	self.controls.groupLabel = new("EditControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, { 0, 0, 380, 20 }, nil, "Label", "%c", 50, function(buf)
		self.displayGroup.label = buf
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupSlotLabel = new("LabelControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, { 0, 30, 0, 16 }, "^7Socketed in:")
	self.controls.groupSlot = new("DropDownControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, { 85, 28, 130, 20 }, groupSlotDropList, function(index, value)
		self.displayGroup.slot = value.slotName
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupSlot.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode == "OUT" or index == 1 then
			tooltip:AddLine(16, "Select the item in which this skill is socketed.")
			tooltip:AddLine(16, "This will allow the skill to benefit from modifiers on the item that affect socketed gems.")
		else
			local slot = self.build.itemsTab.slots[value.slotName]
			local ttItem = self.build.itemsTab.items[slot.selItemId]
			if ttItem then
				self.build.itemsTab:AddItemTooltip(tooltip, ttItem, slot)
			else
				tooltip:AddLine(16, "No item is equipped in this slot.")
			end
		end
	end
	self.controls.groupSlot.enabled = function()
		return self.displayGroup.source == nil
	end
	self.controls.groupEnabled = new("CheckBoxControl", { "LEFT", self.controls.groupSlot, "RIGHT" }, { 70, 0, 20 }, "Enabled:", function(state)
		self.displayGroup.enabled = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupEnabled.tooltipFunc = function(tooltip)
		if tooltip:CheckForUpdate(self.build.outputRevision, self.displayGroup) then
			if self.displayGroup then
				local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator(self.build)
				if calcFunc then
					self.displayGroup.enabled = not self.displayGroup.enabled
					local output = calcFunc()
					self.displayGroup.enabled = not self.displayGroup.enabled
					self.build:AddStatComparesToTooltip(tooltip, calcBase, output, self.displayGroup.enabled and "^7Disabling this group will give you:" or "^7Enabling this group will give you:")
				end
			end
		end
	end
	self.controls.includeInFullDPS = new("CheckBoxControl", { "LEFT", self.controls.groupEnabled, "RIGHT" }, { 145, 0, 20 }, "Include in Full DPS:", function(state)
		self.displayGroup.includeInFullDPS = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupCountLabel = new("LabelControl", { "LEFT", self.controls.includeInFullDPS, "RIGHT" }, { 16, 0, 0, 16 }, "Count:")
	self.controls.groupCountLabel.shown = function()
		return self.displayGroup.source ~= nil
	end
	self.controls.groupCount = new("EditControl", { "LEFT", self.controls.groupCountLabel, "RIGHT" }, { 4, 0, 80, 20 }, nil, nil, "^%d.", 6, function(buf)
		self.displayGroup.groupCount = tonumber(buf) or 1
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupCount.shown = function()
		return self.displayGroup.source ~= nil
	end

	-- Support gem solver: pick a metric and a desired support count; the solver
	-- runs against the group's currently-enabled supports (pinned) and returns
	-- a non-destructive preview of N picks. "Apply (add-only)" then copies the
	-- picks into the live gemList, filling empty slots first and appending
	-- new ones for the remainder. Only available for user-managed socket
	-- groups (source == nil); item-granted groups have fixed gem lists.
	-- Row 2: solver controls.
	self.controls.solveSupportsLabel = new("LabelControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, { 0, 56, 0, 16 }, "^7Solve for:")
	self.controls.solveSupportsLabel.shown = function()
		return self.displayGroup and self.displayGroup.source == nil
	end
	self.controls.solveSupportsMetric = new("DropDownControl", { "LEFT", self.controls.solveSupportsLabel, "RIGHT" }, { 4, 0, 130, 20 }, supportGemSolver.metricList, function(index, value)
		self.solveSupportsMetricIndex = index
	end)
	self.controls.solveSupportsMetric.shown = function()
		return self.displayGroup and self.displayGroup.source == nil
	end
	self.controls.solveSupportsMetric.tooltipText = "Damage metric the solver will maximise.\nThe active skill for this socket group is whatever you've picked as Main Skill in the Calcs tab."
	self.controls.solveSupportsCountLabel = new("LabelControl", { "LEFT", self.controls.solveSupportsMetric, "RIGHT" }, { 12, 0, 0, 16 }, "^7N:")
	self.controls.solveSupportsCountLabel.shown = function()
		return self.displayGroup and self.displayGroup.source == nil
	end
	-- EditControl auto-adds +/- buttons whenever filter == "%D", which eat
	-- ~34px on the right; width 60 matches the existing groupCount / defaultQuality
	-- numeric inputs and leaves the digit visible alongside the buttons.
	self.controls.solveSupportsCount = new("EditControl", { "LEFT", self.controls.solveSupportsCountLabel, "RIGHT" }, { 4, 0, 60, 20 }, tostring(self.solveSupportsCount), nil, "%D", 2, function(buf)
		local n = tonumber(buf) or 0
		if n < 1 then n = 1 end
		if n > 20 then n = 20 end
		self.solveSupportsCount = n
	end)
	self.controls.solveSupportsCount.shown = function()
		return self.displayGroup and self.displayGroup.source == nil
	end
	self.controls.solveSupportsCount.tooltipText = "How many new supports the solver should pick.\nExisting enabled supports stay locked-in and don't count toward this number."
	self.controls.solveSupports = new("ButtonControl", { "LEFT", self.controls.solveSupportsCount, "RIGHT" }, { 6, 0, 80, 20 }, "Solve", function()
		self:SolveSupports()
	end)
	self.controls.solveSupports.shown = function()
		return self.displayGroup and self.displayGroup.source == nil
	end
	self.controls.solveSupports.enabled = function()
		return self.displayGroup and self.solveSupportsCoroutine == nil and (self.solveSupportsCount or 0) >= 1
	end
	self.controls.solveSupports.tooltipText = "Greedy search across all compatible support gems.\nEnabled supports already in the group are pinned and\nlock their gem families against duplicates. Picks go\ninto the Suggested panel — nothing is changed until\nyou hit Apply."
	self.controls.solveSupportsApply = new("ButtonControl", { "LEFT", self.controls.solveSupports, "RIGHT" }, { 6, 0, 130, 20 }, "Apply (add-only)", function()
		self:ApplyPreviewSupports()
	end)
	self.controls.solveSupportsApply.shown = function()
		return self.displayGroup and self.displayGroup.source == nil
	end
	self.controls.solveSupportsApply.enabled = function()
		local p = self.solveSupportsPreview
		return self.solveSupportsCoroutine == nil and p ~= nil and p.group == self.displayGroup and p.picks and #p.picks > 0
	end
	self.controls.solveSupportsApply.tooltipText = "Copy the Suggested supports into this group.\nFills empty slots first, then appends new ones.\nNever overwrites a slot that already contains a gem."
	self.controls.solveSupportsStatus = new("LabelControl", { "LEFT", self.controls.solveSupportsApply, "RIGHT" }, { 8, 0, 0, 16 }, "")
	self.controls.solveSupportsStatus.shown = function()
		return self.solveSupportsStatusText ~= nil and self.displayGroup and self.displayGroup.source == nil
	end
	self.controls.solveSupportsStatus.label = function()
		return self.solveSupportsStatusText or ""
	end
	-- Row 3: locked supports (read-only summary of what's pinned for the solve).
	self.controls.solveSupportsLockedLabel = new("LabelControl", { "TOPLEFT", self.controls.solveSupportsLabel, "BOTTOMLEFT" }, { 0, 8, 0, 16 }, "^7Locked:")
	self.controls.solveSupportsLockedLabel.shown = function()
		return self.displayGroup and self.displayGroup.source == nil
	end
	self.controls.solveSupportsLockedNames = new("LabelControl", { "LEFT", self.controls.solveSupportsLockedLabel, "RIGHT" }, { 6, 0, 0, 16 }, "")
	self.controls.solveSupportsLockedNames.shown = function()
		return self.displayGroup and self.displayGroup.source == nil
	end
	self.controls.solveSupportsLockedNames.label = function()
		return self:FormatLockedSupportsLabel()
	end
	-- Row 4: solver suggestions (output of the most recent solve).
	self.controls.solveSupportsSuggestedLabel = new("LabelControl", { "TOPLEFT", self.controls.solveSupportsLockedLabel, "BOTTOMLEFT" }, { 0, 4, 0, 16 }, "^7Suggested:")
	self.controls.solveSupportsSuggestedLabel.shown = function()
		return self.displayGroup and self.displayGroup.source == nil
	end
	self.controls.solveSupportsSuggestedNames = new("LabelControl", { "LEFT", self.controls.solveSupportsSuggestedLabel, "RIGHT" }, { 6, 0, 0, 16 }, "")
	self.controls.solveSupportsSuggestedNames.shown = function()
		return self.displayGroup and self.displayGroup.source == nil
	end
	self.controls.solveSupportsSuggestedNames.label = function()
		return self:FormatSuggestedSupportsLabel()
	end

	self.controls.sourceNote = new("LabelControl", { "TOPLEFT", self.controls.groupSlotLabel, "TOPLEFT" }, { 0, 30, 0, 16 })
	self.controls.sourceNote.shown = function()
		return self.displayGroup.source ~= nil
	end
	self.controls.sourceNote.label = function()
		local label
		if self.displayGroup.explodeSources then
			label = [[^7This is a special group created for the enemy explosion effect,
which comes from the following sources:]]
			for _, source in ipairs(self.displayGroup.explodeSources) do
				label = label .. "\n\t" .. colorCodes[source.rarity or "NORMAL"] .. (source.name or source.dn or "???")
			end
			label = label .. "^7\nYou cannot delete this group, but it will disappear if you lose the above sources."
		else
			local activeGem = self.displayGroup.gemList[1]
			local sourceName
			if self.displayGroup.sourceItem then
				sourceName = "'" .. colorCodes[self.displayGroup.sourceItem.rarity] .. self.displayGroup.sourceItem.name
			elseif self.displayGroup.sourceNode then
				sourceName = "'" .. colorCodes["NORMAL"] .. self.displayGroup.sourceNode.name
			else
				sourceName = "'" .. colorCodes["NORMAL"] .. "?"
			end
			sourceName = sourceName .. "^7'"
			label = [[^7This is a special group created for the ']] .. activeGem.color .. (activeGem.grantedEffect and activeGem.grantedEffect.name or activeGem.nameSpec) .. [[^7' skill,
which is being provided by ]] .. sourceName .. [[.
You cannot delete this group, but it will disappear if you ]] .. (self.displayGroup.sourceNode and [[un-allocate the node.]] or [[un-equip the item.]])
			if not self.displayGroup.noSupports then
				label = label .. "\n\n" .. [[You cannot add support gems to this group, but support gems in
any other group socketed into ]] .. sourceName .. [[
will automatically apply to the skill.]]
			end
		end
		return label
	end

	-- Scroll bar
	self.controls.scrollBarH = new("ScrollBarControl", nil, {0, 0, 0, 18}, 100, "HORIZONTAL", true)

	-- Initialise skill sets
	self.skillSets = { }
	self.skillSetOrderList = { 1 }
	self:CreateSkillSet(1)
	self:SetActiveSkillSet(1)

	-- Skill gem slots
	-- Y offset leaves room for three solver rows added below the slot/enabled
	-- row: metric/N/Solve/Apply controls, a Locked-supports summary, and a
	-- Suggested-supports summary. See the "Support gem solver" block above.
	self.anchorGemSlots = new("Control", {"TOPLEFT",self.anchorGroupDetail,"TOPLEFT"}, {0, 140, 0, 0})
	self.gemSlots = { }
	self:CreateGemSlot(1)
	self.controls.gemNameHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].nameSpec, "TOPLEFT"}, {0, -2, 0, 16}, "^7Gem name:")
	self.controls.gemLevelHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].level, "TOPLEFT"}, {0, -2, 0, 16}, "^7Level:")
	self.controls.gemQualityHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].quality, "TOPLEFT"}, {0, -2, 0, 16}, "^7Quality:")
	self.controls.gemCorruptHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].corruptLevel, "TOPLEFT"}, {0, -2, 0, 16}, "^7Corrupt:")
	self.controls.gemEnableHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].enabled, "TOPLEFT"}, {-16, -2, 0, 16}, "^7Enabled:")
	self.controls.gemCountHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].count, "TOPLEFT"}, {18, -2, 0, 16}, "^7Count:")
end)

function SkillsTabClass:GetCorruptIndex(gemInstance)
	if gemInstance.corruptLevel == 1 then
		return 2  -- +1 to Gem Level
	elseif gemInstance.corruptLevel == -1 then
		return 4  -- -1 to Gem Level
	elseif gemInstance.corrupted == true then
		return 3  -- Corrupted
	else
		return 1  -- Not Corrupted
	end
end

function SkillsTabClass:LoadSkill(node, skillSetId)
	if node.elem ~= "Skill" then
		return
	end

	local socketGroup = { }
	socketGroup.enabled = node.attrib.active == "true" or node.attrib.enabled == "true"
	socketGroup.includeInFullDPS = node.attrib.includeInFullDPS and node.attrib.includeInFullDPS == "true"
	socketGroup.groupCount = tonumber(node.attrib.groupCount)
	socketGroup.label = node.attrib.label
	socketGroup.slot = node.attrib.slot
	socketGroup.source = node.attrib.source
	socketGroup.mainActiveSkill = tonumber(node.attrib.mainActiveSkill) or 1
	socketGroup.mainActiveSkillCalcs = tonumber(node.attrib.mainActiveSkillCalcs) or 1
	socketGroup.gemList = { }
	for _, child in ipairs(node) do
		local gemInstance = { }
		gemInstance.nameSpec = sanitiseText(child.attrib.nameSpec or "")
		if child.attrib.gemId then
			local gemData
			local possibleVariants = self.build.data.gemsByGameId[child.attrib.gemId]
			if possibleVariants then
				-- If it is a known gem, try to determine which variant is used
				if child.attrib.variantId and possibleVariants[child.attrib.variantId] then
					-- New save format from 3.23 that stores the specific variation (transfiguration)
					gemData = possibleVariants[child.attrib.variantId]
				else
					-- If a gem has changed names between updates, assumed it's the first gem in the list
					for _, variant in pairs(possibleVariants) do
						gemData = variant
						break
					end
				end
			end
			if gemData then
				gemInstance.gemId = gemData.id
				gemInstance.skillId = gemData.grantedEffectId
				if gemData.nameSpec then
					gemInstance.nameSpec = gemData.nameSpec
				end
			end
		elseif child.attrib.skillId then
			local grantedEffect = self.build.data.skills[child.attrib.skillId]
			if grantedEffect then
				gemInstance.gemId = self.build.data.gemForSkill[grantedEffect]
				gemInstance.skillId = grantedEffect.id
				gemInstance.nameSpec = grantedEffect.name
			end
		end
		gemInstance.level = tonumber(child.attrib.level)
		gemInstance.quality = tonumber(child.attrib.quality)
		gemInstance.enabled = not child.attrib.enabled and true or child.attrib.enabled == "true"
		gemInstance.enableGlobal1 = not child.attrib.enableGlobal1 or child.attrib.enableGlobal1 == "true"
		gemInstance.enableGlobal2 = child.attrib.enableGlobal2 == "true"
		gemInstance.count = tonumber(child.attrib.count) or 1
		gemInstance.statSet = { index = tonumber(child.attrib.statSetIndex) or 1 }
		gemInstance.statSetCalcs = { index = tonumber(child.attrib.statSetIndexCalcs) or 1 }
		gemInstance.skillPart = tonumber(child.attrib.skillPart)
		gemInstance.skillPartCalcs = tonumber(child.attrib.skillPartCalcs)
		gemInstance.skillStageCount = tonumber(child.attrib.skillStageCount)
		gemInstance.skillStageCountCalcs = tonumber(child.attrib.skillStageCountCalcs)
		gemInstance.skillMineCount = tonumber(child.attrib.skillMineCount)
		gemInstance.skillMineCountCalcs = tonumber(child.attrib.skillMineCountCalcs)
		gemInstance.skillMinion = child.attrib.skillMinion
		gemInstance.skillMinionCalcs = child.attrib.skillMinionCalcs
		gemInstance.skillMinionItemSet = tonumber(child.attrib.skillMinionItemSet)
		gemInstance.skillMinionItemSetCalcs = tonumber(child.attrib.skillMinionItemSetCalcs)
		gemInstance.skillMinionSkill = tonumber(child.attrib.skillMinionSkill)
		gemInstance.skillMinionSkillCalcs = tonumber(child.attrib.skillMinionSkillCalcs)
		gemInstance.corrupted = child.attrib.corrupted == "true"
		gemInstance.corruptLevel = tonumber(child.attrib.corruptLevel) or 0
		gemInstance.statSet = { }
		gemInstance.statSetCalcs = { }
		gemInstance.skillMinionSkillStatSetIndexLookup = { }
		gemInstance.skillMinionSkillStatSetIndexLookupCalcs = { }
		for _, child in ipairs(child) do
			if child.elem == "StatSetIndex" and child.attrib.grantedEffect then
				gemInstance.statSet[child.attrib.grantedEffect] = tonumber(child.attrib.index)
			elseif child.elem == "StatSetCalcsIndex" and child.attrib.grantedEffect then
				gemInstance.statSetCalcs[child.attrib.grantedEffect] = tonumber(child.attrib.index)
			elseif child.elem == "MinionSkillIndexLookup" and child.attrib.grantedEffect then
				gemInstance.skillMinionSkillStatSetIndexLookup[child.attrib.grantedEffect] = { }
				for _, map in ipairs(child) do
					gemInstance.skillMinionSkillStatSetIndexLookup[child.attrib.grantedEffect][tonumber(map.attrib.skillIndex)] = tonumber(map.attrib.statSetIndex)
				end
			elseif child.elem == "MinionSkillIndexLookupCalcs" and child.attrib.grantedEffect then
				gemInstance.skillMinionSkillStatSetIndexLookupCalcs[child.attrib.grantedEffect] = { }
				for _, map in ipairs(child) do
					gemInstance.skillMinionSkillStatSetIndexLookupCalcs[child.attrib.grantedEffect][tonumber(map.attrib.skillIndex)] = tonumber(map.attrib.statSetIndex)
				end
			end
		end

		t_insert(socketGroup.gemList, gemInstance)
	end
	if node.attrib.skillPart and socketGroup.gemList[1] then
		socketGroup.gemList[1].skillPart = tonumber(node.attrib.skillPart)
	end
	self:ProcessSocketGroup(socketGroup)
	t_insert(self.skillSets[skillSetId].socketGroupList, socketGroup)
end

function SkillsTabClass:Load(xml, fileName)
	self.activeSkillSetId = 0
	self.skillSets = { }
	self.skillSetOrderList = { }
	-- Handle legacy configuration settings when loading `defaultGemLevel`
	if xml.attrib.matchGemLevelToCharacterLevel == "true" then
		self.controls.defaultLevel:SelByValue("characterLevel", "gemLevel")
	elseif type(xml.attrib.defaultGemLevel) == "string" and tonumber(xml.attrib.defaultGemLevel) == nil then
		self.controls.defaultLevel:SelByValue(xml.attrib.defaultGemLevel, "gemLevel")
	else
		self.controls.defaultLevel:SelByValue("normalMaximum", "gemLevel")
	end
	self.defaultGemLevel = self.controls.defaultLevel:GetSelValueByKey("gemLevel")
	self.defaultGemQuality = m_max(m_min(tonumber(xml.attrib.defaultGemQuality) or 0, 23), 0)
	self.controls.defaultQuality:SetText(self.defaultGemQuality or "")
	if xml.attrib.sortGemsByDPS then
		self.sortGemsByDPS = xml.attrib.sortGemsByDPS == "true"
	end
	self.controls.sortGemsByDPS.state = self.sortGemsByDPS
	if xml.attrib.showLegacyGems then
		self.showLegacyGems = xml.attrib.showLegacyGems == "true"
	end
	self.controls.showLegacyGems.state = self.showLegacyGems
	self.controls.showSupportGemTypes:SelByValue(xml.attrib.showSupportGemTypes or "ALL", "show")
	self.controls.sortGemsByDPSFieldControl:SelByValue(xml.attrib.sortGemsByDPSField or "CombinedDPS", "type")
	self.showSupportGemTypes = self.controls.showSupportGemTypes:GetSelValueByKey("show")
	self.sortGemsByDPSField = self.controls.sortGemsByDPSFieldControl:GetSelValueByKey("type")
	for _, node in ipairs(xml) do
		if node.elem == "Skill" then
			-- Old format, initialize skill sets if needed
			if not self.skillSetOrderList[1] then
				self.skillSetOrderList[1] = 1
				self:CreateSkillSet(1)
			end
			self:LoadSkill(node, 1)
		end

		if node.elem == "SkillSet" then
			local skillSet = self:CreateSkillSet(tonumber(node.attrib.id))
			skillSet.title = node.attrib.title
			t_insert(self.skillSetOrderList, skillSet.id)
			for _, subNode in ipairs(node) do
				self:LoadSkill(subNode, skillSet.id)
			end
		end
	end
	self:SetActiveSkillSet(tonumber(xml.attrib.activeSkillSet) or 1)
	self:ResetUndo()
end

function SkillsTabClass:Save(xml)
	xml.attrib = {
		activeSkillSet = tostring(self.activeSkillSetId),
		defaultGemLevel = self.defaultGemLevel,
		defaultGemQuality = tostring(self.defaultGemQuality),
		sortGemsByDPS = tostring(self.sortGemsByDPS),
		showSupportGemTypes = self.showSupportGemTypes,
		sortGemsByDPSField = self.sortGemsByDPSField,
		showLegacyGems = tostring(self.showLegacyGems),
	}
	for _, skillSetId in ipairs(self.skillSetOrderList) do
		local skillSet = self.skillSets[skillSetId]
		local child = { elem = "SkillSet", attrib = { id = tostring(skillSetId), title = skillSet.title } }
		t_insert(xml, child)

		for _, socketGroup in ipairs(skillSet.socketGroupList) do
			local node = { elem = "Skill", attrib = {
				enabled = tostring(socketGroup.enabled),
				includeInFullDPS = tostring(socketGroup.includeInFullDPS),
				groupCount = socketGroup.groupCount ~= nil and tostring(socketGroup.groupCount),
				label = socketGroup.label,
				slot = socketGroup.slot,
				source = socketGroup.source,
				mainActiveSkill = tostring(socketGroup.mainActiveSkill),
				mainActiveSkillCalcs = tostring(socketGroup.mainActiveSkillCalcs),
			} }
			for _, gemInstance in ipairs(socketGroup.gemList) do
				local gemInfo =  { elem = "Gem", attrib = {
					nameSpec = gemInstance.nameSpec,
					skillId = gemInstance.skillId,
					gemId = gemInstance.gemData and gemInstance.gemData.gameId,
					variantId = gemInstance.gemData and gemInstance.gemData.variantId,
					level = tostring(gemInstance.level),
					quality = tostring(gemInstance.quality),
					enabled = tostring(gemInstance.enabled),
					enableGlobal1 = tostring(gemInstance.enableGlobal1),
					enableGlobal2 = tostring(gemInstance.enableGlobal2),
					count = tostring(gemInstance.count),
					statSetIndex = gemInstance.statSet and tostring(gemInstance.statSet.index),
					statSetIndexCalcs = gemInstance.statSetCalcs and tostring(gemInstance.statSetCalcs.index),
					skillPart = gemInstance.skillPart and tostring(gemInstance.skillPart),
					skillPartCalcs = gemInstance.skillPartCalcs and tostring(gemInstance.skillPartCalcs),
					skillStageCount = gemInstance.skillStageCount and tostring(gemInstance.skillStageCount),
					skillStageCountCalcs = gemInstance.skillStageCountCalcs and tostring(gemInstance.skillStageCountCalcs),
					skillMineCount = gemInstance.skillMineCount and tostring(gemInstance.skillMineCount),
					skillMineCountCalcs = gemInstance.skillMineCountCalcs and tostring(gemInstance.skillMineCountCalcs),
					skillMinion = gemInstance.skillMinion,
					skillMinionCalcs = gemInstance.skillMinionCalcs,
					skillMinionItemSet = gemInstance.skillMinionItemSet and tostring(gemInstance.skillMinionItemSet),
					skillMinionItemSetCalcs = gemInstance.skillMinionItemSetCalcs and tostring(gemInstance.skillMinionItemSetCalcs),
					skillMinionSkill = gemInstance.skillMinionSkill and tostring(gemInstance.skillMinionSkill),
					skillMinionSkillCalcs = gemInstance.skillMinionSkillCalcs and tostring(gemInstance.skillMinionSkillCalcs),
					corrupted = tostring(gemInstance.corrupted),
					corruptLevel = tostring(gemInstance.corruptLevel),
				} }
				if gemInstance.statSet then
					for grantedEffect, index in pairs(gemInstance.statSet) do
						t_insert(gemInfo, { elem = "StatSetIndex", attrib = { grantedEffect = grantedEffect, index = tostring(index)}})
					end
				end
				if gemInstance.statSetCalcs then
					for grantedEffect, index in pairs(gemInstance.statSetCalcs) do
						t_insert(gemInfo, { elem = "StatSetCalcsIndex", attrib = { grantedEffect = grantedEffect, index = tostring(index)}})
					end
				end
				if gemInstance.skillMinionSkillStatSetIndexLookup then
					for grantedEffect, map in pairs(gemInstance.skillMinionSkillStatSetIndexLookup) do
						local minionSkillStatSetIndexLookup = { elem = "MinionSkillIndexLookup", attrib = { grantedEffect = grantedEffect }}
						for k,v in pairs(map) do
							t_insert(minionSkillStatSetIndexLookup, { elem = "MinionSkillIndexMap",  attrib = {
								skillIndex = tostring(k),
								statSetIndex = tostring(v)
							} } )
						end
						t_insert(gemInfo, minionSkillStatSetIndexLookup)
					end
				end
				if gemInstance.skillMinionSkillStatSetIndexLookupCalcs then
					for grantedEffect, map in pairs(gemInstance.skillMinionSkillStatSetIndexLookupCalcs) do
						local minionSkillStatSetIndexLookupCalcs = { elem = "MinionSkillIndexLookupCalcs", attrib = { grantedEffect = grantedEffect } }
						for k,v in pairs(map) do
							t_insert(minionSkillStatSetIndexLookupCalcs, { elem = "MinionSkillIndexMap",  attrib = {
								skillIndex = tostring(k),
								statSetIndex = tostring(v)
							} } )
						end
						t_insert(gemInfo, minionSkillStatSetIndexLookupCalcs)
					end
				end
				t_insert(node, gemInfo)
			end
			t_insert(child, node)
		end
	end
end

function SkillsTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height
	self.controls.scrollBarH.width = viewPort.width
	self.controls.scrollBarH.x = viewPort.x
	self.controls.scrollBarH.y = viewPort.y + viewPort.height - 18

	do
		local maxX = self.controls.gemCountHeader:GetPos() + self.controls.gemCountHeader:GetSize() + 25
		local contentWidth = maxX - self.x
		self.controls.scrollBarH:SetContentDimension(contentWidth, viewPort.width)
	end
	self.x = self.x - self.controls.scrollBarH.offset

	for _, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "z" and IsKeyDown("CTRL") then
				self:Undo()
				self.build.buildFlag = true
			elseif event.key == "y" and IsKeyDown("CTRL") then
				self:Redo()
				self.build.buildFlag = true
			elseif event.key == "v" and IsKeyDown("CTRL") then
				self:PasteSocketGroup()
			end
		end
	end
	self:ProcessControlsInput(inputEvents, viewPort)
	for _, event in ipairs(inputEvents) do
		if event.type == "KeyUp" then
			if self.controls.scrollBarH:IsScrollDownKey(event.key) then
				self.controls.scrollBarH:Scroll(1)
			elseif self.controls.scrollBarH:IsScrollUpKey(event.key) then
				self.controls.scrollBarH:Scroll(-1)
			end
		end
	end

	main:DrawBackground(viewPort)

	local newSetList = { }
	for index, skillSetId in ipairs(self.skillSetOrderList) do
		local skillSet = self.skillSets[skillSetId]
		t_insert(newSetList, skillSet.title or "Default")
		if skillSetId == self.activeSkillSetId then
			self.controls.setSelect.selIndex = index
		end
	end
	self.controls.setSelect:SetList(newSetList)

	if main.portraitMode then
		self.anchorGroupDetail:SetAnchor("TOPLEFT",self.controls.optionSection,"BOTTOMLEFT", 0, 20)
	else
		self.anchorGroupDetail:SetAnchor("TOPLEFT",self.controls.groupList,"TOPRIGHT", 20, 0)
	end

	self:UpdateGemSlots()

	self:DriveSupportSolver()

	self:DrawControls(viewPort)
end

-- Comma-separated list of currently-enabled supports in the display group.
-- Drives the read-only "Locked:" label on the solver panel.
function SkillsTabClass:FormatLockedSupportsLabel()
	if not self.displayGroup then
		return ""
	end
	local names = { }
	for _, gem in ipairs(self.displayGroup.gemList) do
		local ge = gem.gemData and gem.gemData.grantedEffect
		if ge and ge.support and gem.enabled then
			t_insert(names, gem.gemData.name)
		end
	end
	if #names == 0 then
		return "^x808080(none)"
	end
	return "^7" .. table.concat(names, ", ")
end

-- Comma-separated list of the most recent solver suggestions for the display
-- group. Drives the read-only "Suggested:" label on the solver panel.
function SkillsTabClass:FormatSuggestedSupportsLabel()
	local p = self.solveSupportsPreview
	if not p or p.group ~= self.displayGroup or not p.picks or #p.picks == 0 then
		return "^x808080(click Solve to preview picks)"
	end
	local names = { }
	for _, pick in ipairs(p.picks) do
		t_insert(names, pick.name)
	end
	return "^7" .. table.concat(names, ", ")
end

-- Kick off a support gem solver run for the currently-displayed socket group.
-- Captures the group reference at click time so a mid-run group change doesn't
-- redirect the solver's mutations onto a different group.
function SkillsTabClass:SolveSupports()
	if self.solveSupportsCoroutine then
		return
	end
	if not self.displayGroup or self.displayGroup.source then
		return
	end
	local count = self.solveSupportsCount or 0
	if count < 1 then
		return
	end
	local group = self.displayGroup
	local metricEntry = supportGemSolver.metricList[self.solveSupportsMetricIndex or 1]
	self.solveSupportsGroup = group
	self.solveSupportsPreview = nil
	self.solveSupportsStatusText = "^7Starting..."
	-- Make sure the misc calculator and displaySkillListCalcs reflect current
	-- state. If the build is flagged dirty (or has never been built), fold the
	-- rebuild into this click instead of waiting for the next frame — the
	-- solver needs a resolved active skill and a callable miscCalculator on
	-- its very first iteration. Mirrors what Build:OnFrame does at line 1144.
	if self.build.buildFlag or not (self.build.calcsTab.miscCalculator and self.build.calcsTab.miscCalculator[1]) then
		wipeGlobalCache()
		self.build.buildFlag = false
		self.build.outputRevision = (self.build.outputRevision or 0) + 1
		self.build.calcsTab:BuildOutput()
		self.build:RefreshStatList()
	end
	self.solveSupportsCoroutine = coroutine.create(function()
		return supportGemSolver.solve(self.build, group, {
			metric = metricEntry.key,
			useFullDPS = metricEntry.useFullDPS,
			treatDisabledAsEmpty = false,
			targetCount = count,
			progressFn = function(state)
				self.solveSupportsStatusText = string.format("^7Solving... %d evaluated, best %s: %s",
					state.evaluated, metricEntry.label, formatNumSep(string.format("%.0f", state.bestScore or 0)))
			end,
		})
	end)
end

-- Drive the active solver coroutine one step per frame. Mirrors the pattern
-- used by CalcsTab:BuildPower for the power-builder coroutine. Result lands in
-- self.solveSupportsPreview — nothing is applied to the gemList until the user
-- hits "Apply (add-only)".
function SkillsTabClass:DriveSupportSolver()
	if not self.solveSupportsCoroutine then
		return
	end
	local ok, ret = coroutine.resume(self.solveSupportsCoroutine)
	if not ok then
		if launch.devMode then
			error(ret)
		end
		self.solveSupportsStatusText = "^1Solver error: " .. tostring(ret)
		self.solveSupportsCoroutine = nil
		self.solveSupportsGroup = nil
		return
	end
	if coroutine.status(self.solveSupportsCoroutine) ~= "dead" then
		return
	end
	local result = ret
	local group = self.solveSupportsGroup
	self.solveSupportsCoroutine = nil
	self.solveSupportsGroup = nil
	if not result or not result.ok then
		self.solveSupportsStatusText = "^1" .. ((result and result.error) or "Solver failed.")
		return
	end
	local picks = result.picks or { }
	self.solveSupportsPreview = {
		group = group,
		picks = picks,
		metric = result.metric,
		baseScore = result.baseScore,
		bestScore = result.bestScore,
		evaluated = result.evaluated,
	}
	local delta = (result.bestScore or 0) - (result.baseScore or 0)
	local pct = (result.baseScore and result.baseScore > 0) and (delta / result.baseScore) * 100 or 0
	self.solveSupportsStatusText = string.format("^7Preview ready (%d picks): %s %+s (%+.1f%%) — %d evals",
		#picks,
		supportGemSolver.metricList[self.solveSupportsMetricIndex or 1].label,
		formatNumSep(string.format("%.0f", delta)),
		pct,
		result.evaluated)
end

-- Copy the most recent preview picks into the display group's gemList.
-- Fills empty slots first (in order), then appends new slots for any remaining
-- picks. Never overwrites a slot that already has a gemId/gemData, regardless
-- of enabled state.
function SkillsTabClass:ApplyPreviewSupports()
	local preview = self.solveSupportsPreview
	if not preview or preview.group ~= self.displayGroup then
		return
	end
	local group = self.displayGroup
	if not group or group.source then
		return
	end
	local picks = preview.picks or { }
	if #picks == 0 then
		return
	end
	local appliedCount = 0
	local pickIdx = 1
	-- Pass 1: fill existing empty slots.
	for i, gem in ipairs(group.gemList) do
		if pickIdx > #picks then break end
		if not gem.gemId and not gem.gemData and not (gem.nameSpec and gem.nameSpec:match("%S")) then
			local pick = picks[pickIdx]
			gem.gemId = pick.gemData.id
			gem.skillId = pick.gemData.grantedEffectId
			gem.gemData = pick.gemData
			gem.nameSpec = pick.gemData.name
			gem.grantedEffect = nil
			gem.errMsg = nil
			gem.displayEffect = nil
			gem.enabled = true
			if gem.enableGlobal1 == nil then gem.enableGlobal1 = true end
			if gem.enableGlobal2 == nil then gem.enableGlobal2 = false end
			gem.count = gem.count or 1
			gem.level = pick.level or self:ProcessGemLevel(pick.gemData) or pick.gemData.naturalMaxLevel or 1
			gem.naturalMaxLevel = pick.gemData.naturalMaxLevel
			gem.quality = pick.quality or self.defaultGemQuality or 0
			pickIdx = pickIdx + 1
			appliedCount = appliedCount + 1
		end
	end
	-- Pass 2: append fresh slots for whatever's left.
	while pickIdx <= #picks do
		local pick = picks[pickIdx]
		local newGem = {
			gemId = pick.gemData.id,
			skillId = pick.gemData.grantedEffectId,
			gemData = pick.gemData,
			nameSpec = pick.gemData.name,
			enabled = true,
			enableGlobal1 = true,
			enableGlobal2 = false,
			count = 1,
			level = pick.level or self:ProcessGemLevel(pick.gemData) or pick.gemData.naturalMaxLevel or 1,
			quality = pick.quality or self.defaultGemQuality or 0,
			naturalMaxLevel = pick.gemData.naturalMaxLevel,
		}
		t_insert(group.gemList, newGem)
		pickIdx = pickIdx + 1
		appliedCount = appliedCount + 1
	end
	-- Refresh resolved gem data so colour/reqs/etc. are filled in for the new
	-- gems, push values into the slot widgets, then commit an undo state.
	self:ProcessSocketGroup(group)
	self:UpdateGemSlots()
	for index, gemInstance in ipairs(group.gemList) do
		local slot = self.gemSlots[index]
		if slot then
			slot.nameSpec:SetText(gemInstance.nameSpec or "")
			slot.level:SetText(gemInstance.level)
			slot.quality:SetText(gemInstance.quality)
			slot.enabled.state = gemInstance.enabled
			slot.enableGlobal1.state = gemInstance.enableGlobal1
			slot.enableGlobal2.state = gemInstance.enableGlobal2
			slot.count:SetText(gemInstance.count or 1)
		end
	end
	self.solveSupportsPreview = nil
	self.solveSupportsStatusText = string.format("^7Applied %d support(s).", appliedCount)
	self:AddUndoState()
	self.build.buildFlag = true
end

function SkillsTabClass:CopySocketGroup(socketGroup)
	local skillText = ""
	if socketGroup.label and socketGroup.label:match("%S") then
		skillText = skillText .. "Label: " .. socketGroup.label .. "\r\n"
	end
	if socketGroup.slot then
		skillText = skillText .. "Slot: " .. socketGroup.slot .. "\r\n"
	end
	for _, gemInstance in ipairs(socketGroup.gemList) do
		skillText = skillText .. string.format(
			"%s %d/%d %s %s%s\r\n",
			gemInstance.nameSpec,
			gemInstance.level,
			gemInstance.quality,
			gemInstance.enabled and "" or "DISABLED",
			string.format("%g", gemInstance.count or 1),
			gemInstance.corrupted and (" C" .. ((gemInstance.corruptLevel or 0) ~= 0 and ((gemInstance.corruptLevel > 0 and "+" or "") .. gemInstance.corruptLevel) or "")) or ""
		)
	end
	Copy(skillText)
end

function SkillsTabClass:PasteSocketGroup(testInput)
	local skillText = sanitiseText(Paste() or testInput)
	if skillText then
		local newGroup = { label = "", enabled = true, gemList = { } }
		local label = skillText:match("Label: (%C+)")
		if label then
			newGroup.label = label
		end
		local slot = skillText:match("Slot: (%C+)")
		if slot then
			newGroup.slot = slot
		end
		for line in skillText:gmatch("([^\r\n]+)") do
			local nameSpec, level, quality, state, count, cFlag, cLevel =
				line:match("^([ %a':]+) (%d+)/(%d+)%s*(%u*)%s+([%d%.]+)%s*(C?)([+%-]?%d*)%s*$")
			if nameSpec then
				local skillMinion = nil
				local skillMinionCalcs = nil
				local minionName = nil
				local minionList = nil

				if nameSpec:find("Spectre") then
					minionName = nameSpec:match(": (.+)")
					nameSpec = "Summon Spectre"
					minionList = self.build.spectreList
				elseif nameSpec:find("Companion") then
					minionName = nameSpec:match(": (.+)")
					nameSpec = "Tamed Companion"
					minionList = self.build.beastList
				end

				-- Search for the minion if we found a spectre or companion
				if minionName then
					for id, spectre in pairs(data.spectres) do
						if spectre.name == minionName then
							if not isValueInArray(minionList, id) then
								t_insert(minionList, id)
							end
							skillMinion = id
							skillMinionCalcs = id
							break
						end
					end
				end

				t_insert(newGroup.gemList, {
					nameSpec = nameSpec,
					level = tonumber(level) or 20,
					quality = tonumber(quality) or 0,
					enabled = state ~= "DISABLED",
					count = tonumber(count) or 1,
					corrupted = cFlag == "C",
					corruptLevel = tonumber(cLevel) or 0,
					enableGlobal1 = true,
					enableGlobal2 = true,
					skillMinion = skillMinion,
					skillMinionCalcs = skillMinionCalcs
				})
			end
		end
		if #newGroup.gemList > 0 then
			t_insert(self.socketGroupList, newGroup)
			self.controls.groupList.selIndex = #self.socketGroupList
			self.controls.groupList.selValue = newGroup
			self:SetDisplayGroup(newGroup)
			self:AddUndoState()
			self.build.buildFlag = true
		end
	end
end

-- Create the controls for editing the gem at a given index
function SkillsTabClass:CreateGemSlot(index)
	local slot = { }
	self.gemSlots[index] = slot

	local function deleteGem()
		t_remove(self.displayGroup.gemList, index)
		for index2 = index, #self.displayGroup.gemList do
			-- Update the other gem slot controls
			local gemInstance = self.displayGroup.gemList[index2]
			self.gemSlots[index2].nameSpec:SetText(gemInstance.nameSpec)
			self.gemSlots[index2].level:SetText(gemInstance.level)
			self.gemSlots[index2].quality:SetText(gemInstance.quality)
			self.gemSlots[index2].enabled.state = gemInstance.enabled
			self.gemSlots[index2].enableGlobal1.state = gemInstance.enableGlobal1
			self.gemSlots[index2].enableGlobal2.state = gemInstance.enableGlobal2
			self.gemSlots[index2].count:SetText(gemInstance.count or 1)
			self.gemSlots[index2].corruptLevel.selIndex = self:GetCorruptIndex(gemInstance)
		end
		self:AddUndoState()
		self.build.buildFlag = true
	end
	-- Delete gem
	slot.delete = new("ButtonControl", nil, {0, 0, 20, 20}, "x", function()
		return deleteGem()
	end)
	if index == 1 then
		slot.delete:SetAnchor("TOPLEFT", self.anchorGemSlots, "TOPLEFT", 0, 0)
	else
		local prevSlot = self.gemSlots[index-1]
		slot.delete:SetAnchor("TOPLEFT", prevSlot.delete, "BOTTOMLEFT", 0, function()
			return (prevSlot.enableGlobal1:IsShown() or prevSlot.enableGlobal2:IsShown()) and 24 or 2
		end)
	end
	slot.delete.shown = function()
		return index <= #self.displayGroup.gemList + 1 and self.displayGroup.source == nil
	end
	slot.delete.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	slot.delete.tooltipText = "Remove this gem."
	self.controls["gemSlot"..index.."Delete"] = slot.delete

	-- Gem name specification
	slot.nameSpec = new("GemSelectControl", { "LEFT", slot.delete, "RIGHT" }, { 2, 0, 300, 20 }, self, index, function(gemId, addUndo, focusLost, bufMatchesGem)
		if not self.displayGroup then
			return
		end
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			if not gemId then
				return
			end
			gemInstance = {
				nameSpec = "",
				level = 1,
				quality = self.defaultGemQuality or 0,
				enabled = true,
				enableGlobal1 = true,
				enableGlobal2 = true,
				count = 1,
				new = true,
				corrupted = false,
				corruptLevel = 0,
			}
			self.displayGroup.gemList[index] = gemInstance
			slot.level:SetText(gemInstance.level)
			slot.quality:SetText(gemInstance.quality)
			slot.corruptLevel.selIndex = self:GetCorruptIndex(gemInstance)
			slot.enabled.state = true
			slot.enableGlobal1.state = true
			slot.enableGlobal2.state = true
			slot.count:SetText(gemInstance.count)
		elseif focusLost and not bufMatchesGem then
			return deleteGem()
		elseif gemId == gemInstance.gemId then
			if addUndo then
				self:AddUndoState()
			end
			if bufMatchesGem then
				self.build.buildFlag = true
			end
			return
		end
		gemInstance.gemId = gemId
		gemInstance.skillId = nil
		self:ProcessSocketGroup(self.displayGroup)
		-- New gems need to be constrained by ProcessGemLevel
		gemInstance.level = self:ProcessGemLevel(gemInstance.gemData)
		gemInstance.naturalMaxLevel = gemInstance.level
		-- Gem changed, update the list and default the quality id
		slot.level:SetText(gemInstance.level)
		if self.defaultCorruptionLevel == 1 then
			slot.corruptLevel.selIndex = 2
			gemInstance.corrupted = true
			gemInstance.corruptLevel = 1
		end
		slot.count:SetText(gemInstance.count or 1)
		if addUndo then
			self:AddUndoState()
		end
		if bufMatchesGem then
			self.build.buildFlag = true
		end
	end, true)
	slot.nameSpec:AddToTabGroup(self.controls.groupLabel)
	self.controls["gemSlot"..index.."Name"] = slot.nameSpec

	-- Gem level
	slot.level = new("EditControl", { "LEFT", slot.nameSpec, "RIGHT" }, { 2, 0, 60, 20 }, nil, nil, "%D", 2, function(buf)
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			gemInstance = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true, enableGlobal1 = true, enableGlobal2 = true, count = 1, new = true, corruptLevel = 0, corrupted = false }
			self.displayGroup.gemList[index] = gemInstance
			slot.quality:SetText(gemInstance.quality)
			slot.enabled.state = true
			slot.enableGlobal1.state = true
			slot.count:SetText(gemInstance.count)
			slot.corruptLevel = self:GetCorruptIndex(gemInstance)
		end
		gemInstance.level = tonumber(buf) or self.displayGroup.gemList[index].naturalMaxLevel or self:ProcessGemLevel(gemInstance.gemData) or 20
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.level:AddToTabGroup(self.controls.groupLabel)
	slot.level.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	self.controls["gemSlot"..index.."Level"] = slot.level

	-- Gem quality
	slot.quality = new("EditControl", {"LEFT",slot.level,"RIGHT"}, {2, 0, 60, 20}, nil, nil, "%D", 2, function(buf)
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			gemInstance = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true, enableGlobal1 = true, enableGlobal2 = true, count = 1, new = true, corruptLevel = 0, corrupted = false }
			self.displayGroup.gemList[index] = gemInstance
			slot.level:SetText(gemInstance.level)
			slot.enabled.state = true
			slot.enableGlobal1.state = true
			slot.count:SetText(gemInstance.count)
			slot.corruptLevel = self:GetCorruptIndex(gemInstance)
		end
		gemInstance.quality = tonumber(buf) or self.defaultGemQuality or 0
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.quality.tooltipFunc = function(tooltip)
		-- Reset the tooltip
		tooltip:Clear()
		-- Get the gem instance from the skills
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			return
		end
		local gemData = gemInstance.gemData
		-- gem data may not be initialized yet, or the quality may be nil, which happens when just floating over the dropdown
		if not gemData then
			return
		end
		-- Function for both granted effect and secondary such as vaal
		local addQualityLines = function(qualityList, grantedEffect)
			if #qualityList > 0 then
				if grantedEffect.name == "" then
					tooltip:AddLine(18, colorCodes.GEM..grantedEffect.statSets[1].label)
				else
					tooltip:AddLine(18, colorCodes.GEM..grantedEffect.name)
				end
				-- Hardcoded to use 20% quality instead of grabbing from gem, this is for consistency and so we always show something
				tooltip:AddLine(16, colorCodes.NORMAL.."At +20% Quality:")
				for k, qual in pairs(qualityList) do
					-- Do the stats one at a time because we're not guaranteed to get the descriptions in the same order we look at them here
					local stats = { }
					stats[qual[1]] = qual[2] * 20
					local descriptions = self.build.data.describeStats(stats, grantedEffect.statSets[1].statDescriptionScope, true)
					-- line may be nil if the value results in no line due to not being enough quality
					for _, line in ipairs(descriptions) do
						if line then
							-- Check if we have a handler for the mod in the gem's statMap or in the shared stat map for skills
							if grantedEffect.statSets[1].statMap[qual[1]] or self.build.data.skillStatMap[qual[1]] then
								tooltip:AddLine(16, colorCodes.MAGIC..line)
							else
								local line = colorCodes.UNSUPPORTED..line
								line = main.notSupportedModTooltips and (line .. main.notSupportedTooltipText) or line
								tooltip:AddLine(16, line)
							end
						end
					end
				end
			end
		end
		-- Check if there is a quality of this type for the effect
		-- Currently only checks the first 2 additionalGrantedEffects. Will need to fix if gems ever add more
		if gemData and gemData.grantedEffect.qualityStats and #gemData.grantedEffect.qualityStats > 0 then
			local qualityTable = gemData.grantedEffect.qualityStats
			addQualityLines(qualityTable, gemData.grantedEffect)
		end
		if gemData and gemData.additionalGrantedEffects[1] and gemData.additionalGrantedEffects[1].qualityStats and #gemData.additionalGrantedEffects[1].qualityStats > 0 then
			local qualityTable = gemData.additionalGrantedEffects[1].qualityStats
			tooltip:AddSeparator(10)
			addQualityLines(qualityTable, gemData.additionalGrantedEffects[1])
		end
		if gemData and gemData.additionalGrantedEffects[2] and gemData.additionalGrantedEffects[2].qualityStats and #gemData.additionalGrantedEffects[2].qualityStats > 0  then
			local qualityTable = gemData.additionalGrantedEffects[2].qualityStats
			tooltip:AddSeparator(10)
			addQualityLines(qualityTable, gemData.additionalGrantedEffects[2])
		end
		-- Add stat comparisons for hovered quality (based on set quality)
		if gemData and (gemData.grantedEffect.qualityStats or (gemData.additionalGrantedEffects[1] and gemData.additionalGrantedEffects[1].qualityStats or gemData.additionalGrantedEffects[2] and gemData.additionalGrantedEffects[2].qualityStats)) and self.displayGroup.gemList[index] then
			local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator(self.build)
			if calcFunc then
				local storedQuality = self.displayGroup.gemList[index].quality
				self.displayGroup.gemList[index].quality = 20
				local output = calcFunc()
				self.displayGroup.gemList[index].quality = storedQuality
				tooltip:AddSeparator(10)
				self.build:AddStatComparesToTooltip(tooltip, calcBase, output, "^7Setting to 20 quality will give you:")
			end
		end
	end
	slot.quality:AddToTabGroup(self.controls.groupLabel)
	slot.quality.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	self.controls["gemSlot"..index.."Quality"] = slot.quality

	-- Enable gem
	slot.enabled = new("CheckBoxControl", {"LEFT",slot.quality,"RIGHT"}, {18, 0, 20}, nil, function(state)
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			gemInstance = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true, enableGlobal1 = true, enableGlobal2 = true, count = 1, new = true, corruptLevel = 0, corrupted = false }
			self.displayGroup.gemList[index] = gemInstance
			slot.level:SetText(gemInstance.level)
			slot.quality:SetText(gemInstance.quality)
			slot.count:SetText(gemInstance.count)
			slot.corruptLevel = self:GetCorruptIndex(gemInstance)
		end
		if not gemInstance.gemData.vaalGem then
			slot.enableGlobal1.state = true
			gemInstance.enableGlobal1 = true
			slot.enableGlobal2.state = true
			gemInstance.enableGlobal2 = true
		end
		gemInstance.enabled = state
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.enabled.tooltipFunc = function(tooltip)
		if tooltip:CheckForUpdate(self.build.outputRevision, self.displayGroup) then
			if self.displayGroup.gemList[index] then
				local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator(self.build)
				if calcFunc then
					self.displayGroup.gemList[index].enabled = not self.displayGroup.gemList[index].enabled
					local output = calcFunc()
					self.displayGroup.gemList[index].enabled = not self.displayGroup.gemList[index].enabled
					self.build:AddStatComparesToTooltip(tooltip, calcBase, output, self.displayGroup.gemList[index].enabled and "^7Disabling this gem will give you:" or "^7Enabling this gem will give you:")
				end
			end
		end
	end
	slot.enabled.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	self.controls["gemSlot"..index.."Enable"] = slot.enabled

	-- Count gem
	slot.count = new("EditControl", {"LEFT",slot.enabled,"RIGHT"}, {18, 0, 80, 20}, nil, nil, "^%d.", 5, function(buf)
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			gemInstance = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true, enableGlobal1 = true, count = 1, new = true, corruptLevel = 0, corrupted = false }
			self.displayGroup.gemList[index] = gemInstance
			slot.level:SetText(gemInstance.level)
			slot.quality:SetText(gemInstance.quality)
			slot.enabled.state = true
			slot.enableGlobal1.state = true
			slot.corruptLevel = self:GetCorruptIndex(gemInstance)
		end
		gemInstance.count = tonumber(buf) or 1
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.count.shown = function()
		local gemInstance = self.displayGroup and self.displayGroup.gemList[index]
		if gemInstance then
			local grantedEffectList = gemInstance.gemData and gemInstance.gemData.grantedEffectList or { gemInstance.grantedEffect }
			for index, grantedEffect in ipairs(grantedEffectList) do
				if not grantedEffect.support and not grantedEffect.hideFromSideBar and (not grantedEffect.hasGlobalEffect or gemInstance["enableGlobal"..index]) then
					return true
				end
			end
		end
		return false
	end
	slot.count.tooltipFunc = function(tooltip)
		if tooltip:CheckForUpdate(self.build.outputRevision, self.displayGroup) then
			tooltip:AddLine(16, "^8Note: `count` numeric value scales the DPS of associated skill by a scalar.")
			tooltip:AddLine(16, "^8To be used with totems, minions, shot-gunning of projectiles (e.g., VD, magma-orbs),")
			tooltip:AddLine(16, "^8multi-hit projectiles (e.g. ball-lightning), traps, mines.")
		end
	end
	slot.count.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	self.controls["gemSlot"..index.."Count"] = slot.count

	slot.corruptLevel = new("DropDownControl", {"LEFT",slot.count,"RIGHT"}, {18, 0, 140, 20}, corruptOption, function(indexSel, value)
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			gemInstance = { nameSpec = "", level = 20, quality = 0, enabled = true, enableGlobal1 = true, count = 1, new = true, corruptLevel = 0, corrupted = false }
			self.displayGroup.gemList[index] = gemInstance
			slot.level:SetText(gemInstance.level)
			slot.quality:SetText(gemInstance.quality)
			slot.enabled.state = true
			slot.enableGlobal1.state = true
		end
		gemInstance.corruptLevel = value.level
		gemInstance.corrupted = (value.label ~= "Not Corrupted")
		slot.corruptLevel.selIndex = indexSel
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)

	slot.corruptLevel.shown = function()
		local gemInstance = self.displayGroup and self.displayGroup.gemList[index]
		if gemInstance then
			local activeGrantedEffect = gemInstance.grantedEffect or gemInstance.gemData and gemInstance.gemData.grantedEffect
			if gemInstance.fromItem or gemInstance.fromTree or activeGrantedEffect and (activeGrantedEffect.fromItem or activeGrantedEffect.fromTree) then
				return false
			end
			local grantedEffectList = gemInstance.gemData and gemInstance.gemData.grantedEffectList or { gemInstance.grantedEffect }
			for index, grantedEffect in ipairs(grantedEffectList) do
				if not grantedEffect.support and not grantedEffect.hideFromSideBar and (not grantedEffect.hasGlobalEffect or gemInstance["enableGlobal"..index]) then
					return true
				end
			end
		end
		return false
	end

	slot.corruptLevel.enabled = function()
		return index <= #self.displayGroup.gemList
	end

	self.controls["gemSlot"..index.."CorruptLevel"] = slot.corruptLevel

	-- Parser/calculator error message
	slot.errMsg = new("LabelControl", {"LEFT",slot.count,"RIGHT"}, {2, 2, 0, 16}, function()
		local gemInstance = self.displayGroup and self.displayGroup.gemList[index]
		return "^1"..(gemInstance and gemInstance.errMsg or "")
	end)
	self.controls["gemSlot"..index.."ErrMsg"] = slot.errMsg

	-- Enable global-effect skill 1
	slot.enableGlobal1 = new("CheckBoxControl", {"TOPLEFT",slot.delete,"BOTTOMLEFT"}, {0, 2, 20}, "", function(state)
		local gemInstance = self.displayGroup.gemList[index]
		gemInstance.enableGlobal1 = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.enableGlobal1.shown = function()
		local gemInstance = self.displayGroup and self.displayGroup.gemList[index]
		return gemInstance and gemInstance.gemData and gemInstance.gemData.vaalGem and gemInstance.gemData.grantedEffectList[1] and not gemInstance.gemData.grantedEffectList[1].support
	end
	slot.enableGlobal1.x = function()
		return self:IsShown() and (DrawStringWidth(16, "VAR", slot.enableGlobal1:GetProperty("label")) + 5) or 0
	end
	slot.enableGlobal1.label = function()
		return "Enable "..self.displayGroup.gemList[index].gemData.grantedEffectList[1].name..":"
	end
	self.controls["gemSlot"..index.."EnableGlobal1"] = slot.enableGlobal1

	-- Enable global-effect skill 2
	slot.enableGlobal2 = new("CheckBoxControl", {"LEFT",slot.enableGlobal1,"RIGHT",true}, {0, 0, 20}, "", function(state)
		local gemInstance = self.displayGroup.gemList[index]
		gemInstance.enableGlobal2 = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.enableGlobal2.shown = function()
		local gemInstance = self.displayGroup and self.displayGroup.gemList[index]
		return gemInstance and gemInstance.gemData and gemInstance.gemData.vaalGem and gemInstance.gemData.grantedEffectList[2] and not gemInstance.gemData.grantedEffectList[2].support
	end
	slot.enableGlobal2.x = function()
		return self:IsShown() and (DrawStringWidth(16, "VAR", slot.enableGlobal2:GetProperty("label")) + 12) or 0
	end
	slot.enableGlobal2.label = function()
		return "Enable "..self.displayGroup.gemList[index].gemData.grantedEffectList[2].name..":"
	end
	self.controls["gemSlot"..index.."EnableGlobal2"] = slot.enableGlobal2
end

-- Update the gem slot controls to reflect the currently displayed socket group
function SkillsTabClass:UpdateGemSlots()
	if not self.displayGroup then
		return
	end
	for slotIndex = 1, #self.displayGroup.gemList + 1 do
		if not self.gemSlots[slotIndex] then
			self:CreateGemSlot(slotIndex)
		end
		local slot = self.gemSlots[slotIndex]
		if slotIndex == #self.displayGroup.gemList + 1 then
			slot.nameSpec:SetText("")
			slot.level:SetText("")
			slot.quality:SetText("")
			slot.enabled.state = false
			slot.count:SetText(1)
			slot.corruptLevel.selIndex = 1
		else
			slot.nameSpec.inactiveCol = self.displayGroup.gemList[slotIndex].color
		end
	end
	self:UpdateGlobalGemCountAssignments()
end

-- Find the skill gem matching the given specification
function SkillsTabClass:FindSkillGem(nameSpec)
	-- Search for gem name using increasingly broad search patterns
	local patternList = {
		"^ "..nameSpec:gsub("%a", function(a) return "["..a:upper()..a:lower().."]" end).."$", -- Exact match (case-insensitive)
		"^"..nameSpec:gsub("%a", " %0%%l+").."$", -- Simple abbreviation ("CtF" -> "Cold to Fire")
		"^ "..nameSpec:gsub(" ",""):gsub("%l", "%%l*%0").."%l+$", -- Abbreviated words ("CldFr" -> "Cold to Fire")
		"^"..nameSpec:gsub(" ",""):gsub("%a", ".*%0"), -- Global abbreviation ("CtoF" -> "Cold to Fire")
		"^"..nameSpec:gsub(" ",""):gsub("%a", function(a) return ".*".."["..a:upper()..a:lower().."]" end), -- Case insensitive global abbreviation ("ctof" -> "Cold to Fire")
	}
	for i, pattern in ipairs(patternList) do
		local foundGemData
		for gemId, gemData in pairs(self.build.data.gems) do
			if (" "..gemData.name):match(pattern) then
				if foundGemData then
					return "Ambiguous gem name '" .. nameSpec .. "': matches '" .. foundGemData.name .. "', '" .. gemData.name .. "'"
				end
				foundGemData = gemData
			end
		end
		if foundGemData then
			return nil, foundGemData
		end
	end
	return "Unrecognised gem name '" .. nameSpec .. "'"
end

function SkillsTabClass:ProcessGemLevel(gemData)
	if not gemData then
		return 1
	end
	local grantedEffect = gemData.grantedEffect
	local naturalMaxLevel = gemData.naturalMaxLevel
	if self.defaultGemLevel == "awakenedMaximum" then
		return naturalMaxLevel + 1
	elseif self.defaultGemLevel == "corruptedMaximum" then
		if grantedEffect.plusVersionOf then
			return naturalMaxLevel
		else
			self.defaultCorruptionLevel = 1
			self.defaultCorruptionState = true
			return naturalMaxLevel
		end
	elseif self.defaultGemLevel == "normalMaximum" then
			self.defaultCorruptionLevel = 0
			self.defaultCorruptionState = false
		return naturalMaxLevel
	else -- self.defaultGemLevel == "characterLevel"
		self.defaultCorruptionLevel = 0
		self.defaultCorruptionState = false
		local maxGemLevel = naturalMaxLevel
		if not grantedEffect.levels[maxGemLevel] then
			maxGemLevel = #grantedEffect.levels
		end
		local characterLevel = self.build and self.build.characterLevel or 1
		for gemLevel = maxGemLevel, 1, -1 do
			if grantedEffect.levels[gemLevel].levelRequirement <= characterLevel then
				return gemLevel
			end
		end
		return 1
	end
end

-- Processes the given socket group, filling in information that will be used for display or calculations
function SkillsTabClass:ProcessSocketGroup(socketGroup)
	-- Loop through the skill gem list
	local data = self.build.data
	for _, gemInstance in ipairs(socketGroup.gemList) do
		gemInstance.color = "^8"
		gemInstance.nameSpec = gemInstance.nameSpec or ""
		local prevDefaultLevel = gemInstance.gemData and gemInstance.gemData.naturalMaxLevel or (gemInstance.new and 20)
		gemInstance.gemData, gemInstance.grantedEffect = nil
		if gemInstance.gemId then
			-- Specified by gem ID
			-- Used for skills granted by skill gems
			gemInstance.errMsg = nil
			gemInstance.gemData = data.gems[gemInstance.gemId]
			if gemInstance.gemData then
				if gemInstance.nameSpec:match("^Companion:") or gemInstance.nameSpec:match("^Spectre:") then
					gemInstance.nameSpec = gemInstance.nameSpec
				else
					gemInstance.nameSpec = gemInstance.gemData.name
				end
				gemInstance.skillId = gemInstance.gemData.grantedEffectId
			end
		elseif gemInstance.skillId then
			-- Specified by skill ID
			-- Used for skills granted by items
			gemInstance.errMsg = nil
			local gemId = data.gemForSkill[gemInstance.skillId]
			if gemId then
				gemInstance.gemData = data.gems[gemId]
			else
				gemInstance.grantedEffect = data.skills[gemInstance.skillId]
			end
			if gemInstance.triggered and gemInstance.grantedEffect then
				if gemInstance.grantedEffect.levels[gemInstance.level] then
					gemInstance.grantedEffect.levels[gemInstance.level].cost = {}
				end
			end
		elseif gemInstance.nameSpec:match("%S") then
			-- Specified by gem/skill name, try to match it
			-- Used to migrate pre-1.4.20 builds
			gemInstance.errMsg, gemInstance.gemData = self:FindSkillGem(gemInstance.nameSpec)
			gemInstance.gemId = gemInstance.gemData and gemInstance.gemData.id
			gemInstance.skillId = gemInstance.gemData and gemInstance.gemData.grantedEffectId
			if gemInstance.gemData then
				gemInstance.nameSpec = gemInstance.gemData.name
			end
		else
			gemInstance.errMsg, gemInstance.gemData, gemInstance.skillId = nil
		end
		if gemInstance.gemData and gemInstance.gemData.grantedEffect.hideFromSideBar then
			gemInstance.errMsg = gemInstance.nameSpec .. " cannot be used as an active skill"
			gemInstance.gemData = nil
		end
		if gemInstance.gemData or gemInstance.grantedEffect then
			local grantedEffect = gemInstance.grantedEffect or gemInstance.gemData.grantedEffect
			if grantedEffect.color == 1 then
				gemInstance.color = colorCodes.STRENGTH
			elseif grantedEffect.color == 2 then
				gemInstance.color = colorCodes.DEXTERITY
			elseif grantedEffect.color == 3 then
				gemInstance.color = colorCodes.INTELLIGENCE
			else
				gemInstance.color = colorCodes.NORMAL
			end
			if prevDefaultLevel and gemInstance.gemData and gemInstance.gemData.naturalMaxLevel ~= prevDefaultLevel then
				gemInstance.level = gemInstance.gemData.naturalMaxLevel
				gemInstance.naturalMaxLevel = gemInstance.level
			elseif gemInstance.new then
				gemInstance.level = gemInstance.gemData.naturalMaxLevel
				gemInstance.naturalMaxLevel = gemInstance.level
				gemInstance.new = nil
			end
			calcLib.validateGemLevel(gemInstance)
			if gemInstance.gemData then
				gemInstance.reqLevel = grantedEffect.levels[gemInstance.level].levelRequirement
				gemInstance.reqStr = calcLib.getGemStatRequirement(gemInstance.reqLevel, gemInstance.gemData.reqStr, grantedEffect.support)
				gemInstance.reqDex = calcLib.getGemStatRequirement(gemInstance.reqLevel, gemInstance.gemData.reqDex, grantedEffect.support)
				gemInstance.reqInt = calcLib.getGemStatRequirement(gemInstance.reqLevel, gemInstance.gemData.reqInt, grantedEffect.support)
			end
		end
	end
end

-- Set the skill to be displayed/edited
function SkillsTabClass:SetDisplayGroup(socketGroup)
	self.displayGroup = socketGroup
	if socketGroup then
		self:ProcessSocketGroup(socketGroup)

		-- Update the main controls
		self.controls.groupLabel:SetText(socketGroup.label)
		self.controls.groupSlot:SelByValue(socketGroup.slot, "slotName")
		self.controls.groupEnabled.state = socketGroup.enabled
		self.controls.includeInFullDPS.state = socketGroup.includeInFullDPS and socketGroup.enabled
		self.controls.groupCount:SetText(socketGroup.groupCount or 1)

		-- Update the gem slot controls
		self:UpdateGemSlots()
		for index, gemInstance in pairs(socketGroup.gemList) do
			self.gemSlots[index].nameSpec:SetText(gemInstance.nameSpec)
			self.gemSlots[index].level:SetText(gemInstance.level)
			self.gemSlots[index].quality:SetText(gemInstance.quality)
			self.gemSlots[index].enabled.state = gemInstance.enabled
			self.gemSlots[index].enableGlobal1.state = gemInstance.enableGlobal1
			self.gemSlots[index].enableGlobal2.state = gemInstance.enableGlobal2
			self.gemSlots[index].count:SetText(gemInstance.count or 1)
			self.gemSlots[index].corruptLevel.selIndex = self:GetCorruptIndex(gemInstance)
		end
	end
end

function SkillsTabClass:AddSocketGroupTooltip(tooltip, socketGroup)
	if socketGroup.explodeSources then
		for _, source in ipairs(socketGroup.explodeSources) do
			tooltip:AddLine(18, "^7Source: " .. colorCodes[source.rarity or "NORMAL"] .. (source.name or source.dn or "???"))
		end
		return
	end
	if socketGroup.enabled and not socketGroup.slotEnabled then
		tooltip:AddLine(16, "^7Note: this group is disabled because it is socketed in the inactive weapon set.")
	end
	local sourceSingle = socketGroup.sourceItem or socketGroup.sourceNode
	if sourceSingle then
		tooltip:AddLine(18, "^7Source: " .. colorCodes[sourceSingle.rarity or "NORMAL"] .. sourceSingle.name)
		tooltip:AddSeparator(10)
	end
	local gemShown = { }
	for index, activeSkill in ipairs(socketGroup.displaySkillList) do
		if index > 1 then
			tooltip:AddSeparator(10)
		end
		tooltip:AddLine(16, "^7Active Skill #"..index..":")
		for _, skillEffect in ipairs(activeSkill.effectList) do
			tooltip:AddLine(20, string.format("%s%s ^7%d%s/%d%s%s",
				data.skillColorMap[skillEffect.grantedEffect.color or skillEffect.gemData and skillEffect.gemData.grantedEffect.color],
				skillEffect.srcInstance.nameSpec or skillEffect.grantedEffect.name,
				skillEffect.srcInstance and skillEffect.srcInstance.level or skillEffect.level,
				(skillEffect.srcInstance and skillEffect.level > skillEffect.srcInstance.level) and colorCodes.MAGIC.."+"..(skillEffect.level - skillEffect.srcInstance.level).."^7" or "",
				skillEffect.srcInstance and skillEffect.srcInstance.quality or skillEffect.quality,
				(skillEffect.srcInstance and skillEffect.quality > skillEffect.srcInstance.quality) and colorCodes.MAGIC.."+"..(skillEffect.quality - skillEffect.srcInstance.quality).."^7" or "",
				(skillEffect.srcInstance and skillEffect.srcInstance.corrupted == true) and (colorCodes.NEGATIVE.." C"..((skillEffect.srcInstance.corruptLevel or 0) ~= 0 and ((skillEffect.srcInstance.corruptLevel > 0 and "+" or "")..skillEffect.srcInstance.corruptLevel) or "")) or ""
			))
			if skillEffect.srcInstance then
				gemShown[skillEffect.srcInstance] = true
			end
		end
		if activeSkill.minion then
			tooltip:AddSeparator(10)
			tooltip:AddLine(16, "^7Active Skill #" .. index .. "'s Main Minion Skill:")
			local activeEffect = activeSkill.minion.mainSkill.effectList[1]
			tooltip:AddLine(20, string.format("%s%s ^7%d/%d",
				data.skillColorMap[activeEffect.grantedEffect.color] or colorCodes.NORMAL,
				activeEffect.grantedEffect.name,
				activeEffect.level,
				activeEffect.quality
			))
			if activeEffect.srcInstance then
				gemShown[activeEffect.srcInstance] = true
			end
		end
	end
	local showOtherHeader = true
	for _, gemInstance in ipairs(socketGroup.displayGemList or socketGroup.gemList) do
		if not gemShown[gemInstance] then
			if showOtherHeader then
				showOtherHeader = false
				tooltip:AddSeparator(10)
				tooltip:AddLine(16, "^7Inactive Gems:")
			end
			local reason = ""
			local displayEffect = gemInstance.displayEffect or gemInstance
			local grantedEffect = gemInstance.gemData and gemInstance.gemData.grantedEffect or gemInstance.grantedEffect
			if not grantedEffect then
				reason = "(Unsupported)"
			elseif not gemInstance.enabled then
				reason = "(Disabled)"
			elseif not socketGroup.enabled or not socketGroup.slotEnabled then
			elseif grantedEffect.support then
				if displayEffect.superseded then
					reason = "(Superseded)"
				elseif (not displayEffect.isSupporting or not next(displayEffect.isSupporting)) and #socketGroup.displaySkillList > 0 then
					reason = "(Cannot apply to any of the active skills)"
				end
			end
			tooltip:AddLine(20, string.format("%s%s ^7%d%s/%d%s %s",
				gemInstance.color,
				(gemInstance.grantedEffect and gemInstance.grantedEffect.name) or (gemInstance.gemData and gemInstance.gemData.name) or gemInstance.nameSpec,
				displayEffect.srcInstance and displayEffect.srcInstance.level or displayEffect.level,
				displayEffect.level > gemInstance.level and colorCodes.MAGIC .. "+" .. (displayEffect.level - gemInstance.level) .. "^7" or "",
				displayEffect.srcInstance and displayEffect.srcInstance.quality or displayEffect.quality,
				displayEffect.quality > gemInstance.quality and colorCodes.MAGIC .. "+" .. (displayEffect.quality - gemInstance.quality) .. "^7" or "",
				reason
			))
		end
	end
end

function SkillsTabClass:CreateUndoState()
	local state = { }
	state.activeSkillSetId = self.activeSkillSetId
	state.skillSets = { }
	for skillSetIndex, skillSet in pairs(self.skillSets) do
		local newSkillSet = copyTable(skillSet, true)
		newSkillSet.socketGroupList = { }
		for socketGroupIndex, socketGroup in pairs(skillSet.socketGroupList) do
			local newGroup = copyTable(socketGroup, true)
			newGroup.gemList = { }
			for gemIndex, gem in pairs(socketGroup.gemList) do
				newGroup.gemList[gemIndex] = copyTable(gem, true)
			end
			newSkillSet.socketGroupList[socketGroupIndex] = newGroup
		end
		state.skillSets[skillSetIndex] = newSkillSet
	end
	state.skillSetOrderList = copyTable(self.skillSetOrderList)
	-- Save active socket group for both skillsTab and calcsTab to UndoState
	state.activeSocketGroup = self.build.mainSocketGroup
	state.activeSocketGroup2 = self.build.calcsTab.input.skill_number
	return state
end

function SkillsTabClass:RestoreUndoState(state)
	local displayId = isValueInArray(self.socketGroupList, self.displayGroup)
	wipeTable(self.skillSets)
	for k, v in pairs(state.skillSets) do
		self.skillSets[k] = v
	end
	wipeTable(self.skillSetOrderList)
	for k, v in ipairs(state.skillSetOrderList) do
		self.skillSetOrderList[k] = v
	end
	self:SetActiveSkillSet(state.activeSkillSetId)
	self:SetDisplayGroup(displayId and self.socketGroupList[displayId])
	if self.controls.groupList.selValue then
		self.controls.groupList.selValue = self.socketGroupList[self.controls.groupList.selIndex]
	end
	-- Load active socket group for both skillsTab and calcsTab from UndoState
	self.build.mainSocketGroup = state.activeSocketGroup
	self.build.calcsTab.input.skill_number = state.activeSocketGroup2
end

-- Opens the skill set manager
function SkillsTabClass:OpenSkillSetManagePopup()
	main:OpenPopup(370, 290, "Manage Skill Sets", {
		new("SkillSetListControl", nil, {0, 50, 350, 200}, self),
		new("ButtonControl", nil, {0, 260, 90, 20}, "Done", function()
			main:ClosePopup()
		end),
	})
end

-- Creates a new skill set without adding to order list
function SkillsTabClass:CreateSkillSet(skillSetId, title)
	local skillSet = { id = skillSetId, title = title, socketGroupList = {} }
	if not skillSetId then
		skillSet.id = #self.skillSets + 1
	end
	self.skillSets[skillSet.id] = skillSet
	return skillSet
end

-- Creates a new skill set with title, adds to order list and sets modFlag
function SkillsTabClass:NewSkillSet(skillSetId, title)
	local skillSet = self:CreateSkillSet(skillSetId, title)
	t_insert(self.skillSetOrderList, skillSet.id)
	self.modFlag = true
	return skillSet
end

function SkillsTabClass:CopySkillSet(sourceSkillSetId, newSkillSetName)
	local skillSet = self.skillSets[sourceSkillSetId]
	local newSkillSet = copyTable(skillSet, true)
	newSkillSet.title = newSkillSetName or skillSet.title .. " (Copy)"
	newSkillSet.socketGroupList = {}
	for socketGroupIndex, socketGroup in pairs(skillSet.socketGroupList) do
		local newGroup = copyTable(socketGroup, true)
		newGroup.gemList = {}
		for gemIndex, gem in pairs(socketGroup.gemList) do
			newGroup.gemList[gemIndex] = copyTable(gem, true)
		end
		t_insert(newSkillSet.socketGroupList, newGroup)
	end
	newSkillSet.id = #self.skillSets + 1
	self.skillSets[newSkillSet.id] = newSkillSet
	t_insert(self.skillSetOrderList, newSkillSet.id)
	self.modFlag = true
	return newSkillSet
end

function SkillsTabClass:RenameSkillSet(skillSetId, newTitle)
	local skillSet = self.skillSets[skillSetId]
	
	if not skillSet then
		return
	end

	skillSet.title = newTitle
	self.modFlag = true
end

function SkillsTabClass:DeleteSkillSet(skillSetId, orderListIndex)
	t_remove(self.skillSetOrderList, orderListIndex)
	self.skillSets[skillSetId] = nil
	self.modFlag = true
end

-- Changes the active skill set
function SkillsTabClass:SetActiveSkillSet(skillSetId, deferSync)
	-- Initialize skill sets if needed
	if not self.skillSetOrderList[1] then
		self.skillSetOrderList[1] = 1
		self:CreateSkillSet(1)
	end

	if not skillSetId then
		skillSetId = self.activeSkillSetId
	end

	if not self.skillSets[skillSetId] then
		skillSetId = self.skillSetOrderList[1]
	end

	self.socketGroupList = self.skillSets[skillSetId].socketGroupList
	self.controls.groupList.list = self.socketGroupList
	self.activeSkillSetId = skillSetId
	self.build.buildFlag = true

	-- set the loadout option to the dummy option since it is now dirty
	self:SetDisplayGroup(self.socketGroupList[1])
	if not deferSync then
		self.build:SyncLoadouts()
	end
end

-- Loop over all socket groups and gem instances
-- to updated global gem count assignments
function SkillsTabClass:UpdateGlobalGemCountAssignments()
	wipeTable(GlobalGemAssignments)
	local countSocketGroups = 0
	for _, socketGroup in ipairs(self.socketGroupList) do
		local countGroup = true
		if socketGroup.enabled then
			local activeGem = socketGroup.gemList[1]
			local activeGrantedEffect = activeGem and (activeGem.grantedEffect or activeGem.gemData and activeGem.gemData.grantedEffect)
			if activeGem and (activeGem.fromItem or activeGem.fromTree or activeGrantedEffect and (activeGrantedEffect.fromItem or activeGrantedEffect.fromTree)) then
				countGroup = false
			end
			for _, gemInstance in ipairs(socketGroup.gemList) do
				if gemInstance.gemData and gemInstance.enabled then
					if GlobalGemAssignments[gemInstance.gemData.name] then
						GlobalGemAssignments[gemInstance.gemData.name].count = GlobalGemAssignments[gemInstance.gemData.name].count + 1
						if socketGroup.displayLabel then
							t_insert(GlobalGemAssignments[gemInstance.gemData.name].groups, socketGroup.displayLabel)
						end
					else
						GlobalGemAssignments[gemInstance.gemData.name] = {
							count = 1,
							support = gemInstance.gemData.grantedEffect and gemInstance.gemData.grantedEffect.support or false,
							lineage = gemInstance.gemData.grantedEffect and gemInstance.gemData.grantedEffect.isLineage or false,
							groups = { }
						}
						if socketGroup.displayLabel then
							t_insert(GlobalGemAssignments[gemInstance.gemData.name].groups, socketGroup.displayLabel)
						end
					end
				end
			end
		end
		if countGroup then
			countSocketGroups = countSocketGroups + 1
		end
	end
	GlobalGemAssignments["GemGroupCount"] = countSocketGroups
end

