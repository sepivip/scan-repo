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

report
