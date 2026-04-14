#!/usr/bin/env bash
# Install scan-repo as a Claude Code skill + slash command.
# Idempotent — overwrites previous install.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_SRC="$REPO_ROOT/skill/SKILL.md"
HELPERS_SRC="$REPO_ROOT/tools/helpers.sh"
COMMAND_SRC="$REPO_ROOT/skill/scan-repo.command.md"
GOOD_LIST_SRC="$REPO_ROOT/docs/superpowers/specs/calibration/known-good.txt"

SKILL_DIR="$HOME/.claude/skills/scan-repo"
COMMAND_DIR="$HOME/.claude/commands"
COMMAND_DST="$COMMAND_DIR/scan-repo.md"

for f in "$SKILL_SRC" "$HELPERS_SRC" "$COMMAND_SRC" "$GOOD_LIST_SRC"; do
    [[ -f "$f" ]] || { echo "install: missing source: $f" >&2; exit 1; }
done

# Check dependencies
command -v gh >/dev/null 2>&1 || { echo "install: gh CLI not found — https://cli.github.com/" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "install: jq not found — install jq first" >&2; exit 1; }

mkdir -p "$SKILL_DIR" "$COMMAND_DIR"

cp "$SKILL_SRC"     "$SKILL_DIR/SKILL.md"
cp "$HELPERS_SRC"   "$SKILL_DIR/helpers.sh"
cp "$GOOD_LIST_SRC" "$SKILL_DIR/known-good.txt"
cp "$COMMAND_SRC"   "$COMMAND_DST"

chmod +x "$SKILL_DIR/helpers.sh"

echo "install: scan-repo installed."
echo "  skill:    $SKILL_DIR/"
echo "  command:  $COMMAND_DST"
echo
echo "Try it:"
echo "  /scan-repo https://github.com/anthropics/claude-code"
