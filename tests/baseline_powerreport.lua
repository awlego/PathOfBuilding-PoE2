-- Headless baseline harness for the Power Report.
-- Loads PoB headless, runs PowerBuilder against one or more builds for a
-- handful of representative stats, and writes:
--   * <out>.tsv         — timing breakdown per (build, stat, run)
--   * <out>.fp.tsv      — correctness fingerprint (base stats + top-10
--                          nodes by power per (build, stat)); compared
--                          across runs to catch regressions in the calc.
--
-- Forces build.viewMode = "TREE" so timings reflect the real user path —
-- saved XMLs typically have viewMode="ITEMS" (last-used tab).
--
-- Run from src/ so HeadlessWrapper's relative paths resolve:
--   cd src
--   luajit ../tests/baseline_powerreport.lua [--builds <dir>] [--out <file>]
--                                            [--match <substr>] [--stats <a,b,c>]
--                                            [--repeat <n>]

io.stdout:setvbuf("no")
io.stderr:setvbuf("no")

package.path = "../runtime/lua/?.lua;../runtime/lua/?/init.lua;" .. package.path
package.cpath = "../runtime/?.dll;" .. package.cpath

local function parseArgs(argv)
	local opts = {
		builds = os.getenv("USERPROFILE") and (os.getenv("USERPROFILE") .. "\\Documents\\Path of Building (PoE2)\\Builds\\0.4")
			or "../../../Documents/Path of Building (PoE2)/Builds/0.4",
		out = "../tests/baseline_powerreport.tsv",
		match = nil,
		stats = "Offence/Defence,Life,Total EHP,Full DPS",
		repeats = 1,
	}
	local i = 1
	while argv and argv[i] do
		local a = argv[i]
		if a == "--builds" then opts.builds = argv[i+1]; i = i + 2
		elseif a == "--out" then opts.out = argv[i+1]; i = i + 2
		elseif a == "--match" then opts.match = argv[i+1]; i = i + 2
		elseif a == "--stats" then opts.stats = argv[i+1]; i = i + 2
		elseif a == "--repeat" then opts.repeats = tonumber(argv[i+1]) or 1; i = i + 2
		else i = i + 1 end
	end
	return opts
end

local opts = parseArgs(arg)

-- Load engine
local ok, err = pcall(dofile, "HeadlessWrapper.lua")
if not ok then
	io.stderr:write("HeadlessWrapper load failed: " .. tostring(err) .. "\n")
	os.exit(1)
end

-- Replace stub GetTime with a real wall-clock (ms). socket ships in runtime/.
local socket = require("socket")
local epoch = socket.gettime()
function GetTime()
	return math.floor((socket.gettime() - epoch) * 1000)
end

-- Capture every ConPrintf line so we can extract the "Power Report" summary.
local capturedLines = {}
local origConPrintf = _G.ConPrintf
_G.ConPrintf = function(fmt, ...)
	local line = string.format(tostring(fmt), ...)
	table.insert(capturedLines, line)
	origConPrintf(fmt, ...)
end

local function flushCaptured()
	local n = #capturedLines
	capturedLines = {}
	return n
end

local function findReportLine(startIdx)
	for i = startIdx, #capturedLines do
		if capturedLines[i]:find("^Power Report ") then
			return capturedLines[i]
		end
	end
end

local function listBuilds(dir, match)
	local patterns
	if match then
		patterns = {}
		for tok in match:gmatch("[^,]+") do
			local t = tok:gsub("^%s+", ""):gsub("%s+$", ""):lower()
			if t ~= "" then table.insert(patterns, t) end
		end
		if #patterns == 0 then patterns = nil end
	end
	local out = {}
	local cmd = string.format('cmd /c dir /b "%s\\*.xml" 2>NUL', dir)
	local p = io.popen(cmd)
	if not p then return out end
	for line in p:lines() do
		if line == "" then
			-- skip
		elseif not patterns then
			table.insert(out, line)
		else
			local ll = line:lower()
			for _, pat in ipairs(patterns) do
				if ll:find(pat, 1, true) then
					table.insert(out, line)
					break
				end
			end
		end
	end
	p:close()
	table.sort(out)
	return out
end

local function readFile(path)
	local f, err = io.open(path, "rb")
	if not f then return nil, err end
	local data = f:read("*a")
	f:close()
	return data
end

local function loadStatList()
	local list = {}
	for _, s in ipairs(data.powerStatList) do
		list[s.label] = s
	end
	return list
end

