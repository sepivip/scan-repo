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

Requires `bash`, `gh` (authenticated), and `curl`. No other runtime dependencies.

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
