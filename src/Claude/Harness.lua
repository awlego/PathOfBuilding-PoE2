-- Path of Building
--
-- Claude harness: core
-- Owns the Claude Code CLI session (one `claude -p` process per turn, resumed by session id),
-- the chat transcript, harness settings, build-context export, and the "live" channel that lets
-- Claude run Lua inside this running PoB instance (see Claude/pob_live.py).
--
-- Everything Claude-related lives in src/Claude/ (core + system prompt + helper) and
-- src/Classes/ClaudePanel.lua (UI). Runtime data goes to <userPath>/ClaudeData/ (gitignored).
--
local t_insert = table.insert
local t_concat = table.concat
local s_format = string.format

local harness = {
	messages = { },     -- { role = "user"|"assistant"|"tool"|"system"|"error", text = ..., ... }
	running = false,
	runId = 0,
	sessionId = nil,
	turnCost = 0,
	totalCost = 0,
	status = "idle",
	changeCounter = 0,  -- bumps whenever messages change (UI cache invalidation)
}

harness.permissionModes = {
	{ label = "Read-only", mode = "readonly", tooltip = "Claude can read files and query the live build, but cannot edit files or run arbitrary commands." },
	{ label = "Accept edits", mode = "acceptEdits", tooltip = "Claude can read and edit files. Other shell commands are denied (no interactive prompts in the panel)." },
	{ label = "Auto", mode = "auto", tooltip = "Claude Code auto mode: a safety classifier approves or blocks each action. Best for PoB development." },
	{ label = "Bypass (unsafe)", mode = "bypassPermissions", tooltip = "No permission checks at all. Only use if you understand the risk." },
}
harness.models = {
	{ label = "Default", model = "" },
	{ label = "Opus", model = "opus" },
	{ label = "Sonnet", model = "sonnet" },
	{ label = "Haiku", model = "haiku" },
}

harness.settings = {
	open = true,
	width = 460,
	permissionMode = "auto",
	model = "",
	claudePath = "",
	liveEnabled = true,
}

local function fileExists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local function writeFile(path, text)
	local f, err = io.open(path, "wb")
	if not f then
		return nil, err
	end
	f:write(text)
	f:close()
	return true
end

local function winPath(path)
	return (path:gsub("/", "\\"))
end

-- Quote one argument for the Windows command line (CommandLineToArgvW rules)
local function quoteArg(arg)
	arg = tostring(arg)
	if arg ~= "" and not arg:find('[%s"]') then
		return arg
	end
	arg = arg:gsub('(\\*)"', function(bs) return bs .. bs .. '\\"' end)
	arg = arg:gsub("(\\+)$", "%1%1")
	return '"' .. arg .. '"'
end
harness.quoteArg = quoteArg

-- Serialize a Lua value as a Lua literal (for persistence)
local function serialize(v, indent)
	indent = indent or ""
	local t = type(v)
	if t == "string" then
		return s_format("%q", v):gsub("\\\n", "\\n")
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		local parts = { }
		local inner = indent .. "\t"
		local n = #v
		for i = 1, n do
			t_insert(parts, inner .. serialize(v[i], inner))
		end
		local keys = { }
		for k in pairs(v) do
			if type(k) == "string" then
				t_insert(keys, k)
			end
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local val = v[k]
			if type(val) ~= "function" and type(val) ~= "userdata" then
				t_insert(parts, inner .. "[" .. s_format("%q", k) .. "] = " .. serialize(val, inner))
			end
		end
		if #parts == 0 then
			return "{ }"
		end
		return "{\n" .. t_concat(parts, ",\n") .. "\n" .. indent .. "}"
	end
	return "nil"
end
harness.serialize = serialize

local function loadLuaTable(path)
	local text = readFile(path)
	if not text then
		return nil
	end
	local fn = loadstring("return " .. text)
	if not fn then
		return nil
	end
	setfenv(fn, { })
	local ok, res = pcall(fn)
	if ok and type(res) == "table" then
		return res
	end
end

---------------------------------------------------------------------------------------------------
-- Paths / init
---------------------------------------------------------------------------------------------------

function harness:Init()
	if self.initialised then
		return
	end
	self.initialised = true
	self.scriptPath = GetScriptPath():gsub("\\", "/")
	if launch.devMode then
		self.repoRoot = self.scriptPath:gsub("/[^/]+$", "")
	else
		self.repoRoot = self.scriptPath
	end
	self.claudeDir = self.scriptPath .. "/Claude/"
	self.dataDir = (main.userPath or (self.scriptPath .. "/")) .. "ClaudeData/"
	self.liveDir = self.dataDir .. "live/"
	self.ctxDir = self.dataDir .. "context/"
	MakeDir(self.dataDir)
	MakeDir(self.liveDir)
	MakeDir(self.ctxDir)
	self.chatsDir = self.dataDir .. "chats/"
	MakeDir(self.chatsDir)
	local settings = loadLuaTable(self.dataDir .. "settings.lua")
	if settings then
		for k, v in pairs(settings) do
			self.settings[k] = v
		end
	end
	self:LoadChatIndex()
	-- Migrate the single-conversation file used before chat history existed
	local legacy = loadLuaTable(self.dataDir .. "chat.lua")
	if legacy then
		os.remove(self.dataDir .. "chat.lua")
		if legacy.messages and #legacy.messages > 0 then
			self:ApplyChat(legacy)
			self.chatId = nil
			self:SaveChat()
		end
	elseif self.settings.currentChatId then
		self:OpenChat(self.settings.currentChatId)
	end
	self.lastLivePoll = 0
	-- Live-channel requests left over from a previous run are stale
	self:ClearLiveDir()