local function pickStats(labelList, statByLabel)
	local picked = {}
	-- accept either comma or semicolon as separators so labels-with-spaces
	-- can be passed safely from PowerShell with `;`.
	for label in labelList:gmatch("[^,;]+") do
		-- Strip surrounding whitespace and stray quotes (PowerShell sometimes
		-- leaks outer double-quotes into the first/last token).
		label = label:gsub("^[%s\"']+", ""):gsub("[%s\"']+$", "")
		local s = statByLabel[label]
		if not s then
			io.stderr:write("warning: stat label not found: " .. label .. "\n")
		else
			table.insert(picked, s)
		end
	end
	return picked
end

local function ensureBuilt(b)
	-- Force the main calc to finish so mainEnv / miscCalculator are ready.
	b.buildFlag = true
	for _ = 1, 8 do
		runCallback("OnFrame")
		if not b.buildFlag then break end
	end
end

local function loadBuild(buildPath)
	local xml, rerr = readFile(buildPath)
	if not xml then return nil, rerr end
	loadBuildFromXML(xml, buildPath)
	-- Builds save the last-used tab (often "ITEMS") into the XML; force TREE so
	-- the calcFunc FullDPS guard at Calcs.lua:139 fires the same way it does
	-- when a real user is on the Tree tab clicking heatmap stats.
	build.viewMode = "TREE"
	-- Mark dirty so BuildOutput re-runs with the new viewMode/state.
	build.buildFlag = true
	ensureBuilt(build)
	if not build.calcsTab.mainEnv then
		return nil, "mainEnv not initialised"
	end
	return true
end

-- Stats from the main calculation output that should be invariant across any
-- perf-only refactor. If any of these drift, we've broken the calc.
local fingerprintBaseStats = {
	"Life","LifeUnreserved","Mana","ManaUnreserved","Spirit","EnergyShield","Armour","Evasion","Ward",
	"Str","Dex","Int",
	"TotalDPS","CombinedDPS","FullDPS","TotalDot","AverageDamage","Speed","CritChance","CritMultiplier",
	"FireResist","ColdResist","LightningResist","ChaosResist",
	"LifeRegen","ManaRegen","TotalEHP",
}

local function fmtNum(v)
	if v == nil then return "nil" end
	if type(v) ~= "number" then return tostring(v) end
	-- Round small denormals to 0 to ignore JIT-level float jitter.
	if v ~= v then return "nan" end -- NaN
	if v == math.huge then return "inf" end
	if v == -math.huge then return "-inf" end
	return string.format("%.4f", v)
end

local function writeBaseFingerprint(fpf, fname)
	local out = build.calcsTab.mainOutput
	if not out then return end
	for _, k in ipairs(fingerprintBaseStats) do
		fpf:write(string.format("BASE\t%s\t-\t%s\t-\t%s\t-\n", fname, k, fmtNum(out[k])))
	end
	fpf:flush()
end

