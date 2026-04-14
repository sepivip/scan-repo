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
