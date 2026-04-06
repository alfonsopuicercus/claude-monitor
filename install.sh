#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")"; pwd)"
APP_NAME="Claude Monitor"
BRIDGE_DEST="$HOME/.claude-monitor/bin/claude-monitor-bridge"
APP_SRC="$PROJECT_DIR/build/$APP_NAME.app"

echo "Installing Claude Monitor..."

# Build first if needed
if [ ! -f "$APP_SRC/Contents/MacOS/$APP_NAME" ]; then
    bash "$PROJECT_DIR/build.sh"
fi

# Install bridge binary
mkdir -p "$(dirname "$BRIDGE_DEST")"
cp "$PROJECT_DIR/.build/release/claude-monitor-bridge" "$BRIDGE_DEST"
chmod +x "$BRIDGE_DEST"
echo "✓ Bridge installed at $BRIDGE_DEST"

# Install app
cp -R "$APP_SRC" /Applications/
echo "✓ App installed at /Applications/$APP_NAME.app"

# Update Claude Code hooks
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    echo "Updating Claude Code hooks..."
    python3 - << PYEOF
import json

with open('$SETTINGS') as f:
    settings = json.load(f)

bridge = '$BRIDGE_DEST'
changed = False
for hook_name, entries in settings.get('hooks', {}).items():
    for entry in entries:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            if 'vibe-island-bridge' in cmd or 'claude-monitor-bridge' in cmd:
                h['command'] = f'{bridge} --source claude'
                changed = True

if not changed:
    # Add hooks if none exist
    hook_cmd = {'type': 'command', 'command': f'{bridge} --source claude'}
    hook_block = {'matcher': '*', 'hooks': [hook_cmd]}
    if 'hooks' not in settings:
        settings['hooks'] = {}
    for event in ['PreToolUse', 'PostToolUse', 'UserPromptSubmit', 'Notification', 'SessionStart', 'SessionEnd']:
        if event not in settings['hooks']:
            settings['hooks'][event] = [hook_block]
    permission_hook = {'matcher': '*', 'hooks': [{'type': 'command', 'command': f'{bridge} --source claude', 'timeout': 86400}]}
    settings['hooks']['PermissionRequest'] = [permission_hook]

with open('$SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
print('  Claude Code hooks updated')
PYEOF
fi

echo ""
echo "Starting Claude Monitor..."
open "/Applications/$APP_NAME.app"
echo ""
echo "✓ Installation complete!"
echo ""
echo "Claude Monitor is now running in your menu bar."
