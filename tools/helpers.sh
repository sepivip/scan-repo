#!/usr/bin/env bash
# scan-repo helpers — pure bash, no external deps beyond coreutils.
# Sourced by SKILL.md and by tests/test-helpers.sh.
# Target platforms: Linux (GNU coreutils), macOS (BSD coreutils),
# Windows (git-bash, msys2).

# extract_url <input>
# Echoes "owner/repo[@branch]" or empty string if no github URL found.
# Recognizes:
#   https://github.com/owner/repo
#   https://github.com/owner/repo.git
#   https://github.com/owner/repo/tree/<branch>
#   https://github.com/owner/repo/blob/<branch>/...
#   gh repo clone owner/repo
#   git clone https://github.com/owner/repo
extract_url() {
    local input="$1"
    local owner="" repo="" branch=""

    if [[ "$input" =~ github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/blob/([A-Za-z0-9_./-]+) ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        branch="${BASH_REMATCH[3]%%/*}"
    elif [[ "$input" =~ github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(/tree/([A-Za-z0-9_./-]+))? ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        branch="${BASH_REMATCH[4]:-}"
    elif [[ "$input" =~ gh[[:space:]]+repo[[:space:]]+clone[[:space:]]+([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+) ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    fi

    [[ -z "$owner" || -z "$repo" ]] && return 0

    repo="${repo%.git}"

    if [[ -n "$branch" ]]; then
        printf '%s/%s@%s\n' "$owner" "$repo" "$branch"
    else
        printf '%s/%s\n' "$owner" "$repo"
    fi
}

# has_intent_token <input>
# Returns 0 (true) if any intent token is present as a word/phrase match.
has_intent_token() {
    local input="$1"
    if printf '%s' "$input" | grep -iqE '\b(should I|is it safe|safe to|can I trust|thoughts on)\b'; then
        return 0
    fi
    if printf '%s' "$input" | grep -iqE '\b(install|clone|try|test|use|run|recommend)\b'; then
        return 0
    fi
    return 1
}

# age_days <iso8601_date>
# Echoes the number of whole days between now and the given date.
# Portable: tries GNU date first, falls back to BSD date.
# On parse failure, echoes "0" and returns non-zero.
age_days() {
    local iso="$1"
    local now_secs then_secs
    now_secs=$(date -u +%s)
    if then_secs=$(date -u -d "$iso" +%s 2>/dev/null); then
        :
    elif then_secs=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null); then
        :
    elif then_secs=$(date -u -j -f "%Y-%m-%d" "${iso%%T*}" +%s 2>/dev/null); then
        :
    else
        echo "0"
        return 1
    fi
    echo $(( (now_secs - then_secs) / 86400 ))
}
