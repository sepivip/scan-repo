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