end

function harness:SaveSettings()
	writeFile(self.dataDir .. "settings.lua", serialize(self.settings))
end

---------------------------------------------------------------------------------------------------
-- Chat history: one file per conversation in ClaudeData/chats/<id>.lua, plus chats/index.lua
-- holding the metadata shown in the History list (so the list never loads every transcript)
---------------------------------------------------------------------------------------------------

function harness:LoadChatIndex()
	local index = loadLuaTable(self.chatsDir .. "index.lua")
	self.chatIndex = index and index.chats or { }
	self:SortChatIndex()
end

function harness:SortChatIndex()
	table.sort(self.chatIndex, function(a, b)
		if (a.updated or 0) ~= (b.updated or 0) then
			return (a.updated or 0) > (b.updated or 0)
		end
		return tostring(a.id) > tostring(b.id)
	end)
end

function harness:SaveChatIndex()
	writeFile(self.chatsDir .. "index.lua", serialize({ chats = self.chatIndex }))
end

function harness:FindChatEntry(id)
	for i, entry in ipairs(self.chatIndex or { }) do
		if entry.id == id then
			return entry, i
		end
	end
end

local function chatTitle(messages)
	for _, m in ipairs(messages) do
		if m.role == "user" and m.text and m.text:match("%S") then
			local title = m.text:gsub("%s+", " "):gsub("^ ", "")
			if #title > 80 then
				title = title:sub(1, 77) .. "..."
			end
			return title
		end
	end
	return "(empty conversation)"
end

function harness:ApplyChat(chat)
	self.sessionId = chat.sessionId
	self.messages = chat.messages or { }
	self.totalCost = chat.totalCost or 0
	self.lastBuildKey = chat.lastBuildKey
	self.lastContextXML = nil
	self.lastTurnInfo = nil
	-- Interrupted turn (e.g. reload mid-turn): close any streaming message
	for _, msg in ipairs(self.messages) do
		msg.streaming = nil
	end
	self:Touch()
end

