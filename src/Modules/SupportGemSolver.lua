-- Path of Building
--
-- Module: SupportGemSolver
-- Greedy / beam search over support gem combinations for a socket group.
--
-- Iterates compatible support gems for the socket group's active skill and
-- fills empty (and optionally disabled) support slots with the combination
-- that maximises a chosen Output metric. Enabled supports already in the
-- group are pinned. gemFamily collisions are filtered out up-front so the
-- search only evaluates legal combinations.
--
-- Designed to run inside a coroutine: yields periodically so the UI stays
-- responsive across long searches.

local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local m_huge = math.huge

local supportGemSolver = { }

-- Metric keys we support, ordered for the UI dropdown. The `key` is what we
-- read out of the Output table; `useFullDPS` toggles the expensive FullDPS
-- pass in the misc calculator (only needed for FullDPS itself).
supportGemSolver.metricList = {
	{ label = "Average Hit",   key = "AverageDamage",   useFullDPS = false },
	{ label = "Hit DPS",       key = "TotalDPS",        useFullDPS = false },
	{ label = "Combined DPS",  key = "CombinedDPS",     useFullDPS = false },
	{ label = "Full DPS",      key = "FullDPS",         useFullDPS = true  },
	{ label = "DoT DPS",       key = "TotalDot",        useFullDPS = false },
	{ label = "Bleed DPS",     key = "BleedDPS",        useFullDPS = false },
	{ label = "Ignite DPS",    key = "IgniteDPS",       useFullDPS = false },
	{ label = "Poison DPS",    key = "TotalPoisonDPS",  useFullDPS = false },
}

-- Read a metric from an Output table. Falls back to the minion's output for
-- summon-style skills (mirrors what GemSelectControl does when sorting gems).
local function readMetric(output, key)
	if not output then
		return 0
	end
	local v = output[key]
	if type(v) == "number" then
		return v
	end
	if output.Minion then
		local mv = output.Minion[key] or (key == "TotalDPS" and output.Minion.CombinedDPS)
		if type(mv) == "number" then
			return mv
		end
	end
	return 0
end

-- Resolve the active skill object for this socket group. Prefers the
-- calcs-mode list (since the misc calculator runs in CALCULATOR mode, which
-- doesn't populate either list — both are written by MAIN / CALCS passes
-- during the normal build update, and the user's "Active Skill" dropdown in
-- the calcs tab indexes into displaySkillListCalcs).
local function resolveActiveSkill(socketGroup)
	local list = socketGroup.displaySkillListCalcs or socketGroup.displaySkillList
	if not list or #list == 0 then
		return nil
	end
	local idx = socketGroup.mainActiveSkillCalcs or socketGroup.mainActiveSkill or 1
	return list[idx] or list[1]
end

-- Returns the gemFamily entries for an enabled support gemInstance, or nil if
-- it isn't an enabled support (in which case it doesn't contribute a lock).
local function pinnedFamiliesOf(gemInstance)
	if not gemInstance or not gemInstance.gemData then
		return nil
	end
	local ge = gemInstance.gemData.grantedEffect
	if not ge or not ge.support then
		return nil
	end
	return ge.gemFamily
end

-- Walk gemList; classify each slot as pinned (active gems + enabled supports),
-- fillable (empty slot, or disabled support when treatDisabledAsEmpty), or
-- unrelated (disabled supports kept as-is when not treating them as empty).
-- Also collects the lockedFamilies set and lockedGemIds set from pinned
-- supports so candidate enumeration can pre-filter conflicts.
function supportGemSolver.classify(socketGroup, treatDisabledAsEmpty)
	local fillSlots = { }
	local lockedFamilies = { }
	local lockedGemIds = { }
	for i, gem in ipairs(socketGroup.gemList) do
		local ge = gem.gemData and gem.gemData.grantedEffect
		if not ge then
			-- Empty slot
			t_insert(fillSlots, i)
		elseif ge.support then
			if gem.enabled then
				if gem.gemId then
					lockedGemIds[gem.gemId] = true
				end
				if ge.gemFamily then
					for _, fam in ipairs(ge.gemFamily) do
						lockedFamilies[fam] = true
					end
				end
			elseif treatDisabledAsEmpty then
				t_insert(fillSlots, i)
			end
			-- Disabled support with treatDisabledAsEmpty=false is left alone.
		end
		-- Active skill gems are always pinned (no contribution to fill list
		-- or to lockedFamilies, since gemFamily is a support-only concept).
	end
	return fillSlots, lockedFamilies, lockedGemIds
end

