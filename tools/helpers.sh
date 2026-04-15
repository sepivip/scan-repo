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

# is_benign_install_hook <hook_content>
# Returns 0 if hook content exactly matches the known-benign allowlist.
is_benign_install_hook() {
    case "$1" in
        "node-gyp rebuild"|"prebuild-install"|"node-pre-gyp install"|"electron-rebuild"|"husky install"|"husky")
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# has_suspicious_pattern <hook_content>
# Returns 0 if any suspicious pattern matches.
has_suspicious_pattern() {
    local content="$1"
    if printf '%s' "$content" | grep -iqE '\b(curl|wget|node[[:space:]]+-e|python[[:space:]]+-c|eval|base64|atob)\b'; then
        return 0
    fi
    if printf '%s' "$content" | grep -qE '(^|[^0-9])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9]|$)'; then
        return 0
    fi
    if printf '%s' "$content" | grep -qiE '\.onion\b'; then
        return 0
    fi
    if printf '%s' "$content" | grep -qE '\|[[:space:]]*(sh|bash)\b'; then
        return 0
    fi
    return 1
}

# is_forbidden_executable <path>
# Returns 0 if the path ends with one of the forbidden installer extensions.
is_forbidden_executable() {
    local lower
    lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        *.exe|*.msi|*.deb|*.rpm|*.pkg|*.dmg) return 0 ;;
        *) return 1 ;;
    esac
}

# is_in_recognized_build_path <path> <ecosystem_markers_string>
is_in_recognized_build_path() {
    local path="$1" markers="$2"
    case "$path" in
        dist/*|build/*|out/*)
            printf '%s' "$markers" | grep -qE '(package\.json|webpack\.config|vite\.config|rollup\.config)' && return 0
            ;;
        target/*)
            printf '%s' "$markers" | grep -qE 'Cargo\.toml' && return 0
            ;;
        bin/*)
            printf '%s' "$markers" | grep -qE '(Makefile|build\.sh|go\.mod)' && return 0
            ;;
        _output/*)
            printf '%s' "$markers" | grep -qE '(Makefile|go\.mod)' && return 0
            ;;
    esac
    return 1
}

# is_empty_profile <created_at_iso> <followers> <public_repos>
# Returns 0 if the profile matches the empty pattern: zero followers AND
# zero public repos AND account age < 90 days. Uses portable age_days.
is_empty_profile() {
    local created_at="$1"
    local followers="$2"
    local repos="$3"
    [[ "$followers" -ne 0 ]] && return 1
    [[ "$repos" -ne 0 ]] && return 1
    local days
    days=$(age_days "$created_at") || return 1
    [[ "$days" -lt 90 ]]
}

# compute_verdict <high_confidence_warn_count> <total_warn_count> <skip_count>
# Echoes one of: green | yellow | red | white
compute_verdict() {
    local hc="$1" warns="$2" skips="$3"
    if [[ "$hc" -gt 0 ]]; then
        echo "red"
    elif [[ "$skips" -ge 3 ]]; then
        echo "white"
    elif [[ "$warns" -ge 1 ]]; then
        echo "yellow"
    else
        echo "green"
    fi
}

# verdict_label <verdict>
# Echoes the soft, caveated label string for the given verdict color.
verdict_label() {
    case "$1" in
        green)  echo "🟢 Nothing obviously wrong — proceed if you trust the source" ;;
        yellow) echo "🟡 A few things look unusual — worth a closer look" ;;
        red)    echo "🔴 Several things look concerning — recommend not installing without expert review" ;;
        white)  echo "⚪ Couldn't gather enough signal — cannot assess" ;;
        *)      echo "[scan-repo: unknown verdict state: $1]" ;;
    esac
}

# npm_script_hook <package_json_content> <hook_name>
# Extract the value of scripts.<hook_name> from package.json content.
# Returns empty string if the scripts object is missing or the hook is not set.
# Uses a two-step grep: isolate the "scripts": { ... } block first so we do not
# match hook names that might appear elsewhere (dependency names, etc).
# Assumption: simple string values, no embedded escaped quotes.
npm_script_hook() {
    local pkg="$1" hook_name="$2"
    local scripts
    scripts=$(printf '%s' "$pkg" | grep -oE '"scripts"[[:space:]]*:[[:space:]]*\{[^}]*\}' | head -1)
    [[ -z "$scripts" ]] && return 0
    printf '%s' "$scripts" \
        | grep -oE "\"$hook_name\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
        | head -1 \
        | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//'
}

# npm_maintainer_names <npm_registry_json>
# Extract all maintainer names from an npm registry response, sorted & unique.
# Primitive: isolates the maintainers array first, then grabs "name":"..." within.
npm_maintainer_names() {
    local json="$1"
    local arr
    arr=$(printf '%s' "$json" | grep -oE '"maintainers"[[:space:]]*:[[:space:]]*\[[^]]*\]' | head -1)
    [[ -z "$arr" ]] && return 0
    printf '%s' "$arr" \
        | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//' \
        | sort -u
}

# npm_modified_date <npm_registry_json>
# Extract time.modified (last-publish timestamp) from an npm registry response.
# Returns empty if not found.
npm_modified_date() {
    local json="$1"
    printf '%s' "$json" \
        | grep -oE '"modified"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 \
        | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//'
}
