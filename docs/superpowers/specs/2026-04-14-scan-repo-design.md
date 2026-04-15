# scan-repo — design spec

**Date:** 2026-04-14
**Status:** Draft v7 (audience clarified — vibe coders; soft verdicts reintroduced)

## Problem

Non-technical users ("normies") routinely clone or `npm install` GitHub
repositories they found minutes ago — MCP servers, AI tools, Claude Code
extensions, Cursor plugins. The trust signals they rely on (stars, forks,
recent commits) are now cheap to fake: $64 buys 1,000 stars; CMU's
StarScout found 6M fake stars across 15,835 repos in 2024. Recent malware
campaigns (e.g. the March 2026 fake "leaked Claude Code source" repo with
564 stars / 793 forks shipping the Vidar infostealer) show the attack
working in the wild.

The dangerous moment is the *first* one: cloning, running `npm install`,
or executing a release binary. By then a malicious post-install hook has
already run.

## Goal

A Claude Code skill that, given a github.com URL, gathers and surfaces
**evidence** about the repo without cloning or executing anything, and
emits a **soft, deflating verdict** the user's agent can interpret and
explain in plain English.

**Audience:** "vibe coders" — people who use a coding agent (Claude
Code, Cursor, Copilot CLI, etc.) but don't read code themselves. They
paste a GitHub URL, say "install this for me," and trust the agent.
The skill is the agent's pre-flight check on their behalf.

**Soft verdicts, not safety judgments.** Each verdict label carries
its own caveat in the wording itself, so the user can't strip it to
"SAFE." Verdicts describe *what we observed*, not *what is true*:

- 🟢 **Nothing obviously wrong** — proceed if you trust the source
- 🟡 **A few things look unusual** — worth a closer look
- 🔴 **Several things look concerning** — recommend not installing
  without expert review
- ⚪ **Couldn't gather enough signal** — cannot assess

The verdict gives vibe coders a steer; their agent explains the
findings in plain English on the next turn.

## What this skill is NOT

- **Not a safety guarantee.** Findings are signals only.
- **Not a complete supply-chain audit.** Inspects the target repo's
  manifest only; transitive deps are a known gap.
- **Not a secret playbook.** Ships in plaintext.
- **Not validated.** Thresholds are placeholders pending calibration.
- **Not behavior-changing in a measured way.**
- **Not a chain of custody.** Plaintext output, no signature.
- **Not free.** Each invocation spends Claude tokens on tool calls and
  interpretation. Auto-trigger is intentionally cheap on API cost
  (~5–9 GitHub API calls); full audit is intentionally heavy
  (~50+ calls). Both spend Claude tokens. Power users running many
  audits should be aware.
- **Not the only thing the user should do.**

## Non-goals

- Sandboxed execution or cloning of the target repo.
- Recursive supply-chain scan (v2).
- Hosts other than github.com (v2).
- Auto-installing missing dependencies.
- Definitive malware detection.
- Hard verdicts ("SAFE" / "MALICIOUS"). All v1 verdicts are soft and
  carry their own caveat in the label text.
- Localization beyond English (v2).

## Audience

- Primary: developers of any level evaluating an unfamiliar GitHub
  repo before installing.
- Secondary: experienced users who want a fast pre-flight check.

## Naming & locations

| Artifact | Path |
|---|---|
| Skill | `~/.claude/skills/scan-repo/SKILL.md` |
| Slash command | `~/.claude/commands/scan-repo.md` |
| Calibration dataset | `e:/GIT/repoguard/docs/superpowers/specs/calibration/` |
| Calibration check script | `e:/GIT/repoguard/tools/scan-repo-calibration-check.sh` |
| Dev workspace | `e:/GIT/repoguard/` |

## Invocation overview

The skill behaves as **two distinct products**, sharing one playbook:

| Entry point | Tier | Approx. duration | API calls | Output style |
|---|---|---|---|---|
| Auto-trigger (intent-gated) | Quick check | 5–10 s | 5–9 | One-line ambient |
| Auto-trigger, quick check warned | Quick + escalation prompt | 5–10 s | 5–9 | One-line warning + CTA |
| `/scan-repo <url>` | Full audit | 30–60 s | 50+ | Streaming findings + summary + closing question |

Auto-trigger is an **ambient guardrail**, not an audit. The slash
command is the audit.

## Auto-trigger UX

### Architecture: layered gating

Two distinct gating layers, with different reliability properties:

