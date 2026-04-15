#!/usr/bin/env bash
# scan-repo calibration check.
#
# Runs the scan-repo skill (full audit) against each URL in known-good.txt,
# counts warns, and exits non-zero if threshold or more unjustified warns
# surface.
#
# Usage:
#   tools/calibration-check.sh
#   tools/calibration-check.sh --good-list path/to/list.txt --threshold 3
#   tools/calibration-check.sh --dry-run   # skip gh, use SCAN_REPO_FAKE_WARN_COUNT env

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GOOD_LIST="$REPO_ROOT/docs/superpowers/specs/calibration/known-good.txt"
JUSTIFIED="$REPO_ROOT/docs/superpowers/specs/calibration/justified-warns.md"
THRESHOLD=3
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --good-list) GOOD_LIST="$2"; shift 2 ;;
        --threshold) THRESHOLD="$2"; shift 2 ;;
        --dry-run)   DRY_RUN=1; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ ! -e "$GOOD_LIST" ]]; then
    echo "calibration: known-good list not found: $GOOD_LIST" >&2
    exit 2
fi

count_warns_for_url() {
    local url="$1"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "${SCAN_REPO_FAKE_WARN_COUNT:-0}"
        return 0
    fi
    if [[ ! -x "$REPO_ROOT/tools/run-skill.sh" ]]; then
        echo "calibration: tools/run-skill.sh not found — live calibration requires runner" >&2
        return 0
    fi
    "$REPO_ROOT/tools/run-skill.sh" --url "$url" --mode full --output-format count-warns
}

count_justified_for_url() {
    local url="$1"
    local owner_repo
    owner_repo="$(echo "$url" | sed -E 's#https?://github\.com/##; s#/$##')"
    if [[ ! -e "$JUSTIFIED" ]]; then
        echo 0
        return
    fi
    awk -v target="$owner_repo" '
        /^## / { in_section = ($2 == target); next }
        in_section && /^- check:/ { count++ }
        END { print count + 0 }
    ' "$JUSTIFIED"
}

total_unjustified=0
repo_count=0

while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    repo_count=$((repo_count + 1))
    warns=$(count_warns_for_url "$line")
    justified=$(count_justified_for_url "$line")
    unjustified=$((warns - justified))
    [[ "$unjustified" -lt 0 ]] && unjustified=0
    if [[ "$unjustified" -gt 0 ]]; then
        printf 'calibration: %s — %d unjustified warn(s)\n' "$line" "$unjustified"
    fi
    total_unjustified=$((total_unjustified + unjustified))
done < "$GOOD_LIST"

printf 'calibration: %d repos checked, %d total unjustified warn(s) (threshold: %d)\n' \
    "$repo_count" "$total_unjustified" "$THRESHOLD"

if [[ "$total_unjustified" -ge "$THRESHOLD" ]]; then
    echo 'calibration: FAIL — threshold exceeded' >&2
    exit 1
fi

echo 'calibration: PASS'
exit 0