function harness:SaveChat()
	if not self.chatsDir then
		return
	end
	local userCount = 0
	for _, m in ipairs(self.messages) do
		if m.role == "user" then
			userCount = userCount + 1
		end
	end
	if userCount == 0 then
		-- Nothing worth keeping yet; don't litter the history with empty chats
		return
	end
	if not self.chatId then
		self.chatId = os.date("%Y%m%d-%H%M%S") .. "-" .. string.format("%04x", math.random(0, 65535))
		self.chatCreated = os.time()
	end
	local keep = { }
	local first = math.max(1, #self.messages - 300)
	for i = first, #self.messages do
		local m = self.messages[i]
		t_insert(keep, { role = m.role, text = m.text, toolName = m.toolName, toolId = m.toolId, isError = m.isError, result = m.result, sub = m.sub, ts = m.ts, done = m.done })
	end
	writeFile(self.chatsDir .. self.chatId .. ".lua", serialize({ id = self.chatId, sessionId = self.sessionId, messages = keep, totalCost = self.totalCost, lastBuildKey = self.lastBuildKey }))
	local entry = self:FindChatEntry(self.chatId)
	if not entry then
		entry = { id = self.chatId, created = self.chatCreated or os.time() }
		t_insert(self.chatIndex, entry)
	end
	entry.title = entry.customTitle or chatTitle(self.messages)
	entry.updated = os.time()
	entry.messages = userCount
	entry.build = self.lastBuildName or entry.build
	entry.cost = self.totalCost
	entry.sessionId = self.sessionId
	self:SortChatIndex()
	self:SaveChatIndex()
	if self.settings.currentChatId ~= self.chatId then
		self.settings.currentChatId = self.chatId
		self:SaveSettings()
	end
end

-- Drop a running turn without waiting for it (used when switching conversations)
function harness:AbandonRun()
	if not self.running then
		return
	end
	if self.pid then
		self:KillProcess(self.pid)
	elseif self.subId then
		AbortSubScript(self.subId)
		launch.subScripts[self.subId] = nil
	end
	if self.currentAssistant then
		self.currentAssistant.streaming = nil
	end
	self:AddMessage("system", "Stopped (switched conversation).")
	self:SaveChat()
	self.runId = self.runId + 1
	self.running = false
	self.subId = nil
	self.pid = nil
	self.currentAssistant = nil
	self.pendingReload = nil
	self.stopRequested = nil
	self.gotResult = nil
	self.status = "idle"
end

function harness:OpenChat(id)
	local chat = loadLuaTable(self.chatsDir .. id .. ".lua")
	if not chat then
		local _, i = self:FindChatEntry(id)
		if i then
			table.remove(self.chatIndex, i)
			self:SaveChatIndex()
		end
		return false
	end
	self:AbandonRun()
	self:SaveChat()
	self:ApplyChat(chat)
	self.chatId = id
	local entry = self:FindChatEntry(id)
	self.chatCreated = entry and entry.created
	self.settings.currentChatId = id
	self:SaveSettings()
	return true
end

function harness:DeleteChat(id)
	os.remove(self.chatsDir .. id .. ".lua")
	local _, i = self:FindChatEntry(id)
	if i then
		table.remove(self.chatIndex, i)
		self:SaveChatIndex()
	end
	if id == self.chatId then
		self.chatId = nil
		self:NewChat()
	end
end

function harness:Touch()
	self.changeCounter = self.changeCounter + 1
end

function harness:AddMessage(role, text, extra)
	local msg = extra or { }
	msg.role = role
	msg.text = text or ""
	msg.ts = os.time()
	t_insert(self.messages, msg)
	self:Touch()
	return msg
end

function harness:NewChat()
	self:AbandonRun()
	self:SaveChat()
	self.chatId = nil
	self.chatCreated = nil
	self.messages = { }
	self.sessionId = nil
	self.totalCost = 0
	self.lastContextXML = nil
	self.lastBuildKey = nil
	self.lastTurnInfo = nil
	self.settings.currentChatId = nil
	self:SaveSettings()
	self:Touch()
end

---------------------------------------------------------------------------------------------------
-- Claude CLI
---------------------------------------------------------------------------------------------------

function harness:GetClaudeExe()
	if self.settings.claudePath and self.settings.claudePath ~= "" then
		return self.settings.claudePath
	end
	local profile = os.getenv("USERPROFILE")
	if profile then
		local candidate = profile .. "\\.local\\bin\\claude.exe"
		if fileExists(candidate) then
			return candidate
		end
	end
	local appdata = os.getenv("APPDATA")
	if appdata and fileExists(appdata .. "\\npm\\claude.cmd") then
		return appdata .. "\\npm\\claude.cmd"
	end
	return "claude.exe"
end

-- Show repo-relative paths in tool lines (the panel is narrow)
function harness:ShortenPaths(text)
	local root = self.repoRoot or ""
	if root == "" then
		return text
	end
	for _, prefix in ipairs({ root .. "/", winPath(root) .. "\\" }) do
		local i = 1
		while true do
			local s, e = text:find(prefix, i, true)
			if not s then
				break
			end
			text = text:sub(1, s - 1) .. text:sub(e + 1)
			i = s
		end
	end
	return text
end

function harness:LiveHelperCommand()
	return s_format('python "%s" --dir "%s"', ((self.claudeDir .. "pob_live.py"):gsub("\\", "/")), (self.liveDir:gsub("\\", "/")))
end

function harness:BuildCommandLine()
	local exe = self:GetClaudeExe()
	local args = { "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages" }
	if self.sessionId then
		t_insert(args, "--resume")
		t_insert(args, self.sessionId)
	else
		-- The appended system prompt is recorded with the session, so only the first turn sends it
		t_insert(args, "--append-system-prompt-file")
		t_insert(args, winPath(self.claudeDir .. "SystemPrompt.md"))
	end
	if self.settings.model and self.settings.model ~= "" then
		t_insert(args, "--model")
		t_insert(args, self.settings.model)
	end
	local mode = self.settings.permissionMode
	local readTools = { "Read", "Grep", "Glob", "WebSearch", "WebFetch", "TodoWrite", "Bash(python *pob_live.py*)" }
	if mode == "readonly" then
		t_insert(args, "--permission-mode")
		t_insert(args, "dontAsk")
		t_insert(args, "--allowedTools")
		for _, tool in ipairs(readTools) do
			t_insert(args, tool)
		end
	elseif mode == "acceptEdits" then
		t_insert(args, "--permission-mode")
		t_insert(args, "acceptEdits")
		t_insert(args, "--allowedTools")
		for _, tool in ipairs(readTools) do
			t_insert(args, tool)
		end
	elseif mode == "bypassPermissions" then
		t_insert(args, "--dangerously-skip-permissions")
	else
		t_insert(args, "--permission-mode")
		t_insert(args, "auto")
	end
	t_insert(args, "--add-dir")
	t_insert(args, winPath(self.dataDir))
	local quoted = { }
	for _, a in ipairs(args) do
		t_insert(quoted, quoteArg(a))
	end
	local cmd = quoteArg(winPath(exe)) .. " " .. t_concat(quoted, " ")
	if exe:lower():match("%.cmd$") or exe:lower():match("%.bat$") then
		cmd = 'cmd.exe /d /s /c "' .. cmd .. '"'
	end
	return cmd
end

-- Kill the running CLI process tree (claude spawns shells for tools)
function harness:KillProcess(pid)
	if not pid then
		return
	end
	local okFfi, ffi = pcall(require, "ffi")
	if okFfi then
		pcall(ffi.cdef, [[
			typedef struct { uint32_t cb; void* a; void* b; void* c; uint32_t d[8]; uint16_t e, f; void* g; void* h; void* i; void* j; } PB_KILL_SI;
			typedef struct { void* hProcess; void* hThread; uint32_t pid; uint32_t tid; } PB_KILL_PI;
			int CreateProcessA(const char* app, char* cmd, void* pa, void* ta, int inherit, uint32_t flags, void* env, const char* cwd, PB_KILL_SI* si, PB_KILL_PI* pi);
			int CloseHandle(void* h);
		]])
		local si = ffi.new("PB_KILL_SI")
		si.cb = ffi.sizeof(si)
		local pi = ffi.new("PB_KILL_PI")
		local cmd = ffi.new("char[?]", 128, "taskkill.exe /F /T /PID " .. tostring(pid))
		if ffi.C.CreateProcessA(nil, cmd, nil, nil, 0, 0x08000000, nil, nil, si, pi) ~= 0 then
			ffi.C.CloseHandle(pi.hProcess)
			ffi.C.CloseHandle(pi.hThread)
			return
		end
	end
	os.execute("taskkill /F /T /PID " .. tostring(pid))
end

function harness:Send(text, build)
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" or self.running then
		return
	end
	if text:sub(1, 1) == "/" then
		if self:HandleSlashCommand(text, build) then
			return
		end
	end
	self:Init()
	local context = build and self:BuildContext(build) or ""
	self:AddMessage("user", text)
	local prompt = context .. text
	local runnerText = readFile(self.claudeDir .. "ProcessRunner.lua")
	if not runnerText then
		self:AddMessage("error", "Missing " .. self.claudeDir .. "ProcessRunner.lua")
		return
	end
	self.runId = self.runId + 1
	self.pid = nil
	self.turnCost = 0
	self.currentAssistant = nil
	self.toolsById = { }
	self.turnStart = GetTime()
	self.status = "Starting Claude..."
	local cmd = self:BuildCommandLine()
	self.lastCommandLine = cmd
	local runId = self.runId
	local id = LaunchSubScript(runnerText, "", "ClaudeHarnessEvent,ConPrintf", runId, cmd, winPath(self.repoRoot), prompt)
	if not id then
		self:AddMessage("error", "Failed to launch the Claude sub-script.")
		return
	end
	self.running = true
	self.subId = id
	launch.subScripts[id] = {
		type = "CUSTOM",
		callback = function(status, exitCode)
			if runId == self.runId then
				self:OnProcessFinished(status, exitCode)
			end
		end,
		errorCallback = function(errMsg)
			if runId == self.runId then
				self:AddMessage("error", "Claude runner error: " .. tostring(errMsg))
				self:OnProcessFinished("error")
			end
		end,
	}
	self:SaveChat()
end

function harness:Stop()
	if not self.running then
		return
	end
	self.stopRequested = true
	if self.pid then
		self:KillProcess(self.pid)
	elseif self.subId then
		AbortSubScript(self.subId)
		launch.subScripts[self.subId] = nil
		self:OnProcessFinished("aborted")
	end
	self.status = "Stopping..."
end

function harness:OnProcessFinished(status, exitCode)
	if not self.running then
		return
	end
	self.running = false
	self.subId = nil
	self.pid = nil
	if self.currentAssistant then
		self.currentAssistant.streaming = nil
		self.currentAssistant = nil
	end
	for _, msg in pairs(self.toolsById or { }) do
		if not msg.done then
			msg.done = true
			msg.isError = true
			msg.result = msg.result or "(no result: the turn ended first)"
		end
	end
	if self.stopRequested then
		self:AddMessage("system", "Stopped.")
	elseif not self.gotResult then
		if status == "exit" and exitCode and exitCode ~= 0 then
			self:AddMessage("error", s_format("Claude exited with code %d before finishing. Command:\n%s", exitCode, self.lastCommandLine or "?"))
		elseif status ~= "exit" then
			self:AddMessage("error", "Claude run ended: " .. tostring(status))
		end
	end
	self.stopRequested = nil
	self.gotResult = nil
	self.status = "idle"
	self:Touch()
	self:SaveChat()
	if self.pendingReload then
		self.pendingReload = nil
		self:Reload()
	end
end

local RS, US = "\30", "\31"
function harness:OnEvent(runId, payload)
	if runId ~= self.runId then
		return
	end
	for evText in (payload .. RS):gmatch("(.-)" .. RS) do
		local f = { }
		for field in (evText .. US):gmatch("(.-)" .. US) do
			t_insert(f, field)
		end
		self:HandleEvent(f)
	end
	self:Touch()
end

function harness:HandleEvent(f)
	local kind = f[1]
	if kind == "pid" then
		self.pid = tonumber(f[2])
		self.status = "Waiting for Claude..."
		if self.stopRequested then
			self:KillProcess(self.pid)
		end
	elseif kind == "init" then
		if f[2] ~= "" then
			self.sessionId = f[2]
		end
		self.model = f[3]
		self.status = "Thinking..."
	elseif kind == "thinking" then
		self.status = "Thinking..."
	elseif kind == "textstart" then
		self.currentAssistant = self:AddMessage("assistant", "", { streaming = true })
		self.status = "Writing..."
	elseif kind == "text" then
		if not self.currentAssistant then
			self.currentAssistant = self:AddMessage("assistant", "", { streaming = true })
		end
		self.currentAssistant.text = self.currentAssistant.text .. f[2]
	elseif kind == "tool" then
		if self.currentAssistant then
			self.currentAssistant.streaming = nil
			self.currentAssistant = nil
		end
		local msg = self:AddMessage("tool", self:ShortenPaths(f[4] or ""), { toolId = f[2], toolName = f[3], sub = f[5] == "1" })
		self.toolsById[f[2]] = msg
		self.status = "Running " .. (f[3] or "tool") .. "..."
	elseif kind == "toolresult" then
		local msg = self.toolsById[f[2]]
		if msg then
			msg.isError = f[3] == "1"
			msg.result = f[4]
			msg.done = true
		end
		self.status = "Thinking..."
	elseif kind == "result" then
		self.gotResult = true
		if self.currentAssistant then
			self.currentAssistant.streaming = nil
			self.currentAssistant = nil
		end
		local isError = f[3] == "1"
		local cost = tonumber(f[5]) or 0
		self.turnCost = cost
		self.totalCost = (self.totalCost or 0) + cost
		if f[8] and f[8] ~= "" then
			self.sessionId = f[8]
		end
		if isError or (f[2] and f[2] ~= "success") then
			self:AddMessage("error", (f[4] ~= "" and f[4]) or ("Claude finished with: " .. tostring(f[2])))
		end
		if f[9] and f[9] ~= "" then
			self:AddMessage("system", "Permission denied (change the permission mode in the panel header to allow):\n" .. f[9])
		end
		self.lastTurnInfo = s_format("$%.3f  %.1fs  %s turns", cost, (tonumber(f[6]) or 0) / 1000, f[7] or "?")
	elseif kind == "fatal" then
		self:AddMessage("error", f[2])
	elseif kind == "stderr" or kind == "raw" then
		if f[2] and f[2]:match("%S") then
			self:AddMessage("system", f[2])
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Slash commands handled locally
---------------------------------------------------------------------------------------------------

function harness:HandleSlashCommand(text, build)
	local cmd = text:match("^/(%S+)")
	if cmd == "clear" or cmd == "new" then
		self:NewChat()
		return true
	elseif cmd == "history" then
		self.showHistory = true
		self:Touch()
		return true
	elseif cmd == "title" then
		local title = text:match("^/%S+%s+(.-)%s*$")
		self:SaveChat()
		local entry = self.chatId and self:FindChatEntry(self.chatId)
		if entry and title and title ~= "" then
			entry.customTitle = title
			entry.title = title
			self:SaveChatIndex()
			self:AddMessage("system", "Conversation renamed to: " .. title)
		else
			self:AddMessage("system", "Usage: /title <name> (after the conversation has at least one message)")
		end
		return true
	elseif cmd == "reload" then
		self:RequestReload()
		return true
	elseif cmd == "cmd" then
		self:AddMessage("system", "Next command line:\n" .. self:BuildCommandLine())
		return true
	elseif cmd == "context" then
		if build then
			self:BuildContext(build, true)
			self:AddMessage("system", "Context written to " .. self.ctxDir .. "\n\n" .. (readFile(self.ctxDir .. "build_summary.md") or ""):sub(1, 4000))
		end
		return true
	elseif cmd == "help" then
		self:AddMessage("system", "Local commands: /new (fresh conversation), /history (past conversations), /title <name> (rename this conversation), /reload (restart PoB, keeps chat + build), /context (show the build summary Claude sees), /cmd (show CLI command line). Anything else is sent to Claude.")
		return true
	end
end

---------------------------------------------------------------------------------------------------
-- Build context export
---------------------------------------------------------------------------------------------------

local function stripCodes(s)
	return (StripEscapes(tostring(s or "")):gsub("%s+$", ""))
end

function harness:BuildSummary(build)
	local lines = { }
	local function add(s)
		t_insert(lines, s)
	end
	local spec = build.spec
	local className = spec and spec.curClassName or "?"
	local ascName = spec and spec.curAscendClassName or "None"
	add("# " .. (build.buildName or "Unnamed build"))
	add("")
	add(s_format("- Class: %s / %s, level %s", className, ascName ~= "None" and ascName or "no ascendancy", tostring(build.characterLevel)))
	add("- Build file: " .. tostring(build.dbFileName or "(unsaved, no file)"))
	add("- Game version / tree: " .. tostring(build.targetVersion) .. " / " .. tostring(spec and spec.treeVersion))
	add("- Active PoB tab: " .. tostring(build.viewMode))
	local mainGroup = build.skillsTab.socketGroupList[build.mainSocketGroup]
	if mainGroup then
		add("- Main skill group: " .. stripCodes(mainGroup.displayLabel or mainGroup.label or "?"))
	end
	local env = build.calcsTab.mainEnv
	if env and env.player and env.player.mainSkill then
		local ms = env.player.mainSkill
		add("- Main skill (calculated): " .. tostring(ms.activeEffect and ms.activeEffect.grantedEffect and ms.activeEffect.grantedEffect.name or "?"))
	end
	add("")
	add("## Sidebar stats (as shown in PoB)")
	for _, line in ipairs(build.controls.statBox.list or { }) do
		local l, r = stripCodes(line[1]), stripCodes(line[2])
		if l ~= "" or r ~= "" then
			add("- " .. l .. (r ~= "" and (" " .. r) or ""))
		end
	end
	local warnings = build.controls.warnings and build.controls.warnings.lines
	if warnings and #warnings > 0 then
		add("")
		add("## Warnings")
		for _, w in ipairs(warnings) do
			add("- " .. stripCodes(w))
		end
	end
	add("")
	add("## Skills (socket groups)")
	for i, group in ipairs(build.skillsTab.socketGroupList) do
		local gems = { }
		for _, gem in ipairs(group.gemList or { }) do
			local name = gem.grantedEffect and gem.grantedEffect.name or gem.nameSpec or "?"
			t_insert(gems, s_format("%s %s/%s%s", name, tostring(gem.level), tostring(gem.quality or 0), gem.enabled == false and " (disabled)" or ""))
		end
		add(s_format("%d. %s%s%s%s: %s", i, stripCodes(group.label ~= "" and group.label or (group.displayLabel or "")),
			group.slot and (" [" .. group.slot .. "]") or "", group.enabled == false and " (disabled)" or "",
			i == build.mainSocketGroup and " **MAIN**" or "", t_concat(gems, ", ")))
	end
	add("")
	add("## Equipped items")
	local itemsTab = build.itemsTab
	for _, slot in ipairs(itemsTab.orderedSlots or { }) do
		local item = slot.selItemId and slot.selItemId ~= 0 and itemsTab.items[slot.selItemId]
		if item and (not slot.weaponSet or slot.weaponSet == (itemsTab.activeItemSet and itemsTab.activeItemSet.useSecondWeaponSet and 2 or 1)) then
			add("")
			add("### " .. slot.slotName)
			add("```")
			local ok, raw = pcall(item.BuildRaw, item)
			add(ok and raw or (item.name or "?"))
			add("```")
		end
	end
	add("")
	add("## Allocated keystones / notables / ascendancy")
	local notables = { }
	for _, node in pairs(spec.allocNodes or { }) do
		if node.type == "Keystone" or node.type == "Notable" or (node.ascendancyName and node.type ~= "AscendClassStart") then
			t_insert(notables, (node.ascendancyName and ("[" .. node.ascendancyName .. "] ") or (node.type == "Keystone" and "[Keystone] " or "")) .. tostring(node.dn))
		end
	end
	table.sort(notables)
	for _, n in ipairs(notables) do
		add("- " .. n)
	end
	add("")
	add("## Non-default configuration")
	local cfgKeys = { }
	local configTab = build.configTab
	for k, v in pairs(configTab.input or { }) do
		local okDef, default = pcall(configTab.GetDefaultState, configTab, k, type(v))
		if v ~= nil and v ~= "" and not (okDef and v == default) then
			t_insert(cfgKeys, k .. " = " .. tostring(v))
		end
	end
	table.sort(cfgKeys)
	for _, c in ipairs(cfgKeys) do
		add("- " .. c)
	end
	return t_concat(lines, "\n")
end

-- Writes context files and returns the <pob_context> header to prepend to the user's message
function harness:BuildContext(build, force)
	self:Init()
	local okXml, xmlText = pcall(build.SaveDB, build, "context")
	if not okXml then
		xmlText = nil
	end
	local okSum, summary = pcall(self.BuildSummary, self, build)
	if not okSum then
		summary = "(summary failed: " .. tostring(summary) .. ")"
	end
	if xmlText then
		writeFile(self.ctxDir .. "build.xml", xmlText)
	end
	writeFile(self.ctxDir .. "build_summary.md", summary)
	local buildKey = tostring(build.dbFileName or build.buildName)
	local changed = force or xmlText ~= self.lastContextXML
	local switched = buildKey ~= self.lastBuildKey
	self.lastContextXML = xmlText
	self.lastBuildKey = buildKey
	self.lastBuildName = build.buildName
	local header = { "<pob_context>" }
	t_insert(header, s_format("Open build: %s (%s / %s, level %s). Active tab: %s. Unsaved changes: %s.",
		tostring(build.buildName), tostring(build.spec.curClassName), tostring(build.spec.curAscendClassName), tostring(build.characterLevel),
		tostring(build.viewMode), build.unsaved and "yes" or "no"))
	t_insert(header, "Build summary (stats, skills, items, notables, config): " .. winPath(self.ctxDir .. "build_summary.md"))
	t_insert(header, "Full build XML: " .. winPath(self.ctxDir .. "build.xml"))
	if self.settings.liveEnabled then
		t_insert(header, "Live PoB Lua channel (Bash; pipe Lua on stdin via a quoted heredoc):\n" .. self:LiveHelperCommand() .. " - <<'LUA'\nreturn pob.stat('Life')\nLUA")
	end
	if switched and self.sessionId then
		t_insert(header, "NOTE: the user switched to a different build since the last message.")
	elseif changed and self.sessionId then
		t_insert(header, "NOTE: the build changed since the last message; re-read the summary if it matters.")
	elseif self.sessionId then
		t_insert(header, "Build unchanged since the last message.")
	end
	if not self.sessionId or switched then
		-- First message about this build: inline the stat block so simple questions need no tool calls
		local statBlock = summary:match("## Sidebar stats.-\n(.-)\n\n## ") or ""
		t_insert(header, "Key stats:\n" .. statBlock)
	end
	t_insert(header, "</pob_context>")
	t_insert(header, "")
	return t_concat(header, "\n") .. "\n"
end

---------------------------------------------------------------------------------------------------
-- Live channel: Claude runs Lua in this PoB instance via Claude/pob_live.py
---------------------------------------------------------------------------------------------------

function harness:ClearLiveDir()
	local handle = NewFileSearch(self.liveDir .. "*")
	local stale = { }
	while handle do
		t_insert(stale, handle:GetFileName())
		if not handle:NextFile() then
			break
		end
	end
	for _, name in ipairs(stale) do
		os.remove(self.liveDir .. name)
	end
end

local function dump(v, depth, seen, indent)
	depth = depth or 3
	seen = seen or { }
	indent = indent or ""
	local t = type(v)
	if t == "string" then
		return s_format("%q", v)
	elseif t ~= "table" then
		return tostring(v)
	end
	if seen[v] then
		return "<cycle>"
	end
	if depth <= 0 then
		return "{...}"
	end
	seen[v] = true
	local keys = { }
	for k in pairs(v) do
		t_insert(keys, k)
	end
	table.sort(keys, function(a, b)
		if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then
			return a < b
		end
		return type(a) < type(b)
	end)
	local parts = { }
	local inner = indent .. "  "
	for i, k in ipairs(keys) do
		if i > 200 then
			t_insert(parts, inner .. s_format("... (%d more keys)", #keys - 200))
			break
		end
		t_insert(parts, inner .. (type(k) == "string" and k or ("[" .. tostring(k) .. "]")) .. " = " .. dump(v[k], depth - 1, seen, inner))
	end
	seen[v] = nil
	if #parts == 0 then
		return "{}"
	end
	return "{\n" .. t_concat(parts, ",\n") .. "\n" .. indent .. "}"
end
harness.dump = dump

function harness:MakeLiveEnv(build, out)
	local pob = { }
	pob.build = build
	pob.harness = self
	pob.dump = dump
	function pob.out()
		return build.calcsTab.mainOutput
	end
	function pob.stat(...)
		local res = { }
		for _, name in ipairs({ ... }) do
			res[name] = build.calcsTab.mainOutput[name]
		end
		return res
	end
	function pob.recalc()
		wipeGlobalCache()
		build.outputRevision = build.outputRevision + 1
		build.calcsTab:BuildOutput()
		build:RefreshStatList()
		build.configTab.calcFunc, build.configTab.calcBase = build.calcsTab:GetMiscCalculator()
		build.buildFlag = true
		return build.calcsTab.mainOutput
	end
	function pob.stats()
		local res = { }
		for _, line in ipairs(build.controls.statBox.list or { }) do
			local l, r = stripCodes(line[1]), stripCodes(line[2])
			if l ~= "" or r ~= "" then
				t_insert(res, l .. " " .. r)
			end
		end
		return t_concat(res, "\n")
	end
	function pob.summary()
		return self:BuildSummary(build)
	end
	function pob.setConfig(var, value)
		build.configTab.input[var] = value
		build.configTab:UpdateControls()
		build.configTab:BuildModList()
		build.configTab.modFlag = true
		return pob.recalc()
	end
	function pob.addItem(raw, equip)
		local itemsTab = build.itemsTab
		itemsTab:CreateDisplayItemFromRaw(raw, true)
		local item = itemsTab.displayItem
		if not item then
			error("Could not parse item text")
		end
		itemsTab:AddDisplayItem(not equip)
		itemsTab.modFlag = true
		pob.recalc()
		return item
	end
	function pob.equip(itemId, slotName)
		local itemsTab = build.itemsTab
		local item = itemsTab.items[itemId]
		slotName = slotName or (item and item:GetPrimarySlot())
		local slot = itemsTab.slots[slotName]
		if not slot then
			error("Unknown slot " .. tostring(slotName))
		end
		slot:SetSelItemId(itemId)
		itemsTab:PopulateSlots()
		itemsTab:AddUndoState()
		itemsTab.modFlag = true
		return pob.recalc()
	end
	function pob.notify(text)
		self:AddMessage("system", tostring(text))
	end
	function pob.reload()
		self:RequestReload()
		return self.running and "PoB will reload after this turn finishes" or "PoB is reloading now"
	end
	function pob.setTab(mode)
		build.viewMode = mode
	end
	local env = setmetatable({
		pob = pob,
		build = build,
		print = function(...)
			local parts = { }
			for i = 1, select("#", ...) do
				t_insert(parts, tostring((select(i, ...))))
			end
			t_insert(out, t_concat(parts, "\t"))
		end,
	}, { __index = _G })
	return env
end

function harness:RunLiveRequest(build, code)
	local out = { }
	local fn, err = loadstring(code, "=live")
	if not fn then
		return "ERROR\n" .. tostring(err)
	end
	setfenv(fn, self:MakeLiveEnv(build, out))
	local res = { xpcall(fn, debug.traceback) }
	local text = t_concat(out, "\n")
	if not res[1] then
		return "ERROR\n" .. (text ~= "" and (text .. "\n") or "") .. tostring(res[2])
	end
	local rets = { }
	for i = 2, table.maxn(res) do
		t_insert(rets, dump(res[i], 3))
	end
	if #rets > 0 then
		text = text .. (text ~= "" and "\n" or "") .. "=> " .. t_concat(rets, ", ")
	end
	return "OK\n" .. text
end

function harness:PollLive(build)
	if not self.settings.liveEnabled then
		return
	end
	local now = GetTime()
	if now - (self.lastLivePoll or 0) < 150 then
		return
	end
	self.lastLivePoll = now
	local handle = NewFileSearch(self.liveDir .. "req_*.lua")
	local reqs = { }
	while handle do
		t_insert(reqs, handle:GetFileName())
		if not handle:NextFile() then
			break
		end
	end
	table.sort(reqs)
	for _, name in ipairs(reqs) do
		local id = name:match("^req_(.+)%.lua$")
		local code = readFile(self.liveDir .. name)
		os.remove(self.liveDir .. name)
		if id and code then
			local ok, result = pcall(self.RunLiveRequest, self, build, code)
			if not ok then
				result = "ERROR\n" .. tostring(result)
			end
			self.liveCount = (self.liveCount or 0) + 1
			writeFile(self.liveDir .. "res_" .. id .. ".tmp", result)
			os.rename(self.liveDir .. "res_" .. id .. ".tmp", self.liveDir .. "res_" .. id .. ".txt")
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Reload PoB (pick up code edits) while keeping the chat and the open build
---------------------------------------------------------------------------------------------------

function harness:RequestReload()
	if self.running then
		self.pendingReload = true
		self:AddMessage("system", "PoB will reload when Claude finishes this turn.")
	else
		self:Reload()
	end
end

function harness:Reload()
	self:SaveChat()
	self:SaveSettings()
	local build = main.modes and main.modes.BUILD
	if main.mode == "BUILD" and build then
		writeFile(self.dataDir .. "reload_state.lua", serialize({ viewMode = build.viewMode }))
		if build.unsaved and not launch.devMode then
			-- Outside dev mode Shutdown() doesn't auto-save; keep the work in a temp file instead
			local xmlText = build:SaveDB("reload")
			if xmlText then
				writeFile(self.dataDir .. "reload_build.xml", xmlText)
				writeFile(self.dataDir .. "reload_build_meta.lua", serialize({ dbFileName = build.dbFileName or false, buildName = build.buildName }))
			end
		end
	end
	launch.doRestart = "Reloading PoB for Claude..."
end

-- Called from Main after settings are loaded
function harness:OnMainInit()
	self:Init()
	local meta = loadLuaTable(self.dataDir .. "reload_build_meta.lua")
	local xmlText = readFile(self.dataDir .. "reload_build.xml")
	os.remove(self.dataDir .. "reload_build_meta.lua")
	os.remove(self.dataDir .. "reload_build.xml")
	if meta and xmlText then
		main:SetMode("BUILD", meta.dbFileName or false, meta.buildName, xmlText)
		self.restoreUnsaved = true
	end
	self.restoreState = loadLuaTable(self.dataDir .. "reload_state.lua")
	os.remove(self.dataDir .. "reload_state.lua")
end

function harness:OnBuildInit(build)
	self:Init()
	if self.restoreState then
		if self.restoreState.viewMode then
			build.viewMode = self.restoreState.viewMode
		end
		self.restoreState = nil
	end
	if self.restoreUnsaved then
		build.modFlag = true
		self.restoreUnsaved = nil
	end
end

function ClaudeHarnessEvent(runId, payload)
	harness:OnEvent(runId, payload)
end

return harness
