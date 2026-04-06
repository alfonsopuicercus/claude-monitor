# Claude Monitor — Roadmap

This document tracks planned features, ideas, and known improvements.
Contributions welcome — see [README.md](README.md) for project structure.

---

## v1.1 — Polish & UX

- [ ] **Scroll inside expanded island** when there are many sessions (currently capped at ~5)
- [ ] **Dismiss individual sessions** with a swipe or close button
- [ ] **Sound feedback** on permission request (system alert sound, toggleable)
- [ ] **Permission auto-deny timeout** — configurable N-second countdown before auto-denying if user ignores
- [ ] **Click-through on non-pill area** — clicks should pass to windows below the transparent window container
- [ ] **Drag to reposition** the island (some users may not have a notch and want to place it differently)
- [ ] **Keyboard shortcut** to expand/collapse (e.g. ⌘⇧C)
- [ ] **Quit button** inside the expanded island (remove reliance on menu bar item)
- [ ] **Dark/light appearance** — currently always dark; add auto-switch mode

---

## v1.2 — Multi-source Support

- [ ] **Codex** support (`--source codex` bridge flag already supported)
- [ ] **Cursor** support (Cursor uses a SQLite-based state that can be read directly)
- [ ] **Gemini CLI** support
- [ ] **Source icon** in each session card showing which AI is running

---

## v1.3 — Session History

- [ ] **Session log view** — expandable transcript of the session (read from `~/.claude/sessions/*.json`)
- [ ] **Cost tracker** — parse token usage from session files, show running cost estimate
- [ ] **Duration display** — how long the session has been active
- [ ] **Export session** to markdown

---

## v1.4 — Notifications

- [ ] **macOS notification** when Claude completes a task (Notification hook → `UNUserNotificationCenter`)
- [ ] **Permission request notification** when island is not visible (e.g. another Space)
- [ ] **Configurable notification events** (only "task complete", or everything)

---

## v1.5 — Configuration UI

- [ ] **Settings panel** accessible from the island or menu bar
  - Toggle: show/hide menu bar icon
  - Toggle: auto-expand on permission request
  - Toggle: sound feedback
  - Slider: permission auto-deny timeout
  - Theme: dark / light / system
- [ ] **Island position presets**: top-center (default), top-left, top-right
- [ ] **Config file** at `~/.claude-monitor/config.json`

---

## v2.0 — Live Output Streaming

- [ ] **Stream Claude's output** directly in the island — show the text being generated in real time
  - Requires hooking into the PTY / pipe that Claude Code runs in
  - Could use `script(1)` wrapper or PTY capture
- [ ] **Collapsible output pane** in expanded view with last N lines of Claude's response
- [ ] **Tool output preview** — show first few lines of Bash/command output

---

## v2.1 — Remote / Multi-machine

- [ ] **WebSocket bridge** — forward events to a web dashboard for remote monitoring
- [ ] **Multiple machine support** — aggregate sessions from several machines in one island
- [ ] **SSH session detection** — detect when Claude is running on a remote machine via SSH

---

## Technical Debt / Known Issues

- The window is a fixed max size; content inside uses SwiftUI animations but the window frame is updated separately (can cause slight mismatch on very slow machines)
- Permission FDs are held open indefinitely — should add a 24h watchdog to close stale ones
- `sessions.json` grows unboundedly if stale sessions aren't pruned (currently 5-min idle prune)
- No error recovery if the socket file is left from a crashed instance on a different UID

---

## Completed (v1.0)

- [x] Unix socket server for receiving Claude Code hook events
- [x] Bridge binary (`claude-monitor-bridge`) registered as Claude Code hooks
- [x] Session tracking: status, cwd, current tool, last user message, last notification
- [x] Dynamic Island-style overlay window (top center, always on top, animated)
- [x] Permission request UI with Approve / Deny buttons
- [x] Glow animation on activity and permission requests
- [x] Expand / collapse with spring animation
- [x] Minimal menu bar icon with quit option
- [x] Auto-prune idle sessions after 5 minutes
- [x] Session persistence to disk across app restarts