1. **Description match (fuzzy, LLM-judged).** Claude decides whether to
   invoke the skill based on the SKILL.md `description`. This is
   probabilistic pattern matching. We cannot rely on it for precision.

2. **Playbook gate (deterministic).** Once invoked, the playbook runs
   the following steps in order. Each step can abort silently:

   - **Step 0 — URL extraction.** Extract `github.com/{owner}/{repo}`
     from input. Normalize URLs that include path, branch, or
     tree/blob fragments to `owner/repo`. If none found, abort silently
     (no output). Capture branch if present, default to repo's
     `default_branch` when unspecified.
   - **Step 1 — Intent gate.** Check input for intent token
     (case-insensitive, word-bounded match against the intent token
     list below). If none AND input does not contain
     `Invocation mode: explicit`, abort silently.
   - **Step 2 — Memoization check.** Check conversation history for
     prior scan-repo activity on `{owner}/{repo}@{branch}`. If found,
     emit the memo line and abort. (Best-effort — see Memoization
     limits below.)
   - **Step 3 — Mode dispatch.** Input contains
     `Invocation mode: explicit` → run full audit.
     Otherwise → run quick-check tier.

The intent token list (case-insensitive, word-bounded):
`install`, `clone`, `try`, `test`, `use`, `run`, `should I`,
`is it safe`, `safe to`, `can I trust`, `thoughts on`, `recommend`.

The list lives in SKILL.md so power users can tighten or loosen it.

### Memoization limits

Memoization keys on `{owner}/{repo}@{branch}`. The default branch is
fetched once when no branch is specified.

**This is best-effort, not guaranteed.** In long conversations or
after context compaction, the memo can silently fail and the skill
will re-fire. Spec acknowledges this as a v1 limit; a real
cross-session cache is a v2 item.

Memo output (when prior scan found) is explicit about which tier ran:

> *(scan-repo already ran a **quick check** on github.com/foo/bar
> earlier in this conversation — for full audit run `/scan-repo <url>`)*

> *(scan-repo already ran a **full audit** on github.com/foo/bar
> earlier in this conversation — see prior message for findings)*

### Quick-check tier

When fired (and not explicit mode), the playbook runs **only the
cheapest 3 checks** with **separate, tighter thresholds**:

- Check 1Q: author profile (1 API call)
- Check 2Q: repo basics (1 API call)
- Check 6Q: install-hook presence + cheap allowlist (1–4 raw fetches)

Plus 1–2 calls for ecosystem detection (manifest probes). Total
budget: 5–9 API calls. Multi-ecosystem repos hit the upper end.

#### Quick-check threshold rules (tighter than full audit)

The full audit's thresholds are tuned for "user asked, depth justifies
noise." The quick tier's thresholds are tuned for "user did not ask,
any false alarm trains them to ignore real ones." Quick-tier rules:

**Check 1Q — Author profile:**
- `warn` only if **(account age < 30 days AND public_repos < 3)**.
  Both must be true. (Full audit warns on either; quick tier requires
  both because every first-time GitHub publisher trips a single
  signal.)
- `followers == 0` alone is NOT a quick-tier warn (too many legitimate
  users have zero followers).
- else `pass`.

**Check 2Q — Repo basics:**
- `warn` if archived or disabled (deterministic — project not
  maintained).
- `warn` only if **stars/age > 500/day AND repo age < 14 days**.
  (Full audit threshold is 200/day. Quick tier raises to 500 because
  trending Show-HN, official launches, model releases routinely hit
  200–500/day legitimately.)
- else `pass`.

**Check 6Q — Install hooks (presence + cheap allowlist):**
- Fetch manifests (`package.json`, `setup.py`, `pyproject.toml`).
- Parse install hook fields.
- If no install hook present → `pass`.
- If install hook present AND content matches the **known-benign
  allowlist** (exact string equality, zero-cost) → `pass`. Allowlist:
  - `node-gyp rebuild`
  - `prebuild-install`
  - `node-pre-gyp install`
  - `electron-rebuild`
  - `husky install`
  - `husky` (no args)
- If install hook present AND not on allowlist → `warn` "install
  hook will run during install — content not on benign allowlist."

The allowlist match is the same one the full audit uses, applied at
the cheapest tier. This avoids the "every legitimate npm package
warns" failure of the unfiltered presence check.

### Quick-check output

**All quick checks `pass`** → emit one ambient line, then continue
with the user's actual request:

```
[scan-repo: 3 quick checks passed — for full audit run /scan-repo <url>]
```

