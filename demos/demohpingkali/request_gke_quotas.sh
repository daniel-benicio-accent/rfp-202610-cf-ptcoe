#!/usr/bin/env bash
# request_gke_quotas.sh
#
# Files one isolated Cloud Quotas increase request per Compute Engine quota
# needed to scale a GKE node pool (C4A nodes, external IPs, Hyperdisk Balanced
# boot disks) to the target node count. Requests are only created when the
# current limit is below the required value, so existing quotas are never lowered.
#
# Usage:
#   ./request_gke_quotas.sh                  # dry run (default)
#   DRY_RUN=false ./request_gke_quotas.sh    # submit requests
#   REFRESH=true ./request_gke_quotas.sh     # ignore cached quota catalog
#   ./request_gke_quotas.sh status           # show request status once
#   ./request_gke_quotas.sh watch            # refresh status every 60s
#
# Requirements: gcloud (with beta component), jq, roles/cloudquotas.admin.
set -euo pipefail

# ---- Configuration (override via environment) --------------------------------
readonly PROJECT_ID="${PROJECT_ID:-rfp-202610-demohpingkali}"
readonly REGION="${REGION:-us-east1}"
readonly VM_FAMILY="${VM_FAMILY:-C4A}"
readonly NODE_NAME_PREFIX="${NODE_NAME_PREFIX:-gke-demohpingkali}"
readonly PREFERENCE_PREFIX="${PREFERENCE_PREFIX:-demohpingkali}"
readonly TARGET_NODES="${TARGET_NODES:-20}"
readonly VCPUS_PER_NODE="${VCPUS_PER_NODE:-2}"
readonly BOOT_DISK_GB="${BOOT_DISK_GB:-30}"
readonly HEADROOM_PERCENT="${HEADROOM_PERCENT:-20}"
readonly EXTRA_IPS="${EXTRA_IPS:-8}"            # load balancers, NAT, bastion, etc.
readonly EXTRA_DISK_GB="${EXTRA_DISK_GB:-300}"  # PVCs and node upgrade surge
readonly CONTACT_EMAIL="${CONTACT_EMAIL:-}"     # defaults to the active gcloud account
readonly DRY_RUN="${DRY_RUN:-true}"
readonly REFRESH="${REFRESH:-false}"
readonly WATCH_INTERVAL_SECONDS="${WATCH_INTERVAL_SECONDS:-60}"

# ---- Constants ---------------------------------------------------------------
readonly SERVICE="compute.googleapis.com"
readonly CATALOG_CACHE="${CATALOG_CACHE:-/tmp/quota-catalog-${PROJECT_ID}.json}"
readonly CACHE_TTL_SECONDS=900
readonly NODES_WITH_HEADROOM=$(( (TARGET_NODES * (100 + HEADROOM_PERCENT) + 99) / 100 ))
readonly JUSTIFICATION="GKE cluster autoscaling to ${TARGET_NODES} ${VM_FAMILY} nodes with external IPs for a security demo lab"

readonly IP_QUOTA_ID="IN-USE-ADDRESSES-per-project-region"
readonly CPU_FAMILY_QUOTA_ID="CPUS-PER-VM-FAMILY-per-project-region"
readonly HDB_GB_QUOTA_ID="HDB-TOTAL-GB-per-project-region"
readonly HDB_IOPS_QUOTA_ID="HDB-TOTAL-IOPS-per-project-region"
readonly HDB_THROUGHPUT_QUOTA_ID="HDB-TOTAL-THROUGHPUT-per-project-region"

CONTACT_EMAIL_RESOLVED=""

# ---- Helpers -----------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

cleanup() { rm -f "${CATALOG_CACHE}.tmp"; }
trap cleanup EXIT

check_dependencies() {
  local cmd
  for cmd in gcloud jq; do
    command -v "${cmd}" >/dev/null 2>&1 || die "'${cmd}' is required but not installed."
  done
}

resolve_contact_email() {
  if [[ -n "${CONTACT_EMAIL}" ]]; then
    printf '%s\n' "${CONTACT_EMAIL}"
    return 0
  fi
  gcloud config get-value account 2>/dev/null || true
}

