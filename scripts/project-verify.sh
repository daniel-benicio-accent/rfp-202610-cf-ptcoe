#!/usr/bin/env bash
################################################################################
# project-verify.sh — check what a demo actually has, against what it should.
#
# Terraform tells you what it managed to create. It says nothing about what it
# never tried, what someone changed by hand, or whether the thing actually
# behaves. This asks the cloud and the running service directly.
#
# Read-only. It creates nothing and changes nothing.
#
# Usage:
#   ./scripts/project-verify.sh <demo-name>
#   ./scripts/project-verify.sh <demo-name> --quiet    # only failures
#
# Exit code is 0 when everything expected is present and behaving, 1 otherwise,
# so it can gate a rehearsal.
################################################################################

set -uo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; BLUE=$'\033[0;34m'
YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUIET=0
DEMO_ARG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet|-q) QUIET=1; shift ;;
    -h|--help)  sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "Unknown option '$1'." >&2; exit 2 ;;
    *)          DEMO_ARG="$1"; shift ;;
  esac
done

[ -n "$DEMO_ARG" ] || { echo "${BOLD}Usage:${NC} $0 <demo-name> [--quiet]"; exit 2; }

DEMO_DIR="$ROOT/demos/$DEMO_ARG"
[ -f "$DEMO_DIR/.envconfig" ] || { echo "${RED}x${NC} demos/$DEMO_ARG/.envconfig not found"; exit 2; }
# shellcheck disable=SC1091
. "$DEMO_DIR/.envconfig"

PASS=0; FAIL=0; SKIP=0

header() { echo; echo "${CYAN}${BOLD}$*${NC}"; }
pass()   { PASS=$((PASS+1)); [ "$QUIET" -eq 1 ] || echo "  ${GREEN}PASS${NC}  $1"; }
fail()   { FAIL=$((FAIL+1)); echo "  ${RED}FAIL${NC}  $1"; [ -n "${2:-}" ] && echo "        ${YELLOW}$2${NC}"; }
skip()   { SKIP=$((SKIP+1)); [ "$QUIET" -eq 1 ] || echo "  ${YELLOW}SKIP${NC}  $1  ${YELLOW}(${2:-not applicable})${NC}"; }

# check <label> <fix-hint> <command...>
check() {
  local label="$1" hint="$2"; shift 2
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label" "$hint"; fi
}

echo "${BOLD}Verifying demo:${NC} $DEMO_NAME"
echo "  project  $PROJECT_ID"
echo "  region   $REGION"
echo "  hostname $HOSTNAME_FQDN"

if ! command -v gcloud >/dev/null 2>&1; then
  echo
  echo "${RED}gcloud is not on PATH — cannot check the GCP side.${NC}"
  echo "See docs/prerequisites.md. On Windows, run this from WSL."
  exit 2
fi

# ── GCP resources ────────────────────────────────────────────────────────────
header "GCP resources"

check "project is reachable" \
      "gcloud auth login, and confirm the project ID" \
      gcloud projects describe "$PROJECT_ID"

ENABLED="$(gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' 2>/dev/null)"
for api in run firestore artifactregistry cloudbuild storage logging iam iamcredentials; do
  if printf '%s\n' "$ENABLED" | grep -q "^${api}.googleapis.com$"; then
    pass "API enabled: ${api}"
  else
    fail "API enabled: ${api}" "gcloud services enable ${api}.googleapis.com --project=$PROJECT_ID"
  fi
done

check "service account ${DEMO_NAME}-sa" \
      "tofu apply in terraform/gcp" \
      gcloud iam service-accounts describe "${DEMO_NAME}-sa@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID"

check "artifact registry repo ${DEMO_NAME}" \
      "tofu apply in terraform/gcp" \
      gcloud artifacts repositories describe "$DEMO_NAME" --project="$PROJECT_ID" --location="$REGION"

check "firestore database" \
      "tofu apply in terraform/gcp" \
      gcloud firestore databases describe --project="$PROJECT_ID"

check "cloud run service ${DEMO_NAME}" \
      "tofu apply in terraform/gcp" \
      gcloud run services describe "$DEMO_NAME" --project="$PROJECT_ID" --region="$REGION"

# ── Audit trail ──────────────────────────────────────────────────────────────
# Created outside Terraform on purpose, so it survives teardown. That also
# means nothing creates it for you: this is the step people miss.
header "Audit trail"

if gcloud storage buckets describe "gs://${AUDIT_BUCKET}" --project="$PROJECT_ID" >/dev/null 2>&1; then
  pass "audit bucket gs://${AUDIT_BUCKET}"
  BUCKET_OK=1
else
  fail "audit bucket gs://${AUDIT_BUCKET}" \
       "Deliberately outside Terraform so it survives destroy. Create it with:
         gcloud storage buckets create gs://${AUDIT_BUCKET} --project=${PROJECT_ID} \\
           --location=${REGION} --uniform-bucket-level-access --public-access-prevention"
  BUCKET_OK=0
fi

