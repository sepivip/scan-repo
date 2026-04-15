#!/usr/bin/env bash
# Install the calibration pre-commit hook. Idempotent.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_DIR="$REPO_ROOT/.git/hooks"
HOOK_FILE="$HOOK_DIR/pre-commit"

if [[ ! -d "$REPO_ROOT/.git" ]]; then
    echo "install-hooks: not a git repo (no .git at $REPO_ROOT)" >&2
    exit 1
fi

mkdir -p "$HOOK_DIR"

cat > "$HOOK_FILE" <<'HOOK_EOF'
#!/usr/bin/env bash
# scan-repo pre-commit gate: if SKILL.md or helpers.sh changes, calibration must pass.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CHANGED="$(git diff --cached --name-only)"

if echo "$CHANGED" | grep -qE '^skill/SKILL\.md$|^tools/helpers\.sh$'; then
    echo 'pre-commit: SKILL.md or helpers.sh changed — running calibration check…'
    if ! "$REPO_ROOT/tools/calibration-check.sh"; then
        echo 'pre-commit: calibration check failed; commit blocked.' >&2
        echo '            Either tune SKILL.md or update justified-warns.md.' >&2
        exit 1
    fi
fi

exit 0
HOOK_EOF

chmod +x "$HOOK_FILE"
echo "install-hooks: installed $HOOK_FILE"
