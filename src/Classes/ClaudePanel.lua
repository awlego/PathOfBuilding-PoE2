-- Path of Building
--
-- Class: Claude Panel
-- Collapsible chat panel docked on the right side of the build screen. Talks to the Claude Code
-- CLI through Claude/Harness.lua. The panel's child controls are registered directly in the
-- owning build's control host (prefixed "claude"), so focus and input routing work like any other
-- build-screen control.
--
local t_insert = table.insert
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local s_format = string.format

local HEADER_H = 52
local FOOTER_H = 18
local MIN_W = 300

local COLOR_TEXT = "^xDCDCDC"
local COLOR_BRIGHT = "^xFFFFFF"
local COLOR_CODE = "^xE8B86D"
local COLOR_DIM = "^x8C8C8C"
local COLOR_CLAUDE = "^xD97757"
local COLOR_USER = "^x7FB2F0"

---------------------------------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------------------------------

local asciiMap = {
	["\226\128\148"] = "-", ["\226\128\147"] = "-", ["\226\128\156"] = '"', ["\226\128\157"] = '"',
	["\226\128\152"] = "'", ["\226\128\153"] = "'", ["\226\128\166"] = "...", ["\226\134\146"] = "->",
	["\226\134\144"] = "<-", ["\226\134\148"] = "<->", ["\226\135\146"] = "=>", ["\226\137\136"] = "~",
	["\195\151"] = "x", ["\226\128\162"] = "*", ["\226\137\165"] = ">=", ["\226\137\164"] = "<=",
	["\226\156\147"] = "v", ["\226\156\148"] = "v", ["\226\156\151"] = "x", ["\226\156\152"] = "x",
	["\194\176"] = " deg", ["\194\177"] = "+/-", ["\194\160"] = " ", ["\226\128\137"] = " ",
	["\226\128\175"] = " ", ["\226\136\146"] = "-", ["\226\128\139"] = "", ["\194\183"] = "*",
	["\226\150\182"] = ">", ["\226\134\145"] = "^", ["\226\134\147"] = "v", ["\226\136\158"] = "inf",
	["\226\137\160"] = "!=", ["\194\178"] = "2", ["\194\179"] = "3", ["\194\189"] = "1/2",
}

-- Make arbitrary text safe for DrawString: fold common unicode to ASCII, neutralise PoB colour escapes
local function sanitize(s)
	s = tostring(s or "")
	s = s:gsub("\r\n", "\n"):gsub("\t", "    ")
	s = s:gsub("[\194-\244][\128-\191]+", function(ch)
		return asciiMap[ch] or "?"
	end)
	s = s:gsub("%^([%dxX])", "^ %1")
	return s
end

local function lastColorCode(s)
	local best, bestPos = nil, 0
	for pos, code in s:gmatch("()(%^x%x%x%x%x%x%x)") do
		if pos > bestPos then
			best, bestPos = code, pos
		end
	end
	for pos, code in s:gmatch("()(%^%d)") do
		if pos > bestPos then
			best, bestPos = code, pos
		end
	end
	return best
end

