# Claude harness for PoB

A collapsible Claude Code chat panel on the right side of the build screen.

## Using it

- **Ctrl+K**, or the orange **CLAUDE** tab on the right edge, opens and closes the panel. Drag the panel's left border to resize it.
- **Enter** sends, **Shift+Enter** adds a new line, and **Up/Down** recall earlier prompts when the box is empty. **Esc** (or **Stop**) cancels a running turn and kills the CLI process tree.
- Right-click a message to copy it. Click a tool line to expand its input and result.
- **New** starts a fresh conversation. **Reload** restarts PoB's Lua so source edits take effect; the chat, the session and the open build are kept.
- The permission dropdown picks what Claude may do:
  - **Read-only**: reads files and queries the live build.
  - **Accept edits**: may also edit files.
  - **Auto**: Claude Code auto mode. This is the default and suits PoB development.
  - **Bypass**: no permission checks.
- Local commands that never reach Claude: `/new`, `/reload`, `/context` (shows what Claude is told about the build), `/cmd` (shows the CLI command line), `/help`.

## How it works

Each message runs `claude -p --output-format stream-json --resume <session>` with the repo root as its working directory. The process starts on a SimpleGraphic sub-script thread through LuaJIT FFI `CreateProcessW`, with no console window. Its stdout is parsed into compact events and streamed back to the UI thread.

Before each message, PoB writes `ClaudeData/context/build_summary.md` and `build.xml`. A short `<pob_context>` header is then prepended to the prompt. It names the build, says whether the build changed since the last message, and includes the key stats.

**Live channel:** `Claude/pob_live.py` drops `live/req_*.lua` files. PoB polls for them every 150 ms and runs each one on the UI thread with `build`, a `pob.*` helper table and a captured `print`. It writes the result to `live/res_*.txt`. That is how Claude reads exact calculated values or changes the open build.

| File | Role |
| --- | --- |
| `Claude/Harness.lua` | session, CLI command line, events, context export, live channel, reload |
| `Claude/ProcessRunner.lua` | sub-script: spawn the process, write stdin, parse stream-json |
| `Claude/SystemPrompt.md` | appended system prompt; edit it to change how Claude behaves here |
| `Claude/pob_live.py` | live-channel client used by Claude |
| `Classes/ClaudePanel.lua` | the UI: chat view with markdown, splitter, collapsed tab, input |
| `ClaudeData/` (gitignored) | `settings.lua`, `chat.lua`, `context/`, `live/` |

The appended system prompt is recorded when a session is created, so edits to `SystemPrompt.md` apply from the next **New** conversation.