load_catalog() {
  if [[ "${REFRESH}" != "true" && -f "${CATALOG_CACHE}" ]] \
     && (( $(date +%s) - $(stat -c %Y "${CATALOG_CACHE}") < CACHE_TTL_SECONDS )); then
    log "Using cached quota catalog: ${CATALOG_CACHE}"
    return 0
  fi

  log "Loading quota catalog for ${SERVICE} in ${PROJECT_ID} (this takes ~1 min)..."
  gcloud beta quotas info list \
    --service="${SERVICE}" \
    --project="${PROJECT_ID}" \
    --format=json > "${CATALOG_CACHE}.tmp"
  mv "${CATALOG_CACHE}.tmp" "${CATALOG_CACHE}"
}

# Prints the first non-region dimension key of a quota (e.g. the VM family key).
extra_dimension_key() {
  jq -r --arg id "$1" '
    first(.[] | select(.quotaId == $id) | (.dimensions // [])[] | select(. != "region"))
    // empty' "${CATALOG_CACHE}"
}

# Prints the most specific limit that applies to the requested dimensions.
current_limit() {
  local quota_id="$1"
  local dims_json="$2"

  jq -r --arg id "${quota_id}" --argjson want "${dims_json}" '
    [ .[]
      | select(.quotaId == $id)
      | (.dimensionsInfos // [])[]
      | . as $info
      | ($info.dimensions // {}) as $d
      | select($d | to_entries | all(.value == $want[.key]))
      | {specificity: ($d | length), value: $info.details.value} ]
    | sort_by(-.specificity)
    | first
    | .value // "unknown"' "${CATALOG_CACHE}"
}

dims_to_flag() {
  jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")' <<<"$1"
}

preference_exists() {
  gcloud beta quotas preferences describe "$1" \
    --project="${PROJECT_ID}" >/dev/null 2>&1
}

# Prints "<iops> <throughput>" provisioned on an existing GKE node boot disk.
node_disk_performance() {
  gcloud compute disks list \
    --project="${PROJECT_ID}" \
    --filter="name~^${NODE_NAME_PREFIX} AND type~hyperdisk-balanced" \
    --format=json \
  | jq -r 'first(.[] | "\(.provisionedIops // 0) \(.provisionedThroughput // 0)") // "0 0"'
}

request_increase() {
  local preference_id="$1"
  local quota_id="$2"
  local preferred_value="$3"
  local dims_json="$4"
  local dims_flag limit
  local -a email_args=()

  dims_flag="$(dims_to_flag "${dims_json}")"
  limit="$(current_limit "${quota_id}" "${dims_json}")"
  log "${quota_id} [${dims_flag}]: current limit = ${limit}, required = ${preferred_value}"

  if [[ "${limit}" == "-1" ]]; then
    log "Skipping ${quota_id}: quota is unlimited."
    return 0
  fi

  if [[ "${limit}" =~ ^[0-9]+$ ]] && (( limit >= preferred_value )); then
    log "Skipping ${quota_id}: current limit already satisfies the requirement."
    return 0
  fi

  if preference_exists "${preference_id}"; then
    log "Preference '${preference_id}' already exists. Track it with: $0 status"
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY_RUN: would create preference '${preference_id}' with --dimensions=${dims_flag}"
    return 0
  fi

  if [[ -n "${CONTACT_EMAIL_RESOLVED}" ]]; then
    email_args=(--email="${CONTACT_EMAIL_RESOLVED}")
  fi

  # errexit is suspended when this function runs inside "|| ...", so the
  # exit status must be checked explicitly.
  if ! gcloud beta quotas preferences create \
      --preference-id="${preference_id}" \
      --project="${PROJECT_ID}" \
      --service="${SERVICE}" \
      --quota-id="${quota_id}" \
      --preferred-value="${preferred_value}" \
      --dimensions="${dims_flag}" \
      --justification="${JUSTIFICATION}" \
      "${email_args[@]}"; then
    log "FAILED to submit '${preference_id}'."
    return 1
  fi

  log "Submitted '${preference_id}'."
}

# ---- Commands ----------------------------------------------------------------
# The Cloud Quotas API rejects most list filters, so filtering happens client-side.
show_status() {
  local preferences_json

  preferences_json="$(gcloud beta quotas preferences list \
    --project="${PROJECT_ID}" \
    --format=json)"

  jq -r --arg prefix "${PREFERENCE_PREFIX}-" '
    ["PREFERENCE", "QUOTA_ID", "DIMENSIONS", "REQUESTED", "GRANTED", "PENDING"],
    ( .[]
      | (.name | split("/") | last) as $id
      | select($id | startswith($prefix))
      | [ $id,
          .quotaId,
          ((.dimensions // {}) | to_entries | map("\(.key)=\(.value)") | join(",")),
          (.quotaConfig.preferredValue // "-"),
          (.quotaConfig.grantedValue // "-"),
          ((.reconciling // false) | tostring) ] )
    | @tsv' <<<"${preferences_json}" \
  | column -t -s $'\t'
}

watch_status() {
  while true; do
    clear
    log "Quota requests for ${PROJECT_ID} (refresh every ${WATCH_INTERVAL_SECONDS}s, Ctrl+C to stop)"
    show_status || log "Failed to fetch status, retrying..."
    sleep "${WATCH_INTERVAL_SECONDS}"
  done
}

submit_requests() {
  local failures=0
  local region_dims family_key family_dims disk_iops disk_throughput
  local -r required_ips=$(( NODES_WITH_HEADROOM + EXTRA_IPS ))
  local -r required_vcpus=$(( NODES_WITH_HEADROOM * VCPUS_PER_NODE ))
  local -r required_disk_gb=$(( NODES_WITH_HEADROOM * BOOT_DISK_GB + EXTRA_DISK_GB ))

  CONTACT_EMAIL_RESOLVED="$(resolve_contact_email)"
  log "Target: ${TARGET_NODES} nodes (${NODES_WITH_HEADROOM} with ${HEADROOM_PERCENT}% headroom), DRY_RUN=${DRY_RUN}"
  log "Contact email: ${CONTACT_EMAIL_RESOLVED:-<none>}"

  load_catalog
  region_dims="$(jq -nc --arg r "${REGION}" '{region: $r}')"

  # 1) Regional external IPv4 addresses
  request_increase "${PREFERENCE_PREFIX}-ip-${REGION}" \
    "${IP_QUOTA_ID}" "${required_ips}" "${region_dims}" \
    || failures=$((failures + 1))

  # 2) vCPUs for the node VM family
  family_key="$(extra_dimension_key "${CPU_FAMILY_QUOTA_ID}")"
  if [[ -z "${family_key}" ]]; then
    log "Could not detect the VM family dimension key for ${CPU_FAMILY_QUOTA_ID}."
    failures=$((failures + 1))
  else
    family_dims="$(jq -nc --arg r "${REGION}" --arg k "${family_key}" --arg f "${VM_FAMILY}" \
      '{region: $r} + {($k): $f}')"
    request_increase "${PREFERENCE_PREFIX}-${VM_FAMILY,,}-cpus-${REGION}" \
      "${CPU_FAMILY_QUOTA_ID}" "${required_vcpus}" "${family_dims}" \
      || failures=$((failures + 1))
  fi

  # 3) Hyperdisk Balanced capacity
  request_increase "${PREFERENCE_PREFIX}-hdb-gb-${REGION}" \
    "${HDB_GB_QUOTA_ID}" "${required_disk_gb}" "${region_dims}" \
    || failures=$((failures + 1))

  # 4) and 5) Hyperdisk Balanced IOPS and throughput, sized from a real node disk
  read -r disk_iops disk_throughput <<<"$(node_disk_performance)"
  if (( disk_iops == 0 || disk_throughput == 0 )); then
    log "Could not read provisioned IOPS/throughput from node disks. Skipping HDB IOPS/throughput."
    failures=$((failures + 1))
  else
    log "Node boot disk provisioned: ${disk_iops} IOPS, ${disk_throughput} MB/s"
    request_increase "${PREFERENCE_PREFIX}-hdb-iops-${REGION}" \
      "${HDB_IOPS_QUOTA_ID}" $(( disk_iops * NODES_WITH_HEADROOM )) "${region_dims}" \
      || failures=$((failures + 1))
    request_increase "${PREFERENCE_PREFIX}-hdb-throughput-${REGION}" \
      "${HDB_THROUGHPUT_QUOTA_ID}" $(( disk_throughput * NODES_WITH_HEADROOM )) "${region_dims}" \
      || failures=$((failures + 1))
  fi

  if [[ "${DRY_RUN}" != "true" ]]; then
    log "Current status:"
    show_status || true
  fi

  if (( failures > 0 )); then
    die "Finished with ${failures} unresolved item(s). Review the output above."
  fi
  log "All requests processed."
}

main() {
  check_dependencies
  case "${1:-submit}" in
    submit) submit_requests ;;
    status) show_status ;;
    watch)  watch_status ;;
    *)      die "Unknown command '${1}'. Use: submit | status | watch" ;;
  esac
}

main "$@"
