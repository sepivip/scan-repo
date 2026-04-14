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
assert_true "grep -q '## Ecosystem detection' '$SKILL'" \
    "skill: ecosystem detection section"
assert_true "grep -q 'Cargo.toml' '$SKILL'" \
    "skill: ecosystem detection includes Rust"

assert_true "grep -q '## Quick-check tier' '$SKILL'" \
    "skill: quick-check tier section"
assert_true "grep -q '### Q1 — Author profile' '$SKILL'" \
    "skill: Q1 quick check"
assert_true "grep -q '### Q2 — Repo basics' '$SKILL'" \
    "skill: Q2 quick check"
assert_true "grep -q '### Q6 — Install hook' '$SKILL'" \
    "skill: Q6 quick check"
assert_true "grep -qF 'is_benign_install_hook' '$SKILL'" \
    "skill: Q6 calls benign allowlist helper"
assert_true "grep -qF '🟢 nothing obviously wrong' '$SKILL'" \
    "skill: quick-check green verdict line"
assert_true "grep -qF '🟡 a few things look unusual' '$SKILL'" \
    "skill: quick-check yellow verdict line"

assert_true "grep -q '## Full audit' '$SKILL'" \
    "skill: full audit section"
assert_true "grep -q '### Check 1 — Author profile (full)' '$SKILL'" \
    "skill: full check 1"
assert_true "grep -q '### Check 2 — Repo basics (full)' '$SKILL'" \
    "skill: full check 2"
assert_true "grep -q '### Check 4 — Activity ratios' '$SKILL'" \
    "skill: full check 4"
assert_true "grep -q '### Check 5 — Star history link' '$SKILL'" \
    "skill: full check 5"
assert_true "grep -q 'star-history.com' '$SKILL'" \
    "skill: star-history URL emitted"

assert_true "grep -q '### Check 3 — Stargazer sample' '$SKILL'" \
    "skill: full check 3"
assert_true "grep -q 'is_empty_profile' '$SKILL'" \
    "skill: check 3 calls is_empty_profile"
assert_true "grep -q 'HC_WARNS=\$((HC_WARNS+1))' '$SKILL'" \
    "skill: check 3 sets high-confidence on >=50% empty"

assert_true "grep -q '### Check 6 — Install scripts (full)' '$SKILL'" \
    "skill: full check 6"
assert_true "grep -q '### Check 7 — Binaries in tree' '$SKILL'" \
    "skill: full check 7"
assert_true "grep -q '### Check 8 — Provenance' '$SKILL'" \
    "skill: full check 8"
assert_true "grep -q 'has_suspicious_pattern' '$SKILL'" \
    "skill: check 6 calls suspicious pattern helper"
assert_true "grep -q 'is_forbidden_executable' '$SKILL'" \
    "skill: check 7 calls forbidden-extension helper"
assert_true "grep -q 'is_in_recognized_build_path' '$SKILL'" \
    "skill: check 7 calls build-path helper"
assert_true "grep -q 'registry.npmjs.org' '$SKILL'" \
    "skill: check 8 hits npm registry"

assert_true "grep -q '## Verdict & output' '$SKILL'" \
    "skill: verdict & output section"
assert_true "grep -q 'compute_verdict' '$SKILL'" \
    "skill: full audit calls compute_verdict"
assert_true "grep -q 'verdict_label' '$SKILL'" \
    "skill: full audit calls verdict_label"
assert_true "grep -q 'I.\?d suggest looking at' '$SKILL'" \
    "skill: yellow directive closing"
assert_true "grep -q 'I don.\?t recommend installing' '$SKILL'" \
    "skill: red directive closing"
assert_true "grep -q '## Edge cases' '$SKILL'" \
    "skill: edge cases section"
assert_true "grep -q '## Self-test' '$SKILL'" \
    "skill: self-test section"

report