-- Enumerate all support gems in build.data.gems compatible with `activeSkill`
-- and not colliding with `lockedFamilies` / `lockedGemIds`. Returns a list of
-- { gemId, gemData, families } so the inner loop avoids re-reading gemFamily.
function supportGemSolver.collectCandidates(build, activeSkill, lockedFamilies, lockedGemIds)
	local candidates = { }
	for gemId, gemData in pairs(build.data.gems) do
		local ge = gemData.grantedEffect
		if ge and ge.support and not lockedGemIds[gemId] then
			local conflict = false
			if ge.gemFamily then
				for _, fam in ipairs(ge.gemFamily) do
					if lockedFamilies[fam] then
						conflict = true
						break
					end
				end
			end
			if not conflict and calcLib.canGrantedEffectSupportActiveSkill(ge, activeSkill) then
				t_insert(candidates, { gemId = gemId, gemData = gemData, families = ge.gemFamily })
			end
		end
	end
	return candidates
end

-- Apply a candidate to a gemInstance in-place. Mirrors what GemSelectControl
-- does in CalcOutputWithThisGem (we set both gemId and gemData so calcs.initEnv
-- picks up the change regardless of which it consults).
local function applyCandidate(skillsTab, slotGem, gemData)
	slotGem.gemId = gemData.id
	slotGem.skillId = gemData.grantedEffectId
	slotGem.nameSpec = gemData.name
	slotGem.gemData = gemData
	slotGem.grantedEffect = nil
	slotGem.errMsg = nil
	slotGem.displayEffect = nil
	slotGem.enabled = true
	if slotGem.enableGlobal1 == nil then slotGem.enableGlobal1 = true end
	if slotGem.enableGlobal2 == nil then slotGem.enableGlobal2 = false end
	slotGem.count = slotGem.count or 1
	slotGem.level = skillsTab:ProcessGemLevel(gemData) or gemData.naturalMaxLevel or 1
	slotGem.naturalMaxLevel = gemData.naturalMaxLevel
	slotGem.quality = slotGem.quality or (skillsTab.defaultGemQuality or 0)
end

-- Clear a slot so the calculator sees nothing in it. Leave the table itself
-- in place so we can mutate it across iterations (and so the snapshot/restore
-- machinery keeps simple index-based identity).
local function clearSlot(slotGem)
	slotGem.gemId = nil
	slotGem.skillId = nil
	slotGem.gemData = nil
	slotGem.grantedEffect = nil
	slotGem.errMsg = nil
	slotGem.displayEffect = nil
	slotGem.nameSpec = ""
end

