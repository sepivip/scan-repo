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

### Check 3 — Stargazer sample (dual-page)

```bash
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
```

### Check 5 — Star history link

```bash
FINDINGS+=("— Star history (eyeball): https://star-history.com/#${OWNER_REPO}&Date")
```

### Check 6 — Install scripts (full)

```bash
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
```

### Check 7 — Binaries in tree

```bash
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
```

### Check 8 — Provenance

```bash
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
```

## Verdict & output (full audit)

```bash
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
```

## Edge cases

- **Repo 404 / private:** `gh api repos/$OWNER_REPO` returns non-zero exit. Catch and print: `scan-repo: cannot access $OWNER_REPO (404 or private). No verdict.` then exit 0.
- **`gh` not installed:** Print install link, exit 0.
- **`gh` unauthenticated:** prepend warning to report.
- **Rate limit hit mid-run:** mark check `skip`, continue.
- **`curl` exceeds size/time limit:** treat as missing fetch; check emits `· skipped (fetch exceeded limit — possible DoS)`.
- **`/scan-repo` with no URL:** slash command file short-circuits.

## Self-test

```bash
if [[ "${1:-}" == "--self-test" ]]; then
    GOOD_LIST="$HOME/.claude/skills/scan-repo/known-good.txt"
    [[ ! -f "$GOOD_LIST" ]] && GOOD_LIST="$(dirname "$HELPERS")/known-good.txt"
    URLS=( $(grep -vE '^[[:space:]]*(#|$)' "$GOOD_LIST") )
    PICK="${URLS[$(( RANDOM % ${#URLS[@]} ))]}"
    echo "self-test: scanning $PICK"
    INPUT="Run a full audit with scan-repo on $PICK. Run all 8 checks." exec bash "$0"
fi
```
