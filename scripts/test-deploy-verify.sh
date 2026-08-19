#!/usr/bin/env bash
# Tests the post-push verification helpers of deploy-site.sh.
#
# `gh` and `curl` are faked so every branch can be exercised, including the one
# that actually bit us: a Pages build wedged in "building" for two days while
# the script had already announced success.
#
# The fakes keep their state in FILES on purpose - both helpers call them inside
# $(...), i.e. in a subshell, where a shell-variable mutation would be lost.
#
#   bash scripts/test-deploy-verify.sh
set -uo pipefail

SCRIPT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-site.sh}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

FUNCS="$WORK/funcs.sh"
sed -n '/^wait_for_pages_build()/,/^}/p;/^live_site_matches()/,/^}/p' "$SCRIPT" > "$FUNCS"
grep -q "^wait_for_pages_build()" "$FUNCS" || { echo "wait_for_pages_build() missing" >&2; exit 1; }
grep -q "^live_site_matches()" "$FUNCS" || { echo "live_site_matches() missing" >&2; exit 1; }

STUBS='
REPO=fake/repo
gh() {
    case "$*" in
        *"-X POST"*pages/builds*)
            echo x >> "$WORK/posts" ;;
        *pages/builds*)
            head -1 "$WORK/statuses"
            sed -i "" 1d "$WORK/statuses" 2>/dev/null || true ;;
    esac
}
sleep() { :; }
'

run_build_case() {
    local name="$1"
    local statuses="$2"
    local expect_rc="$3"
    local expect_posts="$4"
    : > "$WORK/posts"
    printf '%s\n' $statuses > "$WORK/statuses"
    WORK="$WORK" FUNCS="$FUNCS" STUBS="$STUBS" \
        bash -c 'eval "$STUBS"; source "$FUNCS"; wait_for_pages_build 6' >/dev/null 2>&1
    local rc=$?
    local posts; posts=$(wc -l < "$WORK/posts" | tr -d ' ')
    if [[ "$rc" == "$expect_rc" && "$posts" == "$expect_posts" ]]; then
        printf '  PASS  %s\n' "$name"; PASS=$((PASS+1))
    else
        printf '  FAIL  %s\n        rc=%s (want %s)  retriggers=%s (want %s)\n' \
               "$name" "$rc" "$expect_rc" "$posts" "$expect_posts"; FAIL=$((FAIL+1))
    fi
}

run_build_case "a build that completes is accepted" \
               "building built built built built built built built" 0 0
run_build_case "a build wedged in 'building' is re-triggered, then completes" \
               "building building building building built built built built" 0 1
run_build_case "a build wedged for good fails loudly instead of claiming success" \
               "building building building building building building building building" 1 1
run_build_case "an errored build fails immediately, without re-triggering" \
               "building errored errored errored errored errored errored errored" 1 0

run_live_case() {
    local name="$1"
    local served_file="$2"
    local expect_rc="$3"
    printf 'NEW CONTENT\n' > "$WORK/local.html"
    SERVED="$served_file" FUNCS="$FUNCS" WORK="$WORK" bash -c '
        curl() { cat "$SERVED"; }
        sleep() { :; }
        source "$FUNCS"
        live_site_matches "https://example.invalid/" "$WORK/local.html" 3
    ' >/dev/null 2>&1
    local rc=$?
    if [[ "$rc" == "$expect_rc" ]]; then
        printf '  PASS  %s\n' "$name"; PASS=$((PASS+1))
    else
        printf '  FAIL  %s (rc=%s, want %s)\n' "$name" "$rc" "$expect_rc"; FAIL=$((FAIL+1))
    fi
}

printf 'NEW CONTENT\n' > "$WORK/fresh.html"
printf 'OLD CONTENT\n' > "$WORK/stale.html"
: > "$WORK/empty.html"

run_live_case "the live page matching what we pushed is accepted" "$WORK/fresh.html" 0
run_live_case "a stale live page is reported, not glossed over"   "$WORK/stale.html" 1
run_live_case "an empty response is not mistaken for a match"     "$WORK/empty.html" 1

echo ""
echo "passed $PASS, failed $FAIL"
[[ $FAIL -eq 0 ]]
