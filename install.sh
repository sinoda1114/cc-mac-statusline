#!/bin/bash
# cc-mac-statusline installer (macOS)
# Installs statusline.sh and merges statusLine config into ~/.claude/settings.json
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
claude_dir="$HOME/.claude"
script_dest="$claude_dir/statusline.sh"
settings_path="$claude_dir/settings.json"

# 1. Ensure ~/.claude exists
mkdir -p "$claude_dir"

# 2. Copy statusline.sh
cp -f "$repo_root/template/statusline.sh" "$script_dest"
chmod +x "$script_dest"
echo "Installed: $script_dest"

# 3. Verify dependencies
missing=()
for cmd in bash jq git; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
# GNU coreutils (gdate) check — script relies on `date -d` / `stat -c`
if [ ! -x "/opt/homebrew/opt/coreutils/libexec/gnubin/date" ] \
   && ! date -d "@0" +%s >/dev/null 2>&1; then
    missing+=("coreutils")
fi
if [ ${#missing[@]} -gt 0 ]; then
    echo "WARNING: not found / not GNU: ${missing[*]}"
    echo "  brew install coreutils jq git"
fi

# 4. Merge statusLine config into settings.json
status_cfg='{"type":"command","command":"bash ~/.claude/statusline.sh","refreshInterval":5000}'
if [ -f "$settings_path" ]; then
    backup="$settings_path.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$settings_path" "$backup"
    echo "Backed up existing settings.json to $backup"
    tmp="$(mktemp)"
    jq --argjson sl "$status_cfg" '.statusLine = $sl' "$settings_path" > "$tmp"
    mv "$tmp" "$settings_path"
else
    echo "{\"statusLine\": $status_cfg}" | jq '.' > "$settings_path"
fi
echo "Updated: $settings_path"
echo ""
echo "Done. Restart Claude Code to see the status line."
