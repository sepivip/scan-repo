Run a full audit using the scan-repo skill on this URL: {{args}}

This is an explicit full-audit request — run all 8 checks, not the quick-check tier. Produce the complete findings report with the verdict line, findings list, plain-English summary, and directive closing question.

If no URL was provided, print:

    Usage: /scan-repo <github-url>
    Example: /scan-repo https://github.com/anthropics/claude-code

and do not invoke the skill.