**Any quick check returns `warn`** → emit one warning + CTA:

```
[scan-repo: quick check found 1 warning — author account 12 days old,
 only 1 other repo. Run /scan-repo <url> for the full audit (~30s).]
```

The user decides whether to escalate. The skill **never** auto-escalates
to a full audit.

### Slash-command path (full audit)

`/scan-repo <url>` always runs the full 8-check audit. The slash
command file at `~/.claude/commands/scan-repo.md`:

> Run the scan-repo skill on the URL: `{{args}}`.
> **Invocation mode: explicit — run full audit, skip quick-check tier.**

The skill's playbook checks for the literal token `Invocation mode:
explicit` in its input context.

### Verification test status

The auto/explicit mode discrimination depends on Claude Code passing
slash command file content into the skill's input context.
**Verification status: pending — must run before implementation
plan finalizes.**

**Test protocol:**

1. Create a minimal SKILL.md that prints `EXPLICIT_TOKEN_DETECTED`
   when the literal token "Invocation mode: explicit" is detected
   in its input, and `NO_TOKEN` otherwise.
2. Create a slash command at `~/.claude/commands/test-token.md` whose
   body contains only "Invocation mode: explicit. Run test-token
   skill."
3. Invoke `/test-token` in Claude Code. Expect `EXPLICIT_TOKEN_DETECTED`.
4. Trigger the skill via auto-fire path (description match). Expect
   `NO_TOKEN`.

**Fallback if the test fails:** the slash command passes a CLI-style
argument explicitly, e.g.:

> Run scan-repo skill with arg `--mode explicit` on URL: `{{args}}`.

Playbook reads the arg directly via standard skill-input parsing.
Several v6 sections (slash command body, dispatch step 3) would need
minor updates.

### Slash command without URL

`/scan-repo` with no argument prints:

```
Usage: /scan-repo <github-url>
Example: /scan-repo https://github.com/anthropics/claude-code
```

No skill invocation occurs.

## Implementation style

`SKILL.md` is a **playbook** — a numbered sequence of `gh` and `curl`
commands plus interpretation rules — not a compiled script.

## Dependencies

| Tool | Required? | Used for | Fallback |
|---|---|---|---|
| `gh` (authenticated) | required | API calls (5k/hr) | Skill aborts with install instructions |
| `curl` | required | raw file fetches | — |
| `npm` | optional | npm registry lookup for provenance | Skip provenance npm side with note |
| `python` / `pip` | optional | PyPI lookups | Skip Python side with note |

## Fetch hardening

Every `curl` invocation MUST include:

```
curl --max-time 10 --max-filesize 1048576 --fail -sL ...
```

A malicious repo can serve a multi-GB `README.md` or hang the
connection. Without limits, the audit becomes the DoS vector.

## Ecosystem detection

The playbook detects all applicable ecosystems (a repo can have
multiple). The set of applicable checks is the **union** across
detected ecosystems. The header of any output reports the detected set.

| Marker file | Ecosystem |
|---|---|
| `package.json` | Node / npm |
| `pyproject.toml`, `setup.py`, `setup.cfg`, `requirements.txt` | Python |
| `Cargo.toml` | Rust |
| `go.mod` | Go |
| `Gemfile` | Ruby |
| `pom.xml`, `build.gradle*` | JVM |
| `composer.json` | PHP |
| (none of the above) | "no recognized ecosystem" |

Checks that don't apply to *any* detected ecosystem are not run and
are not counted as `skip`.

## Output truncation

Each check's evidence list is capped at **5 examples** in the rendered
output. Additional matches are summarized with `(… and N more)` plus a
hint command the user can run to enumerate everything.

## UX during the run (full audit only)

Per-check status is reported as soon as it completes. Best-effort
streaming — the harness may render checks as separate messages or one
grouped output depending on Claude Code.

## The 8 checks (full audit)

Each check returns one of: `pass`, `warn`, `info`, `skip`. There is
no per-check `fail` outcome — severity is decided at the verdict
layer (see §Verdict logic) by combining warns, with a small set of
"high-confidence" warns weighted to push the verdict to 🔴.

When relevant, findings include 2-3 inline links so the user can
spot-check the claim.

### 1. Author profile

- **Call:** `gh api users/{owner}`
- Heuristics (full audit):
  - `warn` if account age < 30 days, or `public_repos < 3`, or
    `followers == 0`.
  - else `pass`.

### 2. Repo basics

- **Call:** `gh api repos/{owner}/{repo}`
- Heuristics (full audit):
  - `warn` if archived or disabled.
  - `warn` if stars/age > 200/day during first 14 days of repo life.
  - else `pass`.

### 3. Stargazer sample (dual-page)

- Sample 20 stargazers from page 1 (most recent) AND 20 from a random
  middle page. ~40 user lookups.
- For each: `gh api users/{login}` → `created_at`, `followers`,
  `public_repos`.
- **Empty profile** = `followers == 0 && public_repos == 0 && account age < 90 days`.
- Heuristics:
  - `warn` if ≥ 30% of combined sample are empty profiles, OR
    recent-page rate is more than 2× the random-page rate.
  - `skip` if total stars < 50.
  - else `pass`.
- Output: 2-3 sample login URLs `https://github.com/{login}` for
  spot-checking. Truncate per output rule.

