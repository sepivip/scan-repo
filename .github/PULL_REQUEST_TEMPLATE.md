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