if gcloud logging sinks describe "${DEMO_NAME}-audit-sink" --project="$PROJECT_ID" >/dev/null 2>&1; then
  pass "log sink ${DEMO_NAME}-audit-sink"
elif [ "$BUCKET_OK" -eq 0 ]; then
  fail "log sink ${DEMO_NAME}-audit-sink" "Blocked by the missing bucket above. Create it, then re-run tofu apply."
else
  fail "log sink ${DEMO_NAME}-audit-sink" "tofu apply in terraform/gcp"
fi

# ── Live behaviour ───────────────────────────────────────────────────────────
header "Origin behaviour"

URL="$(gcloud run services describe "$DEMO_NAME" --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)' 2>/dev/null)"

if [ -z "$URL" ]; then
  skip "origin checks" "Cloud Run service not deployed"
else
  echo "  origin: $URL"

  code() { curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$@"; }

  # FR-7: a request that did not come through Cloudflare must be refused.
  C="$(code "$URL/")"
  if [ "$C" = "403" ]; then
    pass "direct request to / is refused (FR-7)"
  else
    fail "direct request to / is refused (FR-7)" \
         "Got HTTP $C, expected 403. Is EDGE_SECRET set on the service? Without it the app accepts direct traffic and the demo story does not hold."
  fi

  # Exempt so Cloud Run's startup probe, which bypasses Cloudflare, can pass.
  C="$(code "$URL/health")"
  [ "$C" = "200" ] && pass "/health answers without the edge header" \
                   || fail "/health answers without the edge header" "Got HTTP $C, expected 200. The container may be failing to start."

  SECV="$(gcloud run services describe "$DEMO_NAME" --project="$PROJECT_ID" --region="$REGION" --format=json 2>/dev/null \
          | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    for c in d["spec"]["template"]["spec"]["containers"]:
        for e in c.get("env",[]):
            if e["name"]=="EDGE_SECRET": print(e.get("value",""))
except Exception: pass' 2>/dev/null)"

  HDR="${EDGE_SECRET_HEADER:-X-Edge-Auth}"

  if [ -z "$SECV" ]; then
    fail "EDGE_SECRET present on the service" \
         "Not set, so the origin is accepting direct traffic. FR-7 is NOT satisfied."
  else
    pass "EDGE_SECRET present on the service (${#SECV} chars)"

    C="$(code -H "${HDR}: ${SECV}" "$URL/")"
    [ "$C" = "200" ] && pass "/ served when the edge header is present" \
                     || fail "/ served when the edge header is present" "Got HTTP $C, expected 200. Header name mismatch between the app and the zone module?"

    if curl -s --max-time 20 -H "${HDR}: ${SECV}" "$URL/api/stats" 2>/dev/null | grep -q '"arrivals"'; then
      pass "/api/stats reports arrivals (FR-9)"
    else
      fail "/api/stats reports arrivals (FR-9)" "Endpoint missing. Is src/app/ in sync with this demo's app/?"
    fi
  fi
fi

# ── Cloudflare edge ──────────────────────────────────────────────────────────
header "Cloudflare edge"

if [ -z "${ZONE_ID:-}" ] || [ "${ZONE_ID}" = "REPLACE_ME" ]; then
  skip "edge checks" "no zone configured in .envconfig"
elif [ -z "${HOSTNAME_FQDN:-}" ]; then
  skip "edge checks" "no hostname configured"
else
  if curl -s -o /dev/null --max-time 20 "https://${HOSTNAME_FQDN}/" 2>/dev/null; then
    RAY="$(curl -sI --max-time 20 "https://${HOSTNAME_FQDN}/" 2>/dev/null | grep -i '^cf-ray:' | head -1)"
    [ -n "$RAY" ] && pass "${HOSTNAME_FQDN} is served through Cloudflare" \
                  || fail "${HOSTNAME_FQDN} is served through Cloudflare" "No cf-ray header. Is the DNS record proxied (orange cloud)?"

    C="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://${HOSTNAME_FQDN}/")"
    case "$C" in
      200) pass "${HOSTNAME_FQDN} returns 200 end to end" ;;
      404) fail "${HOSTNAME_FQDN} returns 200 end to end" \
                "Got 404 — the classic Host header problem. Cloud Run routes by Host; the zone module's origin rule must rewrite it to the *.run.app name." ;;
      403) fail "${HOSTNAME_FQDN} returns 200 end to end" \
                "Got 403 — the edge is not injecting the secret the origin expects, or the header names differ." ;;
      *)   fail "${HOSTNAME_FQDN} returns 200 end to end" "Got HTTP $C." ;;
    esac
  else
    skip "edge checks" "https://${HOSTNAME_FQDN} did not resolve or connect — zone module probably not applied yet"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$FAIL" -eq 0 ]; then
  echo "${GREEN}${BOLD}${PASS} passed, ${SKIP} skipped, 0 failed.${NC}"
  exit 0
fi
echo "${RED}${BOLD}${FAIL} failed${NC}, ${PASS} passed, ${SKIP} skipped."
exit 1
