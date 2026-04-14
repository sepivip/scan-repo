#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

SKILL="$SCRIPT_DIR/../skill/SKILL.md"

assert_true "grep -q '^name: scan-repo$' '$SKILL'" \
    "skill: name in frontmatter"
assert_true "grep -q '^description:' '$SKILL'" \
    "skill: description present"
assert_true "grep -q 'install, clone, run, try, test, or use' '$SKILL'" \
    "skill: description names intent tokens"
assert_true "grep -q 'Do NOT use' '$SKILL'" \
    "skill: description has anti-trigger guidance"
assert_true "grep -q 'reference the prior result' '$SKILL'" \
    "skill: description mentions memoization"

assert_true "grep -q '## Layered gating' '$SKILL'" \
    "skill: layered gating section"
assert_true "grep -q 'Step 0 — URL extraction' '$SKILL'" \
    "skill: gate step 0"
assert_true "grep -q 'Step 1 — Intent' '$SKILL'" \
    "skill: gate step 1 intent detection"
assert_true "grep -q 'Step 2 — Memoization' '$SKILL'" \
    "skill: gate step 2 memoization"
assert_true "grep -q 'Step 3 — Branch resolution' '$SKILL'" \
    "skill: gate step 3 branch resolution"
assert_true "grep -q 'extract_url' '$SKILL'" \
    "skill: calls extract_url helper"

report
