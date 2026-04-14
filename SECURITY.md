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

Please use GitHub's private advisory channel:
https://github.com/sepivip/scan-repo/security/advisories/new

Do NOT open a public issue for vulnerabilities in scan-repo itself.
Include:
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
