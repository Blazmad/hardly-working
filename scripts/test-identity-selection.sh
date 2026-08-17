#!/usr/bin/env bash
# Tests newest_developer_id() from build-dmg.sh.
#
# A second real Developer ID certificate cannot be created just to test the
# rollover case, so `security` is faked - but over REAL self-signed certificates,
# so the awk parsing, the openssl date extraction and the comparison all run for
# real. Pass a path to test a mutated copy: the suite must go red for any change
# to the comparison.
#
#   bash scripts/test-identity-selection.sh
set -uo pipefail

SCRIPT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build-dmg.sh}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

FUNC="$WORK/func.sh"
sed -n '/^newest_developer_id()/,/^}/p' "$SCRIPT" > "$FUNC"
[[ -s "$FUNC" ]] || { echo "newest_developer_id() not found in $SCRIPT" >&2; exit 1; }

# Self-signed cert valid for $1 days, tag $2. Echoes "<sha1> <pemfile>".
make_cert() {
    # One `local` per line: bash expands every argument of a single `local`
    # before assigning any of them, so a later $tag would still be unset.
    local days="$1"
    local tag="$2"
    local key="$WORK/$tag.key"
    local pem="$WORK/$tag.pem"
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$key" -out "$pem" \
        -days "$days" -subj "/CN=Developer ID Application: FAKE $tag (TEAM123456)" \
        >/dev/null 2>&1
    echo "$(/usr/bin/openssl x509 -in "$pem" -noout -fingerprint -sha1 \
            | sed 's/.*=//; s/://g') $pem"
}

FAKE_SECURITY='
security() {
    case "$*" in
        *find-certificate*)
            for e in $CERTS; do
                printf "SHA-256 hash: DEADBEEF\nSHA-1 hash: %s\n" "${e%%:*}"
                cat "${e#*:}"
            done ;;
        *find-identity*)
            i=0
            for h in $IDENTS; do
                i=$((i+1))
                printf "  %d) %s \"Developer ID Application: FAKE (TEAM123456)\"\n" "$i" "$h"
            done ;;
    esac
}'

# CERTS = "sha1:pem ..."  what find-certificate sees
# IDENTS = "sha1 ..."     what find-identity sees, i.e. those with a private key
run_case() {
    local name="$1"
    local certs="$2"
    local idents="$3"
    local expected="$4"
    local out
    out="$(CERTS="$certs" IDENTS="$idents" FUNC="$FUNC" FAKE="$FAKE_SECURITY" \
           bash -c 'eval "$FAKE"; source "$FUNC"; newest_developer_id' 2>/dev/null)"
    if [[ "$out" == "$expected" ]]; then
        printf '  PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n        expected [%s]\n        got      [%s]\n' \
               "$name" "$expected" "$out"
        FAIL=$((FAIL + 1))
    fi
}

# build-dmg.sh assigns this under `set -e`, where a non-zero return from the
# function would abort the build instead of falling back to no signature.
survives_set_e() {
    local name="$1"
    local certs="$2"
    local idents="$3"
    if CERTS="$certs" IDENTS="$idents" FUNC="$FUNC" FAKE="$FAKE_SECURITY" \
       bash -c 'set -euo pipefail; eval "$FAKE"; source "$FUNC"
                RESULT="${RESULT:-$(newest_developer_id)}"; echo "$RESULT"' \
       >/dev/null 2>&1; then
        printf '  PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s (aborted under set -e)\n' "$name"
        FAIL=$((FAIL + 1))
    fi
}

read -r SHORT_SHA SHORT_PEM <<< "$(make_cert 168 short)"
read -r LONG_SHA LONG_PEM <<< "$(make_cert 1825 long)"

# Without this guard, empty fixtures would make every comparison pass vacuously.
for v in SHORT_SHA SHORT_PEM LONG_SHA LONG_PEM; do
    [[ -n "${!v:-}" ]] || { echo "fixture broken: $v is empty" >&2; exit 1; }
done
[[ "$SHORT_SHA" != "$LONG_SHA" ]] || { echo "fixture broken: equal hashes" >&2; exit 1; }
[[ ${#SHORT_SHA} -eq 40 ]] || { echo "fixture broken: bad sha1" >&2; exit 1; }

run_case "two usable certificates: the longest-lived one wins" \
         "$SHORT_SHA:$SHORT_PEM $LONG_SHA:$LONG_PEM" "$SHORT_SHA $LONG_SHA" "$LONG_SHA"
run_case "listing order does not decide" \
         "$LONG_SHA:$LONG_PEM $SHORT_SHA:$SHORT_PEM" "$LONG_SHA $SHORT_SHA" "$LONG_SHA"
run_case "a certificate without its private key cannot sign and is skipped" \
         "$SHORT_SHA:$SHORT_PEM $LONG_SHA:$LONG_PEM" "$SHORT_SHA" "$SHORT_SHA"
run_case "a single certificate is chosen" \
         "$SHORT_SHA:$SHORT_PEM" "$SHORT_SHA" "$SHORT_SHA"
run_case "no identity yields nothing" "" "" ""

survives_set_e "no identity does not abort the build" "" ""
survives_set_e "an identity with no matching certificate does not abort the build" \
               "" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
survives_set_e "the normal case does not abort the build" \
               "$SHORT_SHA:$SHORT_PEM" "$SHORT_SHA"

echo ""
echo "passed $PASS, failed $FAIL"
[[ $FAIL -eq 0 ]]
