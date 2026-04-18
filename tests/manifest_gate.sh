#!/usr/bin/env bash
# Smoke tests for the manifest deploy-gate logic in bin/vhack-deploy.
# No external framework — we strip the dispatch tail from the script,
# source the functions, and call them directly.

set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/bin/vhack-deploy"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

FAILURES=0
pass() { printf '  \033[0;32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[0;31mFAIL\033[0m %s\n' "$1"; FAILURES=$((FAILURES+1)); }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Keep everything up to the command dispatch at the bottom.
FUNCS_ONLY="${SCRATCH}/vhack-deploy-funcs.sh"
awk '/^COMMAND="\$\{1:-\}"/ { print "return 0"; exit } { print }' "$SCRIPT" > "$FUNCS_ONLY"
# shellcheck disable=SC1090
source "$FUNCS_ONLY"

# Isolate env for gate tests (unset any inherited keys/overrides)
unset ME_API_KEY SKIP_MANIFEST_GATE
ME_API_URL="https://example.test/api"

# ─── discover_manifests ──────────────────────────────────────────────────────

hdr "discover_manifests: finds <syllabus>/manifest.json"
mkdir -p "$SCRATCH/case1/python-class7-it"
echo '{}' > "$SCRATCH/case1/python-class7-it/manifest.json"
pushd "$SCRATCH/case1" >/dev/null
out=$(discover_manifests .)
popd >/dev/null
[[ "$out" == *"python-class7-it/manifest.json"* ]] \
    && pass "finds manifest at level 1" \
    || fail "did not find manifest: [$out]"

hdr "discover_manifests: ignores node_modules/ and vendor/"
mkdir -p "$SCRATCH/case2/node_modules/foo" "$SCRATCH/case2/vendor/contracts"
echo '{}' > "$SCRATCH/case2/node_modules/foo/manifest.json"
echo '{}' > "$SCRATCH/case2/vendor/contracts/manifest.json"
pushd "$SCRATCH/case2" >/dev/null
out=$(discover_manifests .)
popd >/dev/null
[[ "$out" != *"node_modules"* && "$out" != *"vendor/"* ]] \
    && pass "skips node_modules and vendor" \
    || fail "picked up ignored manifest: [$out]"

# ─── verify_manifests_for_prod ───────────────────────────────────────────────

hdr "verify_manifests_for_prod: no manifests => bypass"
mkdir -p "$SCRATCH/case3/empty"
pushd "$SCRATCH/case3/empty" >/dev/null
if verify_manifests_for_prod "dummy-site" >/dev/null 2>&1; then
    pass "non-pedagogy-platform deploys bypass gate"
else
    fail "gate blocked a non-pedagogy-platform deploy"
fi
popd >/dev/null

hdr "verify_manifests_for_prod: SKIP_MANIFEST_GATE=1 warns and passes"
mkdir -p "$SCRATCH/case4/python-class7-it"
echo '{"syllabus_id":"x","syllabus_version":"1.0"}' > "$SCRATCH/case4/python-class7-it/manifest.json"
pushd "$SCRATCH/case4" >/dev/null
output=$(SKIP_MANIFEST_GATE=1 verify_manifests_for_prod "python-prep" 2>&1)
popd >/dev/null
if [[ "$output" == *"SKIP_MANIFEST_GATE"* ]]; then
    pass "emergency override warns"
else
    fail "override did not warn. Output: $output"
fi

hdr "verify_manifests_for_prod: missing ME_API_KEY warns and passes"
pushd "$SCRATCH/case4" >/dev/null
ME_API_KEY="" output=$(ME_API_KEY="" verify_manifests_for_prod "python-prep" 2>&1)
popd >/dev/null
if [[ "$output" == *"ME_API_KEY not set"* ]]; then
    pass "missing API key warns (dev-friendly)"
else
    fail "missing API key did not warn. Output: $output"
fi

# ─── Done ────────────────────────────────────────────────────────────────────

if [[ "$FAILURES" -gt 0 ]]; then
    printf '\n\033[0;31m%d test(s) failed\033[0m\n' "$FAILURES"
    exit 1
fi
printf '\n\033[0;32mAll tests passed\033[0m\n'
