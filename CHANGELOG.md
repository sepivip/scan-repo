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
