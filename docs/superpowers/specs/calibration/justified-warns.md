# Justified warns on known-good repos

Format: one entry per known-good repo that has a *justified* warn under
the current SKILL.md. Calibration script (`tools/calibration-check.sh`)
reads this file to decide whether a warn on the known-good list counts
toward the failure threshold.

## Format

```
## owner/repo
- check: <check number>
- pattern: <one-line description of the warn output>
- justification: <why this is acceptable>
```

## Entries

(none yet — populated as calibration runs surface specific patterns)