### 4. Activity ratios

- Heuristics:
  - `warn` only if **all three**: stars > 5000 AND contributors ≤ 2 AND
    open_issues_count == 0.
  - else `pass`.

### 5. Star history link

- Always emit `https://star-history.com/#{owner}/{repo}&Date` as `info`.

### 6. Install scripts (target repo only)

Applicable to: Node, Python.

- **Calls:** `package.json`, `setup.py`, `pyproject.toml`.
- **Suspicious-pattern regex** (case-insensitive):
  `\b(curl|wget|node\s+-e|python\s+-c|eval|base64|atob)\b`,
  raw IPv4 addresses, `\.onion`, shell pipes to `sh|bash`.
- **Known-benign allowlist** (exact strings only):
  `node-gyp rebuild`, `prebuild-install`, `node-pre-gyp install`,
  `electron-rebuild`, `husky install`, `husky`.
- Heuristics:
  - `warn` if any suspicious pattern matches inside an install hook.
    Output prints the exact line.
  - `warn` if install hook exists and does not match the allowlist.
  - `pass` if no install hooks present, or all install hooks are on
    the allowlist.
  - `skip` if no manifest files exist.
- Known gaps surfaced in output: does not recurse into
  `package-lock.json` / `requirements.txt`; does not inspect Python
  build-backend (PEP 517) hooks, `conftest.py`, or `.pth` auto-imports.

### 7. Binaries in tree

Applicable to: all ecosystems.

- **Call:** `gh api repos/{o}/{r}/git/trees/{branch}?recursive=1`
- **Forbidden extensions:** `.exe`, `.msi`, `.deb`, `.rpm`, `.pkg`,
  `.dmg`.
- **Recognized build-output paths** (downgrade applies *only* when
  paired with the matching ecosystem marker):
  - `dist/`, `build/`, `out/` only if `package.json` or
    `webpack.config.*` / `vite.config.*` / `rollup.config.*` exists.
  - `target/` only if `Cargo.toml` exists.
  - `bin/` only if `Makefile`, `build.sh`, or `go.mod` exists.
  - `_output/` only if `Makefile` or recognized Go layout exists.
- Heuristics:
  - `warn` for any forbidden-extension file.
  - `warn` for any non-forbidden archive (`.zip`, `.7z`, `.rar`,
    `.jar`, `.so`, `.dylib`, `.dll`) > 1MB outside a recognized
    build-output path.
  - Findings inside a recognized build-output path append the note
    "(in conventional build output for this project)" but remain
    `warn`.
  - `pass` otherwise.
- Truncate per output rule.

### 8. Provenance & ownership

Applicable to: Node, Python.

- **npm provenance** (when `package.json` has a `name`):
  - `curl <hardening> https://registry.npmjs.org/{name}` →
    - Read `maintainers[]` logins. If no maintainer overlaps the
      GitHub owner OR any of the **top 30** contributors:
      `warn` "publisher does not visibly overlap repo contributors —
      verify the org's publishing account is legitimate."
    - If `time.modified` is within last 7 days AND a previous version
      exists: `warn` "recent unscheduled publish — verify changelog."
- **PyPI provenance**: same maintainer-overlap check.
- Max severity = `warn`.

## Verdict logic

The verdict is computed from the per-check results.

**High-confidence warns** (each one alone forces 🔴):
- Check 6 — suspicious-pattern regex hit inside an install hook
  (deterministic content match).
- Check 7 — forbidden executable installer (`.exe`, `.msi`, `.deb`,
  `.rpm`, `.pkg`, `.dmg`) **outside** a recognized build-output path.
