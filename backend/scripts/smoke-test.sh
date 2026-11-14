#!/usr/bin/env bash
# Smoke test for Part 3 backend. Run while the server is up:
#   bash backend/scripts/smoke-test.sh [base_url]
set -euo pipefail

BASE="${1:-http://localhost:8787}"
PASS=0
FAIL=0

check() {
  local label="$1" expected_status="$2" method="$3" url="$4"
  shift 4
  local status body
  body=$(curl -s -o /dev/null -w '%{http_code}' -X "$method" "$url" "$@" 2>/dev/null) || true
  if [ "$body" = "$expected_status" ]; then
    echo "  PASS  $label (HTTP $body)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label (expected $expected_status, got $body)"
    FAIL=$((FAIL + 1))
  fi
}

echo "Smoke testing $BASE"
echo ""

check "GET /health returns 200" \
  200 GET "$BASE/health"

check "POST /walk-plan with fixture origin returns 200" \
  200 POST "$BASE/walk-plan" \
  -H "Content-Type: application/json" \
  -d '{"originLatE6":53546000,"originLonE6":-113493800,"maxWalkS":120}'

check "POST /walk-plan with bad JSON returns 400" \
  400 POST "$BASE/walk-plan" \
  -H "Content-Type: application/json" \
  -d 'not json'

check "POST /walk-plan with out-of-range lat returns 400" \
  400 POST "$BASE/walk-plan" \
  -H "Content-Type: application/json" \
  -d '{"originLatE6":91000000,"originLonE6":0,"maxWalkS":120}'

check "POST /walk-plan with distant origin returns 404" \
  404 POST "$BASE/walk-plan" \
  -H "Content-Type: application/json" \
  -d '{"originLatE6":48000000,"originLonE6":2000000,"maxWalkS":120}'

check "OPTIONS preflight returns 204" \
  204 OPTIONS "$BASE/walk-plan"

check "GET unknown path returns 404" \
  404 GET "$BASE/unknown"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