-- Solve. Mutates socketGroup.gemList during the search and leaves it holding
-- the best combination found (callers should snapshot before invoking if they
-- want an undo path — see SupportGemSolver.snapshot/restore below).
--
-- Options:
--   metric                  -- one of supportGemSolver.metricList[*].key
--   useFullDPS              -- pass to calcFunc (matches the chosen metric)
--   treatDisabledAsEmpty    -- if true, disabled supports become fill targets
--   beamWidth               -- 1 = pure greedy (default); >1 = beam search
--   progressFn(state)       -- optional callback after each evaluation
--   yieldEvery              -- yield to coroutine every N evaluations (default 5)
function supportGemSolver.solve(build, socketGroup, options)
	options = options or { }
	local metric = options.metric or "AverageDamage"
	local useFullDPS = options.useFullDPS == true
	local treatDisabledAsEmpty = options.treatDisabledAsEmpty ~= false
	local beamWidth = options.beamWidth or 1
	local yieldEvery = options.yieldEvery or 5
	local progressFn = options.progressFn

	local activeSkill = resolveActiveSkill(socketGroup)
	if not activeSkill then
		return { ok = false, error = "No active skill found for this socket group. Run a build calc first." }
	end

	local fillSlots, lockedFamilies, lockedGemIds = supportGemSolver.classify(socketGroup, treatDisabledAsEmpty)
	if #fillSlots == 0 then
		return { ok = false, error = "No empty or disabled support slots to solve. Add slots or disable the supports you want replaced." }
	end

	local candidates = supportGemSolver.collectCandidates(build, activeSkill, lockedFamilies, lockedGemIds)
	if #candidates == 0 then
		return { ok = false, error = "No compatible support gems available for this active skill." }
	end

	-- Snapshot every fill slot for restore-on-cancel. We only snapshot the
	-- fields the solver touches (gemList itself stays the same table).
	local snapshot = { }
	for _, idx in ipairs(fillSlots) do
		local g = socketGroup.gemList[idx]
		snapshot[idx] = {
			gemId         = g.gemId,
			skillId       = g.skillId,
			gemData       = g.gemData,
			grantedEffect = g.grantedEffect,
			errMsg        = g.errMsg,
			displayEffect = g.displayEffect,
			nameSpec      = g.nameSpec,
			enabled       = g.enabled,
			enableGlobal1 = g.enableGlobal1,
			enableGlobal2 = g.enableGlobal2,
			level         = g.level,
			quality       = g.quality,
			count         = g.count,
			naturalMaxLevel = g.naturalMaxLevel,
		}
	end

	-- Empty all fill slots so the base calc reflects "no supports added yet."
	for _, idx in ipairs(fillSlots) do
		clearSlot(socketGroup.gemList[idx])
	end

	local calcFunc, calcBase = build.calcsTab:GetMiscCalculator()
	-- calcBase is the baseline output captured when getMiscCalculator was last
	-- built. It reflects whatever supports were in the group at the time of the
	-- previous full build — i.e., before we cleared the fill slots. We re-run
	-- once now with the slots empty so baseScore matches the actual starting
	-- point of the search.
	local emptyOutput = calcFunc(nil, useFullDPS)
	local baseScore = readMetric(emptyOutput, metric)

	local state = {
		ok = true,
		metric = metric,
		baseScore = baseScore,
		bestScore = baseScore,
		evaluated = 0,
		totalEstimate = #fillSlots * #candidates,
		fillSlots = fillSlots,
		assignments = { },  -- slotIndex -> { gemId, name, score }
		snapshot = snapshot,
		cancelled = false,
	}

	local function maybeYield()
		if state.evaluated % yieldEvery == 0 then
			if progressFn then
				progressFn(state)
			end
			if coroutine.running() then
				coroutine.yield()
			end
		end
	end

	-- Greedy / beam search. For each fill slot in order, evaluate every
	-- non-conflicting candidate, keep the top-`beamWidth` by score, commit the
	-- best one (beam search keeps alternates only for tie-breaking lookahead
	-- in later slots — for v1 we just track the best per slot).
	local usedFamilies = { }
	for fam in pairs(lockedFamilies) do usedFamilies[fam] = true end
	local usedGemIds = { }
	for id in pairs(lockedGemIds) do usedGemIds[id] = true end

	for slotPos, slotIdx in ipairs(fillSlots) do
		local slotGem = socketGroup.gemList[slotIdx]
		local bestScore = -m_huge
		local bestCand = nil

		for _, cand in ipairs(candidates) do
			if not usedGemIds[cand.gemId] then
				local conflict = false
				if cand.families then
					for _, fam in ipairs(cand.families) do
						if usedFamilies[fam] then
							conflict = true
							break
						end
					end
				end
				if not conflict then
					applyCandidate(build.skillsTab, slotGem, cand.gemData)
					local output = calcFunc(nil, useFullDPS)
					local score = readMetric(output, metric)
					state.evaluated = state.evaluated + 1
					if score > bestScore then
						bestScore = score
						bestCand = cand
						state.bestScore = score > state.bestScore and score or state.bestScore
					end
					maybeYield()
				end
			end
		end

		if bestCand then
			applyCandidate(build.skillsTab, slotGem, bestCand.gemData)
			usedGemIds[bestCand.gemId] = true
			if bestCand.families then
				for _, fam in ipairs(bestCand.families) do
					usedFamilies[fam] = true
				end
			end
			state.assignments[slotIdx] = {
				gemId = bestCand.gemId,
				name = bestCand.gemData.name,
				score = bestScore,
			}
			state.bestScore = bestScore
		else
			clearSlot(slotGem)
		end

		if progressFn then
			progressFn(state)
		end
	end

	-- beamWidth is a no-op in v1 (always greedy). Reserved for a future pass
	-- that keeps the top-K partial loadouts and explores all of them through
	-- the remaining slots; the structure above is shaped so that's a localised
	-- change rather than a rewrite.
	state.beamWidth = beamWidth
	return state
end

-- Restore a snapshot produced by solve(). Used when the user cancels or undoes.
function supportGemSolver.restore(socketGroup, snapshot)
	if not snapshot then return end
	for idx, snap in pairs(snapshot) do
		local g = socketGroup.gemList[idx]
		if g then
			g.gemId         = snap.gemId
			g.skillId       = snap.skillId
			g.gemData       = snap.gemData
			g.grantedEffect = snap.grantedEffect
			g.errMsg        = snap.errMsg
			g.displayEffect = snap.displayEffect
			g.nameSpec      = snap.nameSpec
			g.enabled       = snap.enabled
			g.enableGlobal1 = snap.enableGlobal1
			g.enableGlobal2 = snap.enableGlobal2
			g.level         = snap.level
			g.quality       = snap.quality
			g.count         = snap.count
			g.naturalMaxLevel = snap.naturalMaxLevel
		end
	end
end

return supportGemSolver