- Check 3 — ≥ 50% of combined stargazer sample are empty profiles.

These are the only signals pre-validated to be specific enough to
warrant 🔴 before the calibration exercise (§Calibration). Threshold
checks (account age, stars/day, contributor counts, publisher
overlap) cap at 🟡 contribution until calibrated.

**Verdict rules:**

| State | Trigger |
|---|---|
| 🔴 Several things look concerning | Any high-confidence warn fires |
| ⚪ Couldn't gather enough signal | ≥ 3 applicable checks returned `skip` |
| 🟡 A few things look unusual | 1 or more `warn` results, no high-confidence warn |
| 🟢 Nothing obviously wrong | 0 `warn` results |

The verdict line **must** include the soft caveat clause as printed.
A renderer that strips the caveat ("the repo is 🟢") misuses the
output and is the failure mode the wording is designed to prevent.

**Quick-check tier verdicts:** the quick tier runs only 3 checks and
cannot produce a high-confidence warn (the regex deep-scan and tree
walk are full-audit only). Quick-check therefore emits only 🟢 or 🟡.
A 🟡 quick-check always recommends running the full audit, where 🔴
becomes possible.

## Output format

### Full-audit output (slash command)

```
🟡 A few things look unusual — worth a closer look

Repo: owner/repo  (https://github.com/owner/repo)
Ecosystem: Node (package.json), Python (pyproject.toml)
Checks applicable: 1, 2, 3, 4, 5, 6, 7, 8

Findings
  ✓ Repo age: 2 years 4 months
  ⚠ Author account created 12 days ago, 1 other repo, 0 followers
       https://github.com/{owner}
  ⚠ 35% of sampled stargazers are empty profiles (recent-page rate 2.4×)
       Examples: https://github.com/abc123, https://github.com/xyz789
  ⚠ postinstall script not on benign allowlist:
       "node download-bin.js && chmod +x ./bin/runner"
       (file: package.json, line 23)
  ⚠ Contains 1 binary: bin/runner.exe (3.2 MB)
       (in conventional build output for this project)
  ⚠ npm package "foo" published by user "alice99" — no visible overlap
    with repo contributors
       https://www.npmjs.com/~alice99
  — Star history (eyeball): https://star-history.com/#owner/repo&Date

Summary
The author account is brand new, sampled stargazers show recent-injection
patterns, the postinstall hook executes a downloaded binary, and the npm
publisher does not visibly map to the repo contributors. Multiple things
worth investigating before installing.

Known limitations of this scan: did not inspect transitive dependencies;
did not execute or sandbox anything; thresholds are unvalidated heuristics.

I'd suggest looking at the postinstall script finding before deciding —
want me to explain why that one's a concern?
```

The closing line is **directive and verdict-aware**. The skill
selects the most concerning warn (using the same high-confidence
priority as §Verdict logic, then by check order) and surfaces it
as the suggested drill-in. Per-verdict wording:

- 🟢 → "Looks fine to install if you trust the source. Want me to
  go ahead and install it?"
- 🟡 → "I'd suggest looking at [most-concerning finding] before
  deciding — want me to explain why that one's a concern?"
- 🔴 → "I don't recommend installing this without expert review.
  Want me to explain what's concerning, or help you find an
  alternative?"
- ⚪ → "I couldn't get enough information to assess this repo. Want
  me to retry, or look for alternatives?"

Symbol key: `✓` pass, `⚠` warn, `—` info, `·` skipped.

### Quick-check output (auto-trigger)

Quick-check emits the verdict line inline so it travels with the
result. Quick-check tier produces only 🟢 or 🟡 (see §Verdict logic).

Clean (🟢):
```
[scan-repo 🟢 nothing obviously wrong (3 quick checks) — proceed if
 you trust the source. For full audit run /scan-repo <url>]
```

With warning(s) (🟡):
```
[scan-repo 🟡 a few things look unusual — author account 12 days old,
 only 1 other repo. Worth running /scan-repo <url> for the full audit
 (~30s) before installing.]
```

Already scanned (quick) this conversation:
```
(scan-repo already ran a quick check on github.com/foo/bar earlier in
 this conversation — verdict was [🟢|🟡]. For full audit run
 /scan-repo <url>)
```

Already scanned (full) this conversation:
```
(scan-repo already ran a full audit on github.com/foo/bar earlier in
 this conversation — verdict was [🟢|🟡|🔴|⚪]. See prior message for
 findings.)
```

## Edge cases & error handling

