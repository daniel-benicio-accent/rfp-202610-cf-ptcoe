#!/usr/bin/env bash
################################################################################
# project-nuke.sh — destroy every cloud resource belonging to one demo.
#
# Takes the demo folder name, loads its .envconfig, inventories what exists,
# uploads that inventory to the audit bucket, then destroys in dependency
# order. Leaving a demo running costs money; this is how you stop it.
#
# Usage:
#   ./scripts/project-nuke.sh <demo-name>
#   ./scripts/project-nuke.sh <demo-name> --yes      # skip the typed confirmation
#   ./scripts/project-nuke.sh --list
#
# DESTROY ORDER — this is the point of the script.
#
#   1. Cloudflare feature modules   rulesets referencing the zone
#   2. Cloudflare zone module       DNS record, origin rule, transform rule
#   3. GCP module                   Cloud Run, Firestore, registry, IAM, sink
#
# That is the reverse of how bootstrap builds them. Destroying GCP first would
# leave a proxied hostname pointing at nothing — the zone would still answer,
# sending visitors to a dead origin — and would strand the Cloudflare state
# with references to resources that no longer exist. Each module has its own
# state, so nothing enforces this ordering for you.
################################################################################

set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; BLUE=$'\033[0;34m'
YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

info()    { echo "${BLUE}i ${NC} $*"; }
ok()      { echo "${GREEN}v ${NC} $*"; }
warn()    { echo "${YELLOW}! ${NC} $*"; }
die()     { echo "${RED}x ${NC} $*" >&2; exit 1; }
header()  { echo; echo "${CYAN}${BOLD}$*${NC}"; echo; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMOS="$ROOT/demos"

TF="tofu"
command -v tofu >/dev/null 2>&1 || TF="terraform"

list_demos() {
  local d found=0
  echo "${BOLD}Demos in demos/:${NC}"
  for d in "$DEMOS"/*/; do
    [ -f "${d}.envconfig" ] || continue
    # shellcheck disable=SC1091
    ( . "${d}.envconfig"; printf '  %s%s%s  project=%s  host=%s  created=%s\n' \
        "$CYAN" "$DEMO_NAME" "$NC" "$PROJECT_ID" "$HOSTNAME_FQDN" "$CREATED_AT" )
    found=1
  done
  [ "$found" -eq 1 ] || echo "  (none)"
}

ASSUME_YES=0
DEMO_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list)    list_demos; exit 0 ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        die "Unknown option '$1'. Try --help." ;;
    *)         DEMO_ARG="$1"; shift ;;
  esac
done

if [ -z "$DEMO_ARG" ]; then
  echo "${BOLD}Usage:${NC} $0 <demo-name> [--yes]"
  echo
  list_demos
  exit 1
fi

DEMO_DIR="$DEMOS/$DEMO_ARG"
[ -d "$DEMO_DIR" ] || die "No demo folder at demos/$DEMO_ARG"
[ -f "$DEMO_DIR/.envconfig" ] || die "demos/$DEMO_ARG/.envconfig not found. Is this a demo created by bootstrap-terraform.sh?"

# shellcheck disable=SC1091
. "$DEMO_DIR/.envconfig"

TFROOT="$DEMO_DIR/terraform"
[ -d "$TFROOT" ] || die "No terraform/ directory in demos/$DEMO_ARG"

# ── Confirm ──────────────────────────────────────────────────────────────────
header "Destruction summary"
cat <<SUMMARY
  Demo         : ${RED}${DEMO_NAME}${NC}
  GCP project  : ${RED}${PROJECT_ID}${NC}
  Region       : ${RED}${REGION}${NC}
  Hostname     : ${RED}${HOSTNAME_FQDN}${NC}
  Audit bucket : ${YELLOW}${AUDIT_BUCKET}${NC}  (survives, by design)
  Created      : ${YELLOW}${CREATED_AT}${NC} by ${CREATED_BY}
SUMMARY
echo
echo "${RED}${BOLD}This permanently destroys every cloud resource for this demo.${NC}"
echo

if [ "$ASSUME_YES" -eq 0 ]; then
  [ -t 0 ] || die "Not a terminal and --yes not given. Refusing to destroy unattended."
  read -rp "${BOLD}Type the demo name to confirm${NC} (${DEMO_NAME}): " TYPED || true
  [ "$TYPED" = "$DEMO_NAME" ] || { info "Confirmation did not match. Aborting."; exit 0; }
fi

# ── Inventory ────────────────────────────────────────────────────────────────
header "Inventorying cloud resources"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${TMPDIR:-/tmp}/${DEMO_NAME}-nuke-${STAMP}.log"

{
  echo "================================================================================"
  echo "Demo teardown log"
  echo "================================================================================"
  echo "Timestamp : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Demo      : ${DEMO_NAME}"
  echo "Project   : ${PROJECT_ID}"
  echo "Region    : ${REGION}"
  echo "Hostname  : ${HOSTNAME_FQDN}"
  echo "Nuked by  : $(whoami 2>/dev/null || echo unknown)"
  echo "Action    : DEMO_DESTROYED"
  echo "================================================================================"
  echo

  if command -v gcloud >/dev/null 2>&1; then
    for section in \
      "Cloud Run services|run services list --project=${PROJECT_ID} --region=${REGION}" \
      "Firestore databases|firestore databases list --project=${PROJECT_ID}" \
      "Artifact Registry|artifacts repositories list --project=${PROJECT_ID} --location=${REGION}" \
      "Service accounts|iam service-accounts list --project=${PROJECT_ID}" \
      "Log sinks|logging sinks list --project=${PROJECT_ID}" \
      "Project IAM policy|projects get-iam-policy ${PROJECT_ID}"
    do
      title="${section%%|*}"; cmd="${section#*|}"
      echo "---------------------------------------------"
      echo "$title"
      echo "---------------------------------------------"
      # shellcheck disable=SC2086
      gcloud $cmd 2>&1 || echo "(error listing $title)"
      echo
    done
  else
    echo "(gcloud not on PATH — inventory skipped)"
  fi
} | tee "$LOG"

ok "Inventory written to $LOG"

upload_log() {
  command -v gcloud >/dev/null 2>&1 || return 0
  local dest="gs://${AUDIT_BUCKET}/previous-labs/${DEMO_NAME}/nuke-${STAMP}.log"
  if gcloud storage cp "$LOG" "$dest" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    ok "Log uploaded to $dest"
  else
    warn "Could not upload the log. Local copy kept at $LOG"
  fi
}

header "Uploading pre-destruction log"
upload_log

# ── Destroy, in dependency order ─────────────────────────────────────────────
STATUS="SUCCESS"

destroy_module() {
  local dir="$1" label="$2"
  if [ ! -d "$dir" ]; then
    info "$label — no module, skipping"
    return 0
  fi
  if [ ! -f "$dir/terraform.tfstate" ] && [ ! -d "$dir/.terraform" ]; then
    info "$label — never applied, skipping"
    return 0
  fi

  header "Destroying: $label"
  ( cd "$dir" && "$TF" init -input=false >/dev/null && "$TF" destroy -auto-approve ) && {
    ok "$label destroyed"
    return 0
  }
  warn "$label reported errors. Some resources may still exist."
  STATUS="FAILED"
  return 0
}

# 1. Cloudflare feature modules
for d in "$TFROOT"/cloudflare/*/; do
  [ -d "$d" ] || continue
  case "$(basename "$d")" in
    zone) continue ;;
  esac
  destroy_module "${d%/}" "cloudflare/$(basename "$d")"
done

# 2. Cloudflare zone
destroy_module "$TFROOT/cloudflare/zone" "cloudflare/zone"

# 3. GCP origin
destroy_module "$TFROOT/gcp" "gcp"

# ── Record the outcome ───────────────────────────────────────────────────────
{
  echo
  echo "================================================================================"
  echo "Status       : ${STATUS}"
  echo "Completed at : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "================================================================================"
} >> "$LOG"

header "Uploading final log"
upload_log

# ── Local cleanup ────────────────────────────────────────────────────────────
if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
  echo
  read -rp "${BOLD}Remove the local folder demos/${DEMO_NAME}?${NC} (y/N): " RM || true
  case "${RM:-n}" in
    [Yy]*) rm -rf "$DEMO_DIR"; ok "demos/${DEMO_NAME} removed" ;;
    *)     info "demos/${DEMO_NAME} kept" ;;
  esac
fi

header "Teardown complete — ${STATUS}"

echo "  Audit log : gs://${AUDIT_BUCKET}/previous-labs/${DEMO_NAME}/nuke-${STAMP}.log"
echo "  Local log : ${LOG}"
echo

if [ "$STATUS" = "FAILED" ]; then
  echo "${RED}${BOLD}Check for survivors before you walk away:${NC}"
  echo "  gcloud run services list --project=${PROJECT_ID}"
  echo "  gcloud firestore databases list --project=${PROJECT_ID}"
  echo "  gcloud artifacts repositories list --project=${PROJECT_ID} --location=${REGION}"
  echo "  gcloud logging sinks list --project=${PROJECT_ID}"
  echo
  exit 1
fi