-- Word-wrap one logical line (may contain colour codes) to a pixel width
local function wrapLine(str, font, size, width)
	local out = { }
	if str == "" then
		return { "" }
	end
	if DrawStringWidth(size, font, str) <= width then
		return { str }
	end
	local cur = ""
	local color = ""
	local function flush()
		local line = cur:gsub("%s+$", "")
		t_insert(out, line)
		color = lastColorCode(cur) or color
		cur = color
	end
	local leading = str:match("^%s*")
	local rest = str:sub(#leading + 1)
	cur = leading
	for token in rest:gmatch("%S+%s*") do
		local cand = cur .. token
		if StripEscapes(cur):match("%S") and DrawStringWidth(size, font, (cand:gsub("%s+$", ""))) > width then
			flush()
			cand = cur .. token
		end
		cur = cand
		-- A single token wider than the line: hard-split it
		while DrawStringWidth(size, font, (cur:gsub("%s+$", ""))) > width and #StripEscapes(cur) > 1 do
			local cut = #cur - 1
			while cut > 1 and DrawStringWidth(size, font, cur:sub(1, cut)) > width do
				cut = cut - m_max(1, m_floor((cut) / 8))
			end
			cut = m_max(cut, 1)
			local head = cur:sub(1, cut)
			t_insert(out, head)
			color = lastColorCode(head) or color
			cur = color .. cur:sub(cut + 1)
		end
	end
	if StripEscapes(cur):match("%S") then
		t_insert(out, (cur:gsub("%s+$", "")))
	end
	return out
end

local function inlineFormat(s, base)
	s = s:gsub("%*%*(.-)%*%*", COLOR_BRIGHT .. "%1" .. base)
	s = s:gsub("__(.-)__", COLOR_BRIGHT .. "%1" .. base)
	s = s:gsub("`([^`]+)`", COLOR_CODE .. "%1" .. base)
	s = s:gsub("%[([^%]]+)%]%(([^%)]+)%)", "%1 (%2)")
	return base .. s
end

---------------------------------------------------------------------------------------------------
-- Layout: turn a message into a list of drawable lines
---------------------------------------------------------------------------------------------------

local BODY_SIZE = 16
local BODY_LINE = 18
local CODE_SIZE = 14
local CODE_LINE = 15

local function layoutMarkdown(lines, text, width, indent)
	local inCode = false
	for raw in (text .. "\n"):gmatch("(.-)\n") do
		local line = raw
		if line:match("^%s*```") then
			inCode = not inCode
			t_insert(lines, { h = 4, codeBg = true, x = indent })
		elseif inCode then
			for _, w in ipairs(wrapLine(COLOR_TEXT .. line, "FIXED", CODE_SIZE, width - indent - 8)) do
				t_insert(lines, { text = w, font = "FIXED", size = CODE_SIZE, h = CODE_LINE, x = indent + 4, codeBg = true })
			end
		elseif line:match("^%s*|") then
			if not line:match("^%s*|[%s%-:|]+|%s*$") then
				t_insert(lines, { text = COLOR_TEXT .. line:gsub("%*%*", ""):gsub("`", ""), font = "FIXED", size = CODE_SIZE, h = CODE_LINE, x = indent })
			end
		elseif line:match("^%s*$") then
			t_insert(lines, { h = 7 })
		elseif line:match("^%s*[-*_]%s*[-*_]%s*[-*_][-*_%s]*$") then
			t_insert(lines, { h = 9, rule = true, x = indent })
		else
			local hashes, heading = line:match("^(#+)%s+(.*)$")
			if hashes then
				local size = #hashes <= 1 and 20 or (#hashes == 2 and 18 or 16)
				t_insert(lines, { h = 3 })
				for _, w in ipairs(wrapLine(inlineFormat((heading:gsub("%*%*", "")), COLOR_BRIGHT), "VAR BOLD", size, width - indent)) do
					t_insert(lines, { text = w, font = "VAR BOLD", size = size, h = size + 3, x = indent })
				end
			else
				local lead, bullet, content = line:match("^(%s*)([-*+])%s+(.*)$")
				local num
				if not bullet then
					lead, num, content = line:match("^(%s*)(%d+[.)])%s+(.*)$")
				end
				local quote = not bullet and not num and line:match("^%s*>%s?(.*)$")
				if bullet or num then
					local depth = m_floor(#lead / 2)
					local bx = indent + 4 + depth * 14
					local textX = bx + (num and (DrawStringWidth(BODY_SIZE, "VAR", num) + 6) or 12)
					local wrapped = wrapLine(inlineFormat(content, COLOR_TEXT), "VAR", BODY_SIZE, width - textX)
					for i, w in ipairs(wrapped) do
						local l = { text = w, font = "VAR", size = BODY_SIZE, h = BODY_LINE, x = textX }
						if i == 1 then
							if num then
								l.prefix = COLOR_DIM .. num
								l.prefixX = bx
							else
								l.bulletX = bx + 2
							end
						end
						t_insert(lines, l)
					end
				elseif quote then
					for _, w in ipairs(wrapLine(inlineFormat(quote, COLOR_DIM), "VAR", BODY_SIZE, width - indent - 12)) do
						t_insert(lines, { text = w, font = "VAR", size = BODY_SIZE, h = BODY_LINE, x = indent + 12, quoteBar = indent + 3 })
					end
				else
					for _, w in ipairs(wrapLine(inlineFormat(line, COLOR_TEXT), "VAR", BODY_SIZE, width - indent)) do
						t_insert(lines, { text = w, font = "VAR", size = BODY_SIZE, h = BODY_LINE, x = indent })
					end
				end
			end
		end
	end
end

local function layoutMessage(msg, width, expanded)
	local lines = { }
	local text = sanitize(msg.text)
	if msg.role == "user" then
		t_insert(lines, { text = COLOR_USER .. "You", font = "VAR BOLD", size = 14, h = 17, x = 0 })
		for raw in (text .. "\n"):gmatch("(.-)\n") do
			for _, w in ipairs(wrapLine(COLOR_TEXT .. raw, "VAR", BODY_SIZE, width - 12)) do
				t_insert(lines, { text = w, font = "VAR", size = BODY_SIZE, h = BODY_LINE, x = 6, userBg = true })
			end
		end
		t_insert(lines, { h = 8 })
	elseif msg.role == "assistant" then
		if not msg.continued then
			t_insert(lines, { text = COLOR_CLAUDE .. "Claude", font = "VAR BOLD", size = 14, h = 17, x = 0 })
		end
		layoutMarkdown(lines, text, width - 4, 0)
		t_insert(lines, { h = 6 })
	elseif msg.role == "tool" then
		local mark
		if not msg.done then
			mark = COLOR_DIM .. "..."
		elseif msg.isError then
			mark = "^xE05050x"
		else
			mark = "^x60C060v"
		end
		local head = s_format("%s %s%s %s%s", mark, msg.sub and COLOR_DIM .. "  " or "", COLOR_CODE .. sanitize(msg.toolName or "tool"), COLOR_DIM, (text:gsub("\n", " ")))
		t_insert(lines, { text = head, font = "VAR", size = 14, h = 16, x = 2, clip = true, tool = true })
		if expanded then
			local detail = sanitize(msg.text or "")
			if msg.result and msg.result ~= "" then
				detail = detail .. "\n--- result ---\n" .. sanitize(msg.result)
			end
			for raw in (detail .. "\n"):gmatch("(.-)\n") do
				for _, w in ipairs(wrapLine(COLOR_TEXT .. raw, "FIXED", 13, width - 16)) do
					t_insert(lines, { text = w, font = "FIXED", size = 13, h = 14, x = 10, codeBg = true })
				end
			end
			t_insert(lines, { h = 4 })
		end
	elseif msg.role == "error" then
		for raw in (text .. "\n"):gmatch("(.-)\n") do
			for _, w in ipairs(wrapLine("^xE05050" .. raw, "VAR", 14, width - 4)) do
				t_insert(lines, { text = w, font = "VAR", size = 14, h = 16, x = 0 })
			end
		end
		t_insert(lines, { h = 6 })
	else
		for raw in (text .. "\n"):gmatch("(.-)\n") do
			for _, w in ipairs(wrapLine(COLOR_DIM .. raw, "VAR", 14, width - 4)) do
				t_insert(lines, { text = w, font = "VAR", size = 14, h = 16, x = 0 })
			end
		end
		t_insert(lines, { h = 6 })
	end
	local total = 0
	for _, l in ipairs(lines) do
		total = total + l.h
	end
	return lines, total
end

---------------------------------------------------------------------------------------------------
-- Chat view control
---------------------------------------------------------------------------------------------------

local ChatViewClass = newClass("ClaudeChatView", "Control")

function ChatViewClass:ClaudeChatView(anchor, rect, panel)
	self:Control(anchor, rect)
	self.panel = panel
	self.expanded = { }
	return self
end

function ChatViewClass:IsMouseOver()
	return self:IsShown() and self:IsMouseInBounds()
end

function ChatViewClass:GetLayout(msg, width)
	local key = width .. ":" .. #(msg.text or "") .. ":" .. tostring(msg.done) .. ":" .. tostring(msg.continued) .. ":" .. tostring(self.expanded[msg] or false)
	if msg._layoutKey ~= key then
		msg._layoutLines, msg._layoutH = layoutMessage(msg, width, self.expanded[msg])
		msg._layoutKey = key
	end
	return msg._layoutLines, msg._layoutH
end

local HISTORY_ROW = 42

-- Past conversations list (replaces the chat view while harness.showHistory is set)
function ChatViewClass:DrawHistory(x, y, width, height)
	local harness = self.panel.harness
	local scrollBar = self.panel.scrollBar
	local contentW = width - 16
	local list = harness.chatIndex or { }
	scrollBar:SetContentDimension(30 + #list * HISTORY_ROW + 8, height)
	SetDrawColor(0.06, 0.06, 0.07)
	DrawImage(nil, x, y, width, height)
	SetViewport(x + 6, y, contentW, height)
	local cursorX, cursorY = GetCursorPos()
	local mx, my = cursorX - x - 6, cursorY - y
	local mouseIn = self:IsMouseOver()
	self.hoverChat = nil
	self.hoverDelete = nil
	local top = 4 - scrollBar.offset
	SetDrawColor(1, 1, 1)
	DrawString(0, top, "LEFT", 16, "VAR BOLD", COLOR_BRIGHT .. "Past conversations " .. COLOR_DIM .. "(" .. #list .. ")")
	DrawString(contentW, top + 2, "RIGHT_X", 13, "VAR", COLOR_DIM .. "click to open, x to delete")
	if #list == 0 then
		DrawString(0, top + 30, "LEFT", 15, "VAR", COLOR_DIM .. "No saved conversations yet.")
	end
	local rowY = top + 26
	for _, entry in ipairs(list) do
		if rowY + HISTORY_ROW >= 0 and rowY <= height then
			local hovered = mouseIn and my >= rowY and my < rowY + HISTORY_ROW - 2 and mx >= 0 and mx < contentW
			local current = entry.id == harness.chatId
			if hovered then
				self.hoverChat = entry
				SetDrawColor(1, 1, 1, 0.07)
			else
				SetDrawColor(1, 1, 1, 0.025)
			end
			DrawImage(nil, 0, rowY, contentW, HISTORY_ROW - 2)
			if current then
				SetDrawColor(0.85, 0.47, 0.34)
				DrawImage(nil, 0, rowY, 3, HISTORY_ROW - 2)
			end
			local title = sanitize(entry.title or "(untitled)")
			local maxW = contentW - 34
			if DrawStringWidth(15, "VAR", title) > maxW then
				while #title > 4 and DrawStringWidth(15, "VAR", title .. "...") > maxW do
					title = title:sub(1, -2)
				end
				title = title .. "..."
			end
			DrawString(8, rowY + 3, "LEFT", 15, "VAR", (current and COLOR_CLAUDE or COLOR_BRIGHT) .. title)
			local meta = { os.date("%Y-%m-%d %H:%M", entry.updated or entry.created or 0) }
			if entry.build then
				t_insert(meta, sanitize(entry.build))
			end
			t_insert(meta, (entry.messages or 0) .. " msg" .. ((entry.messages or 0) == 1 and "" or "s"))
			if entry.cost and entry.cost > 0 then
				t_insert(meta, s_format("$%.3f", entry.cost))
			end
			DrawString(8, rowY + 21, "LEFT", 13, "VAR", COLOR_DIM .. table.concat(meta, "  |  "))
			if hovered then
				local delX = contentW - 22
				local overDel = mx >= delX and my >= rowY + 4 and my < rowY + 24
				local confirm = self.confirmDelete == entry.id
				if overDel then
					self.hoverDelete = entry
				end
				SetDrawColor(confirm and 0.8 or (overDel and 0.5 or 0.25), overDel and 0.2 or 0.25, overDel and 0.2 or 0.25)
				DrawImage(nil, delX, rowY + 4, 20, 20)
				SetDrawColor(1, 1, 1)
				DrawString(delX + 10, rowY + 5, "CENTER_X", 15, "VAR", "^7x")
				if confirm then
					DrawString(delX - 4, rowY + 6, "RIGHT_X", 13, "VAR", "^xE05050click again to delete")
				end
			end
		end
		rowY = rowY + HISTORY_ROW
	end
	if not self.hoverChat or self.hoverChat.id ~= self.confirmDelete then
		if not mouseIn then
			self.confirmDelete = nil
		end
	end
	SetViewport()
end

function ChatViewClass:Draw(viewPort)
	local harness = self.panel.harness
	local x, y = self:GetPos()
	local width, height = self:GetSize()
	local scrollBar = self.panel.scrollBar
	local contentW = width - 16
	local messages = harness.messages
	if harness.showHistory ~= self.lastShowHistory then
		self.lastShowHistory = harness.showHistory
		self.hoverMsg = nil
		if harness.showHistory then
			scrollBar.offset = 0
		else
			self.forceBottom = true
		end
	end
	if harness.showHistory then
		self:DrawHistory(x, y, width, height)
		return
	end

	-- Merge consecutive assistant blocks visually (one "Claude" label per run of text/tool blocks)
	local prevRole
	for _, msg in ipairs(messages) do
		local continued = msg.role == "assistant" and (prevRole == "assistant" or prevRole == "tool") or nil
		if msg.continued ~= continued then
			msg.continued = continued
		end
		if msg.role ~= "system" then
			prevRole = msg.role
		end
	end

	local total = 8
	for _, msg in ipairs(messages) do
		local _, h = self:GetLayout(msg, contentW)
		total = total + h
	end
	if harness.running then
		total = total + 22
	end
	local atBottom = scrollBar.offset >= (scrollBar.offsetMax or 0) - 4
	scrollBar:SetContentDimension(total, height)
	if atBottom or self.forceBottom then
		scrollBar:SetOffset(scrollBar.offsetMax or 0)
		self.forceBottom = nil
	end

	SetDrawColor(0.06, 0.06, 0.07)
	DrawImage(nil, x, y, width, height)
	SetViewport(x + 6, y, contentW, height)
	local cursorX, cursorY = GetCursorPos()
	local mx, my = cursorX - x - 6, cursorY - y
	local mouseIn = self:IsMouseOver()
	self.hoverMsg = nil
	local lineY = 4 - scrollBar.offset
	for _, msg in ipairs(messages) do
		local lines, h = self:GetLayout(msg, contentW)
		if lineY + h >= 0 and lineY <= height then
			if mouseIn and my >= lineY and my < lineY + h and mx >= 0 then
				self.hoverMsg = msg
				if msg.role == "tool" then
					SetDrawColor(1, 1, 1, 0.05)
					DrawImage(nil, 0, lineY, contentW, h)
				end
			end
			local ly = lineY
			for _, l in ipairs(lines) do
				if ly + l.h >= 0 and ly <= height then
					if l.userBg then
						SetDrawColor(0.13, 0.17, 0.25)
						DrawImage(nil, 0, ly, contentW, l.h)
					elseif l.codeBg then
						SetDrawColor(0.12, 0.12, 0.13)
						DrawImage(nil, (l.x or 0) - 4, ly, contentW - (l.x or 0) + 4, l.h)
					end
					if l.rule then
						SetDrawColor(0.3, 0.3, 0.3)
						DrawImage(nil, l.x or 0, ly + 4, contentW - (l.x or 0), 1)
					end
					if l.quoteBar then
						SetDrawColor(0.4, 0.4, 0.4)
						DrawImage(nil, l.quoteBar, ly, 2, l.h)
					end
					if l.bulletX then
						SetDrawColor(0.75, 0.75, 0.75)
						DrawImage(nil, l.bulletX, ly + m_floor(l.h / 2) - 2, 4, 4)
					end
					if l.prefix then
						SetDrawColor(1, 1, 1)
						DrawString(l.prefixX, ly, "LEFT", l.size, l.font, l.prefix)
					end
					if l.text then
						SetDrawColor(1, 1, 1)
						DrawString(l.x or 0, ly, "LEFT", l.size, l.font, l.text)
					end
				end
				ly = ly + l.h
			end
		end
		lineY = lineY + h
	end
	if harness.running then
		local dots = string.rep(".", m_floor(GetTime() / 400) % 4)
		local elapsed = harness.turnStart and m_floor((GetTime() - harness.turnStart) / 1000) or 0
		SetDrawColor(1, 1, 1)
		DrawString(0, lineY + 2, "LEFT", 14, "VAR", COLOR_CLAUDE .. (harness.status or "Working") .. dots .. COLOR_DIM .. "  " .. elapsed .. "s")
	end
	if #messages == 0 and not harness.running then
		local hint = {
			COLOR_BRIGHT .. "Ask Claude about this build.",
			"",
			COLOR_DIM .. "Each message includes the open build's stats,",
			COLOR_DIM .. "skills, items, tree and config. Claude can also",
			COLOR_DIM .. "query and change the live build, and edit PoB's",
			COLOR_DIM .. "own source (then press Reload).",
			"",
			COLOR_DIM .. "Enter: send   Shift+Enter: new line   Ctrl+K: toggle",
			COLOR_DIM .. "Right-click a message to copy it. Click a tool",
			COLOR_DIM .. "line to expand it. /help lists local commands.",
		}
		for i, line in ipairs(hint) do
			DrawString(4, 10 + (i - 1) * 18, "LEFT", 15, "VAR", line)
		end
	end
	SetViewport()
	if self.copiedAt and GetTime() - self.copiedAt < 1200 then
		SetDrawColor(0, 0, 0, 0.8)
		DrawImage(nil, x + width / 2 - 40, y + 6, 80, 20)
		SetDrawColor(1, 1, 1)
		DrawString(x + width / 2, y + 8, "CENTER_X", 15, "VAR", "^7Copied")
	end
end

function ChatViewClass:OnKeyDown(key, doubleClick)
	local harness = self.panel.harness
	if harness.showHistory then
		if key == "LEFTBUTTON" and self.hoverDelete then
			if self.confirmDelete == self.hoverDelete.id then
				harness:DeleteChat(self.hoverDelete.id)
				self.confirmDelete = nil
			else
				self.confirmDelete = self.hoverDelete.id
			end
		elseif key == "LEFTBUTTON" and self.hoverChat then
			self.confirmDelete = nil
			if self.hoverChat.id == harness.chatId or harness:OpenChat(self.hoverChat.id) then
				harness.showHistory = false
				self.forceBottom = true
			end
		end
		return nil
	end
	if key == "LEFTBUTTON" and self.hoverMsg and self.hoverMsg.role == "tool" then
		self.expanded[self.hoverMsg] = not self.expanded[self.hoverMsg] or nil
	elseif key == "RIGHTBUTTON" and self.hoverMsg then
		local text = self.hoverMsg.text or ""
		if self.hoverMsg.result then
			text = text .. "\n" .. self.hoverMsg.result
		end
		Copy(text)
		self.copiedAt = GetTime()
	end
	return nil
end

function ChatViewClass:OnKeyUp(key)
	local scrollBar = self.panel.scrollBar
	if key == "WHEELDOWN" then
		scrollBar:Scroll(1)
		return self
	elseif key == "WHEELUP" then
		scrollBar:Scroll(-1)
		return self
	end
end

---------------------------------------------------------------------------------------------------
-- Collapsed tab and resize splitter
---------------------------------------------------------------------------------------------------

local TabClass = newClass("ClaudeTabControl", "Control", "TooltipHost")

function TabClass:ClaudeTabControl(anchor, rect, onClick)
	self:Control(anchor, rect)
	self:TooltipHost("Open the Claude panel (Ctrl+K)")
	self.onClick = onClick
	return self
end

function TabClass:IsMouseOver()
	return self:IsShown() and self:IsMouseInBounds()
end

function TabClass:Draw(viewPort)
	local x, y = self:GetPos()
	local width, height = self:GetSize()
	local mOver = self:IsMouseOver()
	SetDrawColor(mOver and 0.85 or 0.5, mOver and 0.47 or 0.3, mOver and 0.34 or 0.22)
	DrawImage(nil, x, y, width, height)
	SetDrawColor(0.1, 0.1, 0.1)
	DrawImage(nil, x + 1, y + 1, width - 2, height - 2)
	SetDrawColor(1, 1, 1)
	local label = "CLAUDE"
	for i = 1, #label do
		DrawString(x + width / 2, y + 6 + (i - 1) * 15, "CENTER_X", 14, "VAR BOLD", COLOR_CLAUDE .. label:sub(i, i))
	end
	DrawString(x + width / 2, y + height - 20, "CENTER_X", 14, "VAR", "^7<")
	if mOver then
		SetDrawLayer(nil, 100)
		self:DrawTooltip(x, y, width, height, viewPort)
		SetDrawLayer(nil, 0)
	end
end

function TabClass:OnKeyDown(key)
	if key == "LEFTBUTTON" then
		self.onClick()
	end
end

local SplitterClass = newClass("ClaudeSplitterControl", "Control")

function SplitterClass:ClaudeSplitterControl(anchor, rect, panel)
	self:Control(anchor, rect)
	self.panel = panel
	return self
end

function SplitterClass:IsMouseOver()
	return self:IsShown() and self:IsMouseInBounds()
end

function SplitterClass:Draw()
	local x, y = self:GetPos()
	local width, height = self:GetSize()
	if self.dragging then
		if IsKeyDown("LEFTBUTTON") then
			local cursorX = GetCursorPos()
			self.panel:SetWidth(main.screenW - cursorX)
		else
			self.dragging = false
			self.panel.harness:SaveSettings()
		end
	end
	if self.dragging or self:IsMouseOver() then
		SetDrawColor(0.85, 0.47, 0.34)
	else
		SetDrawColor(0.85, 0.85, 0.85)
	end
	DrawImage(nil, x + 1, y, 4, height)
end

function SplitterClass:OnKeyDown(key)
	if key == "LEFTBUTTON" then
		self.dragging = true
	end
end

---------------------------------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------------------------------

local PanelClass = newClass("ClaudePanel")

function PanelClass:ClaudePanel(build)
	self.build = build
	if not claudeHarness then
		claudeHarness = LoadModule("Claude/Harness")
	end
	self.harness = claudeHarness
	self.harness:Init()
	self.harness:OnBuildInit(build)
	local harness = self.harness
	local controls = build.controls
	self.historyIndex = nil

	local function panelX()
		return main.screenW - self:GetWidth()
	end
	local function shown()
		return harness.settings.open
	end

	self.anchor = new("Control"):Control(nil, { function() return panelX() end, 32, 0, 0 })

	controls.claudeSplitter = new("ClaudeSplitterControl"):ClaudeSplitterControl({ "TOPLEFT", self.anchor, "TOPLEFT" }, { 0, 0, 6, function() return main.screenH - 32 end }, self)
	controls.claudeSplitter.shown = shown

	controls.claudeTitle = new("LabelControl"):LabelControl({ "TOPLEFT", self.anchor, "TOPLEFT" }, { 12, 6, 0, 18 }, COLOR_CLAUDE .. "Claude")
	controls.claudeTitle.shown = shown
	controls.claudeStatus = new("LabelControl"):LabelControl({ "TOPLEFT", self.anchor, "TOPLEFT" }, { 76, 8, 0, 14 }, function()
		if harness.running then
			return COLOR_DIM .. (harness.status or "")
		end
		local s = harness.lastTurnInfo or ""
		if harness.liveCount and harness.liveCount > 0 then
			s = s .. "  live:" .. harness.liveCount
		end
		return COLOR_DIM .. s
	end)
	controls.claudeStatus.shown = shown

	controls.claudeCollapse = new("ButtonControl"):ButtonControl({ "TOPRIGHT", self.anchor, "TOPLEFT" }, { function() return self:GetWidth() - 6 end, 4, 22, 20 }, ">>", function()
		self:SetOpen(false)
	end)
	controls.claudeCollapse.tooltipText = "Collapse the Claude panel (Ctrl+K)"
	controls.claudeCollapse.shown = shown

	controls.claudeNew = new("ButtonControl"):ButtonControl({ "TOPLEFT", self.anchor, "TOPLEFT" }, { 10, 28, 42, 20 }, "New", function()
		harness:NewChat()
		harness.showHistory = false
		self.build:SelectControl(self.edit)
	end)
	controls.claudeNew.tooltipText = "Start a fresh Claude conversation"
	controls.claudeNew.shown = shown

	controls.claudeHistory = new("ButtonControl"):ButtonControl({ "LEFT", controls.claudeNew, "RIGHT" }, { 4, 0, 58, 20 }, function()
		return harness.showHistory and "Chat" or "History"
	end, function()
		harness.showHistory = not harness.showHistory
		if harness.showHistory then
			harness:SaveChat()
		end
	end)
	controls.claudeHistory.tooltipText = "Browse and reopen past conversations (Claude resumes the same session)"
	controls.claudeHistory.shown = shown

	controls.claudeReload = new("ButtonControl"):ButtonControl({ "LEFT", controls.claudeHistory, "RIGHT" }, { 4, 0, 54, 20 }, "Reload", function()
		harness:RequestReload()
	end)
	controls.claudeReload.tooltipText = "Restart PoB's Lua to pick up code edits.\nThe chat and the open build are preserved (F5 also works in dev mode)."
	controls.claudeReload.shown = shown

	local modeList = { }
	for _, m in ipairs(harness.permissionModes) do
		t_insert(modeList, { label = m.label, mode = m.mode })
	end
	controls.claudeMode = new("DropDownControl"):DropDownControl({ "LEFT", controls.claudeReload, "RIGHT" }, { 4, 0, 104, 20 }, modeList, function(index, value)
		harness.settings.permissionMode = value.mode
		harness:SaveSettings()
	end)
	controls.claudeMode:SelByValue(harness.settings.permissionMode, "mode")
	controls.claudeMode.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip:AddLine(14, "^7Permission mode for Claude's tools:")
		for _, m in ipairs(harness.permissionModes) do
			tooltip:AddLine(14, (m.mode == harness.settings.permissionMode and COLOR_CLAUDE or "^7") .. m.label .. ": ^8" .. m.tooltip)
		end
	end
	controls.claudeMode.shown = shown

	local modelList = { }
	for _, m in ipairs(harness.models) do
		t_insert(modelList, { label = m.label, model = m.model })
	end
	controls.claudeModel = new("DropDownControl"):DropDownControl({ "LEFT", controls.claudeMode, "RIGHT" }, { 4, 0, 100, 20 }, modelList, function(index, value)
		harness.settings.model = value.model
		harness:SaveSettings()
	end)
	controls.claudeModel:SelByValue(harness.settings.model or "", "model")
	controls.claudeModel.tooltipText = "Model for new turns (Default = your Claude Code default)"
	controls.claudeModel.shown = shown

	local function inputHeight()
		local lines = 1
		local buf = self.edit and self.edit.buf or ""
		for _ in buf:gmatch("\n") do
			lines = lines + 1
		end
		return m_min(m_max(lines, 3), 10) * 16 + 6
	end

	controls.claudeChat = new("ClaudeChatView"):ClaudeChatView({ "TOPLEFT", self.anchor, "TOPLEFT" }, { 6, HEADER_H + 2, function() return self:GetWidth() - 6 - 14 end, function()
		return main.screenH - 32 - HEADER_H - 2 - inputHeight() - FOOTER_H - 10
	end }, self)
	controls.claudeChat.shown = shown

	self.scrollBar = new("ScrollBarControl"):ScrollBarControl({ "TOPLEFT", controls.claudeChat, "TOPRIGHT" }, { 0, 0, 14, function()
		local _, h = controls.claudeChat:GetSize()
		return h
	end }, 54)
	controls.claudeScroll = self.scrollBar
	controls.claudeScroll.shown = shown

	self.edit = new("EditControl"):EditControl({ "TOPLEFT", controls.claudeChat, "BOTTOMLEFT" }, { 0, 6, function() return self:GetWidth() - 6 - 72 end, inputHeight }, "", nil, "^%C\t\n", nil, nil, 16)
	self.edit.placeholder = "Ask about this build, or ask for a PoB change..."
	local edit = self.edit
	local baseKeyDown = edit.OnKeyDown
	edit.OnKeyDown = function(ctl, key, doubleClick)
		if key == "RETURN" and not IsKeyDown("SHIFT") then
			self:Submit()
			return ctl
		elseif key == "UP" and (ctl.buf == "" or self.historyIndex) and not IsKeyDown("SHIFT") then
			self:RecallHistory(-1)
			return ctl
		elseif key == "DOWN" and self.historyIndex and not IsKeyDown("SHIFT") then
			self:RecallHistory(1)
			return ctl
		elseif key == "ESCAPE" and harness.running then
			harness:Stop()
			return ctl
		end
		self.historyIndex = nil
		return baseKeyDown(ctl, key, doubleClick)
	end
	controls.claudeInput = edit
	controls.claudeInput.shown = shown

	controls.claudeSend = new("ButtonControl"):ButtonControl({ "TOPLEFT", edit, "TOPRIGHT" }, { 6, 0, 60, 22 }, function()
		return harness.running and "Stop" or "Send"
	end, function()
		if harness.running then
			harness:Stop()
		else
			self:Submit()
		end
	end)
	controls.claudeSend.shown = shown

	controls.claudeFooter = new("LabelControl"):LabelControl({ "TOPLEFT", edit, "BOTTOMLEFT" }, { 0, 3, 0, 13 }, function()
		local modeLabel = controls.claudeMode:GetSelValueByKey("label") or "?"
		local sid = harness.sessionId and ("session " .. harness.sessionId:sub(1, 8)) or "new session"
		return COLOR_DIM .. sid .. "  |  " .. modeLabel .. "  |  total $" .. string.format("%.3f", harness.totalCost or 0)
	end)
	controls.claudeFooter.shown = shown

	controls.claudeTab = new("ClaudeTabControl"):ClaudeTabControl(nil, { function() return main.screenW - 20 end, 36, 20, 112 }, function()
		self:SetOpen(true)
	end)
	controls.claudeTab.shown = function()
		return not harness.settings.open
	end
	return self
end

function PanelClass:GetWidth()
	local w = self.harness.settings.width or 460
	return m_max(MIN_W, m_min(w, main.screenW - 640))
end

function PanelClass:SetWidth(w)
	self.harness.settings.width = m_floor(m_max(MIN_W, m_min(w, main.screenW - 640)))
end

-- Width taken away from the tab area
function PanelClass:GetReservedWidth()
	return self.harness.settings.open and self:GetWidth() or 22
end

function PanelClass:SetOpen(open)
	self.harness.settings.open = open
	self.harness:SaveSettings()
	if open then
		self.build:SelectControl(self.edit)
		self.build.controls.claudeChat.forceBottom = true
	elseif self.build.selControl and self.build.selControl == self.edit then
		self.build:SelectControl()
	end
end

function PanelClass:Toggle()
	self:SetOpen(not self.harness.settings.open)
end

function PanelClass:Submit()
	local text = self.edit.buf
	if text:match("^%s*$") or self.harness.running then
		return
	end
	self.edit:SetText("")
	self.historyIndex = nil
	if not text:match("^%s*/history") then
		self.harness.showHistory = false
	end
	self.build.controls.claudeChat.forceBottom = true
	self.harness:Send(text, self.build)
end

function PanelClass:RecallHistory(dir)
	local userMsgs = { }
	for _, msg in ipairs(self.harness.messages) do
		if msg.role == "user" then
			t_insert(userMsgs, msg.text)
		end
	end
	if #userMsgs == 0 then
		return
	end
	local idx = (self.historyIndex or (#userMsgs + 1)) + dir
	if idx > #userMsgs then
		self.historyIndex = nil
		self.edit:SetText("")
		return
	end
	idx = m_max(1, idx)
	self.historyIndex = idx
	self.edit:SetText(userMsgs[idx])
end

-- Called from buildMode:OnFrame (layer 5, before DrawControls)
function PanelClass:DrawBackground()
	if not self.harness.settings.open then
		SetDrawColor(0.1, 0.1, 0.1)
		DrawImage(nil, main.screenW - 22, 32, 22, main.screenH - 32)
		SetDrawColor(0.85, 0.85, 0.85)
		DrawImage(nil, main.screenW - 22, 32, 2, main.screenH - 32)
		return
	end
	local x = main.screenW - self:GetWidth()
	SetDrawColor(0.1, 0.1, 0.1)
	DrawImage(nil, x, 32, self:GetWidth(), main.screenH - 32)
	SetDrawColor(0.25, 0.25, 0.25)
	DrawImage(nil, x + 6, 32 + HEADER_H - 2, self:GetWidth() - 6, 1)
end

function PanelClass:OnFrame()
	self.harness:PollLive(self.build)
end

return PanelClass