| Case | Behavior |
|---|---|
| Repo 404 / private | Abort with one-line message. |
| `gh` not installed | Abort with install link. |
| `gh` unauthenticated | Try anonymous (60/hr); warn user about reduced detection. |
| Rate limit hit mid-run | Report partial findings; skipped checks marked clearly with reason. |
| Repo with 0 stars | Most heuristics trivially pass; reflected in findings list. |
| URL is a path inside a repo (e.g. `/blob/main/...`) | Normalize to `owner/repo`, capture branch if present. |
| URL is a github.io / pages URL | Out of scope; tell user to provide source repo URL. |
| Multiple URLs in one slash invocation | v1: take first only, note ignored URLs. |
| `/scan-repo` with no arg | Print usage, no skill invocation. |
| `curl` exceeds size/time limit | Treat as missing; emit `skip` with note "fetch exceeded limit (possible DoS — investigate manually)". |
| Network/proxy blocks GitHub | Abort with diagnostic; suggest user check `gh auth status` and connectivity. |

## Self-test

`--self-test` flag runs the full playbook against a randomly chosen URL
from `docs/superpowers/specs/calibration/known-good.txt` and confirms
each check returns *some* result. Catches regressions in GitHub API
responses or `gh` CLI behavior. Random selection means the self-test
target stays current as the calibration list evolves.

## Calibration

Calibration is a **v1.1 hard requirement** — but only with teeth.

### Forcing function (script + pre-commit hook)

Ship `tools/scan-repo-calibration-check.sh`:

- Reads `docs/superpowers/specs/calibration/known-good.txt`.
- Runs `scan-repo` (full audit) against each URL in the list.
- Counts `warn` results per repo.
- Exits non-zero if **3 or more** known-good repos accumulate
  unjustified `warn` results (definition of "justified" maintained
  in `calibration/justified-warns.md`).

Wire to a pre-commit hook in the repo. Modifications to SKILL.md cannot
be committed without the script passing. This converts "must run
calibration" from strongly-worded comment into actual block.

### Asymmetric forcing function — known-bad gap

`known-bad.txt` is intentionally empty until sourced from advisories
(see file header for sourcing protocol). **Until populated, the
forcing function detects only false positives, not false negatives.**

This is a known asymmetry, named explicitly so future maintainers do
not assume calibration covers both directions. Adding curated
known-bad URLs is a v1.1 prerequisite alongside the script.

### Calibration output

Per-check false-positive and false-negative rates documented in
`docs/superpowers/specs/calibration/results-{date}.md`. Results inform
whether v2 can responsibly emit verdict labels.

## Future work (out of scope for v1)

- Verdict labels (only after calibration validates per-check error
  rates).
- Hosts beyond github.com.
- Recursive transitive-dep scan.
- Inspection of Python build-backend hooks, `conftest.py`, `.pth`.
- Optional sandboxed deep audit behind explicit user opt-in.
- Cross-session cache of author/stargazer reputation lookups (v1
  memoization is per-conversation only).
- Integration with external services (StarGuard, Astronomer,
  Socket.dev).
- Signed/hashed shareable verdict format (chain of custody).
- Re-scan & diff: detect changes since last audit.
- Multi-URL comparison.
- Curated allowlist of known-legitimate npm/PyPI publishers that don't
  overlap GitHub org contributors.
- Use of `gh search code` to grep server-side instead of fetching files.
- Members/collaborators API for organizations the user has access to
  (improves provenance accuracy).
- Localization beyond English.
- Defined skill-side mechanism for "look for established alternatives"
  (v1 punts this to general conversational follow-up — Claude searches /
  recommends from general knowledge when the directive closing offers it
  on a 🔴 or ⚪ verdict).
- Telemetry / measurement framework for "is this skill helping users?"

## Open questions

1. The `github.com/{o}/{r}/network/dependents` page is HTML, not API.
   Acceptable to scrape for v2's transitive-dep work?
2. Stargazer dual-page sampling (~40 calls) acceptable, or fall back
   to single page on low quota?
3. Privacy: every stargazer-sample lookup goes against the user's
   `gh` token. Worth a one-line privacy note in the report?
4. For repos with no recognized ecosystem (raw shell scripts, raw
   Lua, raw config), do we emit a special-case "we can do less here"
   note in the report so the absence of certain checks is explicit?
5. Should the intent-token list be configurable per-user (settings
   file), or hard-coded in SKILL.md and require editing the playbook
   to adjust?