-- Capture the top-K nodes by power.singleStat in a stable order so the
-- fingerprint is deterministic across runs. Mirrors what BuildPowerReportList
-- shows the user but keeps only what we need to detect drift.
local function writeReportFingerprint(fpf, fname, statLabel, topK)
	local rows = {}
	for nodeId, node in pairs(build.spec.nodes) do
		if (node.type == "Normal" or node.type == "Keystone" or node.type == "Notable")
			and not node.ascendancyName
			and node.power and node.power.singleStat then
			table.insert(rows, {
				name = node.dn or node.name or ("id="..tostring(nodeId)),
				id = node.id or nodeId,
				power = node.power.singleStat,
				pathPower = node.power.pathPower or 0,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.power ~= b.power then return a.power > b.power end
		-- stable tiebreak on name then id
		if a.name ~= b.name then return a.name < b.name end
		return tostring(a.id) < tostring(b.id)
	end)
	for i = 1, math.min(topK or 10, #rows) do
		local r = rows[i]
		fpf:write(string.format("TOP\t%s\t%s\t%s\t%d\t%s\t%s\n",
			fname, statLabel, r.name, i, fmtNum(r.power), fmtNum(r.pathPower)))
	end
	fpf:flush()
end

local function runStat(stat)
	build.calcsTab.powerStat = stat
	build.calcsTab.powerBuildFlag = false
	-- Drive synchronously so coroutine.running() == nil inside PowerBuilder,
	-- yield checks are no-ops, and the ConPrintf summary fires.
	local before = #capturedLines
	build.calcsTab:PowerBuilder()
	return findReportLine(before + 1)
end

-- Parse the structured ConPrintf line. Accepts both the pre-#2 and post-#2
-- formats (the latter adds "unique pathKeys" and "path hits").
local function parseReport(line)
	if not line then return nil end
	local r = {}
	r.label = line:match("%[(.-)%]")
	r.total = tonumber(line:match("total (%d+) ms")) or 0
	r.calc = tonumber(line:match("calcFunc (%d+) ms")) or 0
	r.pct = tonumber(line:match("%((%d+)%%%)")) or 0
	r.calls = tonumber(line:match("over (%d+) calls")) or 0
	r.uniq = tonumber(line:match("unique modKeys (%d+)")) or 0
	r.uniqPath = tonumber(line:match("unique pathKeys (%d+)")) or 0
	r.hits = tonumber(line:match("cache hits (%d+)")) or 0
	r.pathHits = tonumber(line:match("path hits (%d+)")) or 0
	r.addS = tonumber(line:match("add%-single (%d+)")) or 0
	r.addP = tonumber(line:match("add%-path (%d+)")) or 0
	r.remS = tonumber(line:match("rem%-single (%d+)")) or 0
	r.remP = tonumber(line:match("rem%-path (%d+)")) or 0
	r.clus = tonumber(line:match("cluster (%d+)")) or 0
	return r
end

-- ---- main ----
print(string.format("[baseline] builds=%s", opts.builds))
print(string.format("[baseline] stats=%s repeats=%d", opts.stats, opts.repeats))

local statByLabel = loadStatList()
local stats = pickStats(opts.stats, statByLabel)
if #stats == 0 then
	io.stderr:write("no valid stats selected\n")
	os.exit(1)
end

local files = listBuilds(opts.builds, opts.match)
if #files == 0 then
	io.stderr:write("no builds found under " .. opts.builds .. (opts.match and (" matching '" .. opts.match .. "'") or "") .. "\n")
	os.exit(1)
end
print(string.format("[baseline] %d build(s):", #files))
for _, f in ipairs(files) do print("  " .. f) end

local outf, oerr = io.open(opts.out, "w")
if not outf then
	io.stderr:write("cannot open output " .. opts.out .. ": " .. tostring(oerr) .. "\n")
	os.exit(1)
end
outf:setvbuf("no")
outf:write("build\tstat\trun\ttotal_ms\tcalc_ms\tpct\tcalls\tuniq\tuniqPath\thits\tpathHits\taddS\taddP\tremS\tremP\tclus\n")

-- Sidecar fingerprint file for correctness validation. Same row shape for both
-- BASE (per-build main-output stat values) and TOP (top-10 power-report nodes
-- per (build, stat)). Diffing this file across runs catches calc regressions.
local fpPath = opts.out:gsub("%.tsv$", "") .. ".fp.tsv"
local fpf, fperr = io.open(fpPath, "w")
if not fpf then
	io.stderr:write("cannot open fingerprint output " .. fpPath .. ": " .. tostring(fperr) .. "\n")
	os.exit(1)
end
fpf:setvbuf("no")
fpf:write("type\tbuild\tstat\tkey_or_name\trank\tvalue\tvalue2\n")

for _, fname in ipairs(files) do
	local fullPath = opts.builds .. "\\" .. fname
	print(string.format("[baseline] loading %s", fname))
	local ok, lerr = loadBuild(fullPath)
	if not ok then
		io.stderr:write(string.format("FAIL load %s: %s\n", fname, tostring(lerr)))
	else
		writeBaseFingerprint(fpf, fname)
		for _, stat in ipairs(stats) do
			for r = 1, opts.repeats do
				local line, rerr = runStat(stat)
				if not line then
					io.stderr:write(string.format("FAIL %s | %s: %s\n", fname, stat.label, tostring(rerr)))
				else
					local p = parseReport(line)
					outf:write(string.format("%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n",
						fname, p.label, r, p.total, p.calc, p.pct, p.calls, p.uniq, p.uniqPath, p.hits, p.pathHits, p.addS, p.addP, p.remS, p.remP, p.clus))
					outf:flush()
					-- only write fingerprint on the first repeat; repeats produce
					-- identical reports (cache is per-PowerBuilder-call) so any
					-- drift across repeats would be a deeper concern than these tests
					-- are meant to catch.
					if r == 1 then
						writeReportFingerprint(fpf, fname, stat.label, 10)
					end
				end
				flushCaptured()
			end
		end
	end
end

outf:close()
fpf:close()
print(string.format("[baseline] wrote %s", opts.out))
print(string.format("[baseline] wrote %s", fpPath))
os.exit(0)
