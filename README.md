# SpyWater

Native macOS SwiftUI app + hooks for **Claude Code** and **Antigravity (Gemini)** to monitor, control, and orchestrate parallel AI coding agents from a floating dashboard and menu bar.

## Demo

- [Watch the 24s demo video](assets/demo.mp4)
- English subtitles: [assets/demo.srt](assets/demo.srt)

## Features

- **Live multi-agent dashboard (Claude Code & Antigravity):** Distinct visual states and animations separate **Needs you** (pulsing coral/amber) from **Working** (flowing cyan/emerald), with source filters (`All`, `Claude`, `Antigravity`), model/context/cost indicators (including a `/compact` alert at 80%+), and a reactive corner mascot (*SpyDrop*).
- **Unblock agents from anywhere:** Native cards to **Allow**, **Always Allow**, or **Deny** (with optional feedback), answer `AskUserQuestion` / `ask_question` prompts, and approve or reject `ExitPlanMode` plans. Click any session card to jump directly to its Terminal/iTerm tab, VS Code workspace, or Antigravity window.
- **Dedicated Plan Usage tab:** Track Claude Code 5-hour and 7-day rate limits (via status line wrapper + local cache) alongside local token, turn, cost, and top-model telemetry for both Claude Code and Antigravity.
- **Multi-agent Missions (Claude Code):** Describe a larger goal and SpyWater splits it into a dependency DAG, launches parallel Claude Code workers inside isolated `git worktree`s, runs verification commands, retries failures, and merges completed branches automatically.
- **Zero third-party dependencies:** Built with pure SwiftUI / SwiftPM on macOS 14+, a local `127.0.0.1` hook server, and an optional English UI toggle (`SPYWATER_LANG=en`).

## Repository Structure

- `.claude-plugin/marketplace.json` — Local plugin marketplace definition for Claude Code
- `plugin/` — `spywater` plugin and hooks (`spy-hook.sh`, `agy-hook.sh`, `statusline-tee.sh`)
- `app/` — Native macOS 14+ SwiftUI application (`SpyWater.app`)
- `scripts/` — App builder, Claude Code status line / Antigravity hook installers, self-tests, and demo recorder
- `assets/` — Demo video and English subtitles (`demo.mp4`, `demo.srt`)

## Build & Install

### 1. Build the app

```bash
./scripts/build-app.sh
```

Compiles a release build with SwiftPM and installs the locally signed bundle to `~/Applications/SpyWater.app`.

### 2. Install the Claude Code plugin

```bash
claude plugin marketplace add "$(pwd)"
claude plugin install spywater@spywater-local
```

### 3. Enable Claude Code status line integration (5h / 7d rate limits)

```bash
./scripts/install-statusline.sh
```

### 4. Install Antigravity / Gemini hooks

```bash
./scripts/install-agy-hooks.sh
```

Configures the `"spywater"` entry in `~/.gemini/config/hooks.json` (creating a backup at `~/.gemini/config/hooks.json.spywater-bak` if the file already exists). SpyWater also reads `~/.gemini/antigravity/conversation_summaries.db` and local `transcript.jsonl` files directly to surface open conversations, active models, and context usage.

## Usage

1. Launch `SpyWater.app` (available in the Dock and menu bar). Set `SPYWATER_LANG=en` in your environment if you prefer the English UI outside the default Portuguese interface.
2. Run `claude` in your terminal or use **Antigravity** as usual.
3. Permission prompts, questions, and plan approvals appear in the dashboard and menu bar; unanswered prompts automatically fall back to the host terminal/app after the configured timeout (default: 2 minutes).
4. Optional: in **Settings**, enable command interception (`run_command`) for Antigravity if you want to approve shell commands directly from SpyWater.

## Uninstall

```bash
./scripts/uninstall-statusline.sh
./scripts/uninstall-agy-hooks.sh
claude plugin uninstall spywater@spywater-local
claude plugin marketplace remove spywater-local
rm -rf ~/Applications/SpyWater.app ~/.spywater
```

## Known Limitations

- Pressing `Esc` in Claude Code mid-response does not trigger the `Stop` hook, so the session stays marked as working until the next hook event.
- Official Claude plan limit percentages (5h / 7d) appear right after the first session reply with the status line wrapper installed.
- In Antigravity, `ask_question` replies are injected into the `PreToolUse` hook via `deny` + `reason`, whereas `ask_permission` and `run_command` approvals use `auto_approve` / `deny`.
- Switching models mid-session and sending arbitrary text to non-tmux terminals are not supported in this version.
