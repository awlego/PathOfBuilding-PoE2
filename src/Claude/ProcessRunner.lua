-- Path of Building
--
-- Claude harness: process runner (sub-script)
-- Runs inside a SimpleGraphic sub-script thread (separate Lua state). Spawns the Claude Code CLI
-- with hidden console + redirected pipes via LuaJIT FFI, writes the prompt to stdin, then reads
-- stream-json lines from stdout and forwards compact events to the main thread through the
-- ClaudeHarnessEvent sub-call.
--
-- Wire format to the main thread (one sub-call per stdout chunk, batching many events):
--   events are separated by \30 (RS), fields by \31 (US); first field is the event kind.
--
-- Args: runId, cmdLine, cwd, stdinText
local runId, cmdLine, cwd, stdinText = ...

local RS, US = "\30", "\31"

local function emit(list)
	if #list > 0 then
		ClaudeHarnessEvent(runId, table.concat(list, RS))
	end
end

local function ev(kind, ...)
	local parts = { kind }
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		parts[#parts + 1] = (tostring(v == nil and "" or v)):gsub("[\30\31]", " ")
	end
	return table.concat(parts, US)
end

local okFfi, ffi = pcall(require, "ffi")
if not okFfi then
	emit({ ev("fatal", "LuaJIT FFI is not available in sub-scripts; cannot launch Claude.") })
	return "noffi"
end
local okJson, json = pcall(require, "dkjson")
if not okJson then
	json = nil
end

ffi.cdef[[
typedef void* HANDLE;
typedef struct { uint32_t nLength; void* lpSecurityDescriptor; int bInheritHandle; } PB_SECURITY_ATTRIBUTES;
typedef struct {
	uint32_t cb; uint16_t* lpReserved; uint16_t* lpDesktop; uint16_t* lpTitle;
	uint32_t dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
	uint16_t wShowWindow, cbReserved2; uint8_t* lpReserved2;
	HANDLE hStdInput, hStdOutput, hStdError;
} PB_STARTUPINFOW;
typedef struct { HANDLE hProcess; HANDLE hThread; uint32_t dwProcessId; uint32_t dwThreadId; } PB_PROCESS_INFORMATION;
int CreatePipe(HANDLE* r, HANDLE* w, PB_SECURITY_ATTRIBUTES* sa, uint32_t size);
int SetHandleInformation(HANDLE h, uint32_t mask, uint32_t flags);
int CreateProcessW(const uint16_t* app, uint16_t* cmd, void* pa, void* ta, int inherit, uint32_t flags, void* env, const uint16_t* cwd, PB_STARTUPINFOW* si, PB_PROCESS_INFORMATION* pi);
int ReadFile(HANDLE h, void* buf, uint32_t n, uint32_t* read, void* ov);
int WriteFile(HANDLE h, const void* buf, uint32_t n, uint32_t* written, void* ov);
int CloseHandle(HANDLE h);
uint32_t WaitForSingleObject(HANDLE h, uint32_t ms);
int GetExitCodeProcess(HANDLE h, uint32_t* code);
uint32_t GetLastError(void);
int MultiByteToWideChar(uint32_t cp, uint32_t flags, const char* s, int n, uint16_t* w, int wn);
]]
local k32 = ffi.C

local function wide(s)
	if not s then
		return nil
	end
	local n = k32.MultiByteToWideChar(65001, 0, s, #s, nil, 0)
	local buf = ffi.new("uint16_t[?]", n + 1)
	k32.MultiByteToWideChar(65001, 0, s, #s, buf, n)
	buf[n] = 0
	return buf
end

local sa = ffi.new("PB_SECURITY_ATTRIBUTES")
sa.nLength = ffi.sizeof(sa)
sa.bInheritHandle = 1
local outR, outW = ffi.new("HANDLE[1]"), ffi.new("HANDLE[1]")
local inR, inW = ffi.new("HANDLE[1]"), ffi.new("HANDLE[1]")
if k32.CreatePipe(outR, outW, sa, 65536) == 0 or k32.CreatePipe(inR, inW, sa, 1048576) == 0 then
	emit({ ev("fatal", "CreatePipe failed: " .. k32.GetLastError()) })
	return "pipe"
end
-- Our ends must not be inherited by the child
k32.SetHandleInformation(outR[0], 1, 0)
k32.SetHandleInformation(inW[0], 1, 0)

local si = ffi.new("PB_STARTUPINFOW")
si.cb = ffi.sizeof(si)
si.dwFlags = 0x100 -- STARTF_USESTDHANDLES
si.hStdInput = inR[0]
si.hStdOutput = outW[0]
si.hStdError = outW[0]
local pi = ffi.new("PB_PROCESS_INFORMATION")
local CREATE_NO_WINDOW = 0x08000000
local ok = k32.CreateProcessW(nil, wide(cmdLine), nil, nil, 1, CREATE_NO_WINDOW, nil, wide(cwd), si, pi)
k32.CloseHandle(outW[0])
k32.CloseHandle(inR[0])
if ok == 0 then
	local err = k32.GetLastError()
	k32.CloseHandle(outR[0])
	k32.CloseHandle(inW[0])
	emit({ ev("fatal", "Could not start Claude Code (CreateProcess error " .. err .. ").\nCommand: " .. cmdLine) })
	return "spawn"
end
emit({ ev("pid", pi.dwProcessId) })

-- Send the prompt then close stdin so the CLI starts working
do
	local written = ffi.new("uint32_t[1]")
	local data = stdinText or ""
	local pos = 0
	while pos < #data do
		local chunk = data:sub(pos + 1, pos + 65536)
		if k32.WriteFile(inW[0], chunk, #chunk, written, nil) == 0 then
			break
		end
		pos = pos + written[0]
	end
	k32.CloseHandle(inW[0])
end

local function shorten(s, n)
	s = tostring(s or "")
	if #s > n then
		return s:sub(1, n) .. "..."
	end
	return s
end

local function toolSummary(name, input)
	if type(input) ~= "table" then
		return ""
	end
	local s = input.command or input.file_path or input.notebook_path or input.pattern or input.url or input.query or input.description or input.prompt or input.skill
	if not s then
		for _, v in pairs(input) do
			if type(v) == "string" then
				s = v
				break
			end
		end
	end
	return shorten(((s or ""):gsub("[\r\n]+", " ")), 300)
end

local function contentText(content)
	if type(content) == "string" then
		return content
	elseif type(content) == "table" then
		local parts = { }
		for _, c in ipairs(content) do
			if type(c) == "table" and c.type == "text" then
				parts[#parts + 1] = c.text
			end
		end
		return table.concat(parts, "\n")
	end
	return ""
end

-- Translate one stream-json line to zero or more compact events
local function handleLine(line, out)
	if line:match("^%s*$") then
		return
	end
	if not json then
		out[#out + 1] = ev("raw", line)
		return
	end
	local msg = json.decode(line, 1, json.null)
	if type(msg) ~= "table" then
		out[#out + 1] = ev("stderr", line)
		return
	end
	local sub = msg.parent_tool_use_id ~= nil and msg.parent_tool_use_id ~= json.null
	if msg.type == "system" and msg.subtype == "init" then
		out[#out + 1] = ev("init", msg.session_id, msg.model, msg.permissionMode or "")
	elseif msg.type == "stream_event" and not sub then
		local e = msg.event or { }
		if e.type == "content_block_start" and e.content_block and e.content_block.type == "text" then
			out[#out + 1] = ev("textstart")
		elseif e.type == "content_block_start" and e.content_block and e.content_block.type == "thinking" then
			out[#out + 1] = ev("thinking")
		elseif e.type == "content_block_delta" and e.delta and e.delta.type == "text_delta" then
			out[#out + 1] = ev("text", e.delta.text)
		end
	elseif msg.type == "assistant" and msg.message and type(msg.message.content) == "table" then
		for _, c in ipairs(msg.message.content) do
			if c.type == "tool_use" then
				out[#out + 1] = ev("tool", c.id, c.name, toolSummary(c.name, c.input), sub and "1" or "")
			end
		end
	elseif msg.type == "user" and msg.message and type(msg.message.content) == "table" then
		for _, c in ipairs(msg.message.content) do
			if type(c) == "table" and c.type == "tool_result" then
				out[#out + 1] = ev("toolresult", c.tool_use_id, c.is_error and "1" or "", shorten(contentText(c.content), 1500))
			end
		end
	elseif msg.type == "result" then
		local denials = { }
		if type(msg.permission_denials) == "table" then
			for _, d in ipairs(msg.permission_denials) do
				denials[#denials + 1] = (d.tool_name or "?") .. ": " .. toolSummary(d.tool_name, d.tool_input)
			end
		end
		out[#out + 1] = ev("result", msg.subtype, msg.is_error and "1" or "", type(msg.result) == "string" and msg.result or "",
			msg.total_cost_usd or 0, msg.duration_ms or 0, msg.num_turns or 0, msg.session_id or "", table.concat(denials, "\n"))
	end
end

local buf = ffi.new("uint8_t[?]", 65536)
local nRead = ffi.new("uint32_t[1]")
local pending = ""
while true do
	if k32.ReadFile(outR[0], buf, 65536, nRead, nil) == 0 or nRead[0] == 0 then
		break
	end
	pending = pending .. ffi.string(buf, nRead[0])
	local out = { }
	while true do
		local nl = pending:find("\n", 1, true)
		if not nl then
			break
		end
		local line = pending:sub(1, nl - 1):gsub("\r$", "")
		pending = pending:sub(nl + 1)
		local okLine, err = pcall(handleLine, line, out)
		if not okLine then
			out[#out + 1] = ev("stderr", "[harness parse error] " .. tostring(err))
		end
	end
	emit(out)
end
if #pending > 0 then
	local out = { }
	pcall(handleLine, pending, out)
	emit(out)
end
k32.CloseHandle(outR[0])
k32.WaitForSingleObject(pi.hProcess, 10000)
local code = ffi.new("uint32_t[1]")
k32.GetExitCodeProcess(pi.hProcess, code)
k32.CloseHandle(pi.hProcess)
k32.CloseHandle(pi.hThread)
return "exit", tonumber(code[0])
