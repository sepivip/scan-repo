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

## Ways to contribute

### Report a false positive

You ran scan-repo on a repo you know is legitimate and got a warn or
🟡 verdict that looks wrong.

→ Open an issue using the **false-positive** template.

### Report a missed attack

You found a malicious repo that scan-repo failed to flag.

→ Open an issue using the **missed-attack** template. These go into
`calibration/known-bad.txt` once triaged.

### Propose a new check

→ Open an issue using the **new-check** template. Requirements:

- One-line description of what it detects.
- Honest estimate of false-positive rate.
- Whether it qualifies as a *deterministic* (high-confidence) signal
  or a threshold heuristic.
- Proposed ecosystem applicability.

### Contribute a known-good URL

Add to `calibration/known-good.txt`.
Requirements:
- Multi-year history, multiple contributors, real downstream usage.
- A short comment explaining why it's a good test case.

### Contribute a known-bad URL

Add to `calibration/known-bad.txt`. Requirements:
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
   - Add to `calibration/justified-warns.md`
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

Required tools: `bash` 4+, `gh` (authenticated), and `curl`. No other runtime dependencies — JSON parsing is delegated to gh's built-in `--jq` filter.

## Pull request checklist

- [ ] Tests pass locally on your platform
- [ ] CI passes (runs on Linux, macOS, Windows)
- [ ] If you changed SKILL.md or helpers.sh, calibration passes (the
      pre-commit hook enforces this)
- [ ] You've read the design spec
- [ ] CHANGELOG.md updated with a one-line entry under "Unreleased"

## Code style

- Pure bash; no external deps beyond coreutils, `gh`, and `curl`. Use `gh api --jq` for any JSON parsing of GitHub responses.
- Cross-platform: test with GNU date (Linux) *and* BSD date (macOS).
- Short functions with a one-line comment describing purpose and return.
- Tests for every deterministic helper.

## License

By contributing, you agree your contributions will be licensed under
the MIT License (see LICENSE).
