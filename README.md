# Claude Monitor

An open-source macOS menu bar app that tracks your Claude Code sessions in real time — showing what Claude is doing, which tool it's running, and letting you approve or deny permission requests without switching windows.

Built as an open-source alternative to [Vibe Island](https://vibeisland.app).

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

---

## Features

- **Live session tracking** — see every active Claude Code session, its working directory, and what it's doing
- **Tool indicator** — color-coded badge shows the current tool (Bash, Edit, Read, WebSearch, Subagent, …)
- **Last message preview** — see the user's last prompt and Claude's last notification inline
- **Permission requests** — when Claude needs approval to run a tool, the menu bar turns orange and shows Approve / Deny buttons
- **Session details** — expand any session to see tool input, session ID, TTY, start time
- **Persisted state** — sessions survive app restarts (stored in `~/Library/Application Support/ClaudeMonitor/`)
- **Auto-cleanup** — sessions idle for more than 5 minutes are pruned automatically

---

## Architecture

```
Claude Code session
       │
       │  (hook events via stdin JSON)
       ▼
claude-monitor-bridge          ← small CLI binary, called by Claude Code hooks
       │
       │  (Unix socket: /tmp/claude-monitor.sock)
       ▼
Claude Monitor.app             ← macOS menu bar app
       │
       │  (DispatchQueue.main)
       ▼
SessionStore (ObservableObject)
       │
       │  persists to ~/Library/Application Support/ClaudeMonitor/sessions.json
       ▼
SwiftUI MenuBarView            ← popover shown when you click the menu bar icon
```

### Hook events handled

| Event | Effect |
|-------|--------|
| `SessionStart` | New session appears |
| `SessionEnd` | Session marked idle |
| `UserPromptSubmit` | Shows user's prompt, status → working |
| `PreToolUse` | Shows current tool badge |
| `PostToolUse` | Clears tool badge |
| `PermissionRequest` | Menu bar turns orange, shows Approve/Deny |
| `Notification` | Shows Claude's message |
| `SubagentStart/Stop` | Shows subagent activity |
| `Stop` | Session marked idle |

### Permission request flow

```
Claude needs permission
        │
        ▼
bridge sends PermissionRequest to socket (keeps connection open)
        │
        ▼
App shows orange badge + Approve/Deny buttons
        │
  user clicks
        │
        ▼
App sends {"continue": true/false} back through the open socket fd
        │
        ▼
bridge writes response to stdout (Claude Code reads it)
```

---

## Requirements

- macOS 13 Ventura or later
- Swift 5.9+ (for building from source)
- Claude Code CLI

---

## Installation

### From source (recommended)

```bash
git clone https://github.com/alfonsopuicercus/claude-monitor
cd claude-monitor
bash install.sh
```

This will:
1. Build the app with `swift build -c release`
2. Ad-hoc sign the `.app` bundle
3. Copy it to `/Applications/`
4. Install the bridge binary to `~/.claude-monitor/bin/`
5. Update your `~/.claude/settings.json` hooks
6. Launch the app

### Manual build

```bash
bash build.sh
cp -R "build/Claude Monitor.app" /Applications/
open "/Applications/Claude Monitor.app"
```

---

## Uninstall

```bash
# Remove app
rm -rf "/Applications/Claude Monitor.app"

# Remove bridge
rm -rf ~/.claude-monitor/

# Restore hooks (edit ~/.claude/settings.json manually, remove claude-monitor-bridge lines)
```

---

## How it works with Claude Code

Claude Code supports [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) — shell commands that fire on lifecycle events. `install.sh` registers `claude-monitor-bridge` for all relevant hooks in `~/.claude/settings.json`.

Each time a hook fires, Claude Code passes a JSON payload via stdin to the bridge. The bridge forwards it to the app via a Unix socket (`/tmp/claude-monitor.sock`). The app updates its state and UI.

For `PermissionRequest` hooks, Claude Code waits for the bridge to exit before continuing. The bridge keeps the socket connection open until the user clicks Approve or Deny in the menu bar, then outputs `{"continue": true}` or `{"continue": false}` and exits.

---

## Project structure

```
claude-monitor/
├── Package.swift                        # SPM package definition
├── build.sh                             # Build script
├── install.sh                           # Install script
├── Sources/
│   ├── ClaudeMonitor/                   # Menu bar app
│   │   ├── main.swift                   # NSApplication entry point
│   │   ├── AppDelegate.swift            # NSStatusItem + popover setup
│   │   ├── SessionStore.swift           # Observable state + socket server
│   │   └── MenuBarView.swift            # SwiftUI views
│   └── Bridge/                          # Bridge CLI binary
│       └── main.swift                   # Hook → socket forwarding
├── README.md
└── ROADMAP.md
```

---

## Contributing

PRs welcome. Some ideas to start with are in [ROADMAP.md](ROADMAP.md).

---

## License

MIT — see [LICENSE](LICENSE).
