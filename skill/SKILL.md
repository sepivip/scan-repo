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

## Setup

Source the helpers (assumes installed location, with a fallback for local dev):

```bash
HELPERS="${SCAN_REPO_HELPERS:-$HOME/.claude/skills/scan-repo/helpers.sh}"
[[ -f "$HELPERS" ]] || { echo "scan-repo: helpers.sh not found — run tools/install.sh" >&2; exit 1; }
source "$HELPERS"
```

## Layered gating (run on every invocation)

### Step 0 — URL extraction

Extract a github.com URL from the input. If none, abort silently (produce no output).

```bash
TARGET="$(extract_url "$INPUT")"
[[ -z "$TARGET" ]] && exit 0
OWNER_REPO="${TARGET%@*}"
BRANCH="${TARGET##*@}"
[[ "$BRANCH" == "$OWNER_REPO" ]] && BRANCH=""
```

### Step 1 — Intent & mode detection

Read the user's message naturally. Decide:

- **MODE=full** — the user *explicitly* asked for a deep / full / complete audit, said "run all checks", or invoked this skill via the `/scan-repo` slash command (the command's file content says "Run a full audit..."). If the invocation context contains phrases like "full audit", "run all 8 checks", "explicit audit", treat as full.
- **MODE=quick** — the user expressed install / clone / try / use intent ("should I install", "is it safe to", "can I trust", etc.), but did not request a full audit.
- **Abort silently** — the user merely shared a URL for context, asked about an issue/PR, or referenced docs without install intent. Produce no output at all.

This is a natural-language judgment — just read the message and decide.

### Step 2 — Memoization check

Claude-side responsibility: check conversation history for prior scan-repo activity on `{OWNER_REPO}@{BRANCH}` (default branch if BRANCH is empty). If a prior result exists in the conversation, emit one of:

> *(scan-repo already ran a quick check on github.com/{OWNER_REPO} earlier in this conversation — verdict was [🟢|🟡]. For full audit run /scan-repo {URL})*

> *(scan-repo already ran a full audit on github.com/{OWNER_REPO} earlier in this conversation — verdict was [🟢|🟡|🔴|⚪]. See prior message for findings.)*

…and exit. Memoization is best-effort — after context compaction the prior result may be invisible and the skill will re-fire.

### Step 3 — Branch resolution

```bash
[[ -z "$BRANCH" ]] && BRANCH="$(gh api "repos/$OWNER_REPO" --jq .default_branch)"
```

## Ecosystem detection

```bash
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
```

## Quick-check tier (MODE=quick)

Three checks. Tighter thresholds than the full audit (a false alarm here trains users to ignore real ones).

### Q1 — Author profile

```bash
AUTHOR_JSON="$(gh api "users/${OWNER_REPO%%/*}")"
AUTHOR_CREATED="$(echo "$AUTHOR_JSON" | jq -r .created_at)"
AUTHOR_REPOS="$(echo "$AUTHOR_JSON"   | jq -r .public_repos)"

age=$(age_days "$AUTHOR_CREATED")

Q1_RESULT=pass
Q1_EVIDENCE="Author account ${age}d old, ${AUTHOR_REPOS} other repo(s)"
if [[ "$age" -lt 30 && "$AUTHOR_REPOS" -lt 3 ]]; then
    Q1_RESULT=warn
fi
```

### Q2 — Repo basics

```bash
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
```

### Q6 — Install hook presence + allowlist

```bash
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
```

### Quick-check verdict and output

```bash
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
```

## Full audit (MODE=full)

Initialise accumulators:

```bash
WARNS=0
HC_WARNS=0
SKIPS=0
declare -a FINDINGS
```

### Check 1 — Author profile (full)

```bash
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
```

### Check 2 — Repo basics (full)

```bash
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
```

### Check 4 — Activity ratios

```bash
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
```

### Check 5 — Star history link

```bash
FINDINGS+=("— Star history (eyeball): https://star-history.com/#${OWNER_REPO}&Date")
```
