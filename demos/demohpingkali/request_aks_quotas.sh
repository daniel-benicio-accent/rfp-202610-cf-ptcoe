#!/usr/bin/env bash
# request_aks_quotas.sh
#
# Files one Azure quota increase request per quota needed to scale the AKS node
# pool of terraform/azure-ebc (the node VM family's vCPUs, total regional vCPUs,
# Standard public IPv4 addresses) to the target node count. Requests are only
# created when the current limit is below the required value, so existing
# quotas are never lowered. The Azure counterpart of request_gke_quotas.sh.
#
# Usage:
#   ./request_aks_quotas.sh                  # dry run (default)
#   DRY_RUN=false ./request_aks_quotas.sh    # submit requests
#   ./request_aks_quotas.sh status           # show limits and request status once
#   ./request_aks_quotas.sh watch            # refresh status every 60s
#
# Requirements: az (logged in), jq, column, and a role that may request quota
# on the subscription (Contributor, or Quota Request Operator). The script adds
# the az "quota" extension if missing, and registers the Microsoft.Quota
# resource provider right before the first request it submits.
set -euo pipefail

# Git Bash on Windows rewrites "/subscriptions/..." arguments into file paths.
export MSYS_NO_PATHCONV=1

# ---- Configuration (override via environment) --------------------------------
readonly SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"  # defaults to the active az subscription
readonly LOCATION="${LOCATION:-westeurope}"
readonly VM_SIZE="${VM_SIZE:-Standard_D2pds_v6}"
readonly TARGET_NODES="${TARGET_NODES:-20}"
readonly HEADROOM_PERCENT="${HEADROOM_PERCENT:-20}"
readonly EXTRA_VCPUS="${EXTRA_VCPUS:-0}"        # other VMs of the same family in the region
readonly EXTRA_IPS="${EXTRA_IPS:-4}"            # outbound load balancer IP, other public IPs
readonly DRY_RUN="${DRY_RUN:-true}"
readonly WATCH_INTERVAL_SECONDS="${WATCH_INTERVAL_SECONDS:-60}"

# ---- Constants ---------------------------------------------------------------
readonly NODES_WITH_HEADROOM=$(( (TARGET_NODES * (100 + HEADROOM_PERCENT) + 99) / 100 ))
readonly REGIONAL_VCPU_QUOTA="cores"
readonly VM_FAMILY_RESOURCE_TYPE="dedicated"

# The quota API names Standard public IPs as below (az quota create examples);
# the usage API reports the same quota under the IPv4-prefixed name, hence the
# separate lookup list, tried in order.
readonly PUBLIC_IP_QUOTA="${PUBLIC_IP_QUOTA:-StandardSkuPublicIpAddresses}"
readonly PUBLIC_IP_RESOURCE_TYPE="PublicIpAddresses"
readonly -a PUBLIC_IP_USAGE_NAMES=(IPv4StandardSkuPublicIpAddresses StandardSkuPublicIpAddresses PublicIPAddresses)

# Flattens `az quota request status list` output into one object per
# sub-request. Fields are read from .properties (the REST shape) or from the
# top level, so a flattened CLI output works too.
readonly JQ_REQUESTS='
  def value_of: if type == "object" then .value else . end;
  def requests:
    .[] | (.properties // .) as $p
    | ($p.value // [])[]
    | { submitted: ($p.requestSubmitTime // "-"),
        state: (.provisioningState // $p.provisioningState // "-"),
        quota: ((.name | value_of) // "-"),
        requested: ((.limit | value_of) // "-" | tostring),
        message: (.message // $p.message // "" | tostring | gsub("\\s+"; " ")) };'

SUB_ARGS=()
SUBSCRIPTION=""
COMPUTE_SCOPE=""
NETWORK_SCOPE=""
VM_FAMILY=""
VCPUS_PER_NODE=""
QUOTA_PROVIDER_STATE=""

# ---- Helpers -----------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

check_dependencies() {
  local cmd
  for cmd in az jq column; do
    command -v "${cmd}" >/dev/null 2>&1 || die "'${cmd}' is required but not installed."
  done
  if ! az extension show --name quota --output none >/dev/null 2>&1; then
    log "Adding the az 'quota' extension..."
    az extension add --name quota --only-show-errors --output none
  fi
}

resolve_context() {
  local account subscription_name

  if [[ -n "${SUBSCRIPTION_ID}" ]]; then
    SUB_ARGS=(--subscription "${SUBSCRIPTION_ID}")
  fi
  account="$(az account show "${SUB_ARGS[@]}" --output json)" \
    || die "az is not logged in, or cannot see subscription '${SUBSCRIPTION_ID}'. Run: az login"
  IFS=$'\t' read -r SUBSCRIPTION subscription_name < <(jq -r '[.id, .name] | @tsv' <<<"${account}")

  SUB_ARGS=(--subscription "${SUBSCRIPTION}")
  COMPUTE_SCOPE="/subscriptions/${SUBSCRIPTION}/providers/Microsoft.Compute/locations/${LOCATION}"
  NETWORK_SCOPE="/subscriptions/${SUBSCRIPTION}/providers/Microsoft.Network/locations/${LOCATION}"
  log "Subscription: ${subscription_name} (${SUBSCRIPTION}), location: ${LOCATION}"
}

# Sets VM_FAMILY (the quota name, e.g. StandardDpdsv6Family) and VCPUS_PER_NODE
# from the SKU catalogue. A restricted size is an availability block, not a
# quota: no increase lifts it, so it is only reported.
resolve_vm_sku() {
  local sku restrictions

  log "Looking up ${VM_SIZE} in ${LOCATION} (takes ~30s)..."
  sku="$(az vm list-skus "${SUB_ARGS[@]}" --location "${LOCATION}" --size "${VM_SIZE}" \
           --resource-type virtualMachines --all --output json \
         | jq -c --arg s "${VM_SIZE}" 'first(.[] | select(.name == $s)) // empty')"
  [[ -n "${sku}" ]] || die "VM size ${VM_SIZE} is not offered in ${LOCATION}."

  VM_FAMILY="$(jq -r '.family' <<<"${sku}")"
  VCPUS_PER_NODE="$(jq -r 'first(.capabilities[] | select(.name == "vCPUs") | .value)' <<<"${sku}")"
  restrictions="$(jq -r '[.restrictions[]? | "\(.reasonCode) (\(.type): \(.values // [] | join(",")))"]
                         | join("; ")' <<<"${sku}")"

  log "${VM_SIZE}: family ${VM_FAMILY}, ${VCPUS_PER_NODE} vCPUs per node"
  if [[ -n "${restrictions}" ]]; then
    log "WARNING: ${VM_SIZE} is restricted for this subscription: ${restrictions}." \
        "A quota increase does not lift this; use another size or region, or open a support request."
  fi
}

# Prints a usage entry's field ("currentValue" or "limit") for the first of the
# given quota names found (case-insensitive), or "unknown".
usage_field() {
  local json="$1" field="$2"
  shift 2
  jq -r --arg f "${field}" '
    first(($ARGS.positional[] | ascii_downcase) as $n
          | .[] | select((.name.value | ascii_downcase) == $n) | .[$f] | tostring)
    // "unknown"' --args "$@" <<<"${json}"
}

# Prints one tab-separated row per quota: scope, quota name, resource type
# ("-" when the request does not need one), usage, limit, required.
quota_rows() {
  local compute_usage network_usage
  local family_usage family_limit cores_usage cores_limit ip_usage ip_limit
  local other_vcpus=0
  local -r required_vcpus=$(( NODES_WITH_HEADROOM * VCPUS_PER_NODE + EXTRA_VCPUS ))
  local -r required_ips=$(( NODES_WITH_HEADROOM + EXTRA_IPS ))

  compute_usage="$(az vm list-usage "${SUB_ARGS[@]}" --location "${LOCATION}" --output json)"
  network_usage="$(az network list-usages "${SUB_ARGS[@]}" --location "${LOCATION}" --output json)"

  family_usage="$(usage_field "${compute_usage}" currentValue "${VM_FAMILY}")"
  family_limit="$(usage_field "${compute_usage}" limit "${VM_FAMILY}")"
  cores_usage="$(usage_field "${compute_usage}" currentValue "${REGIONAL_VCPU_QUOTA}")"
  cores_limit="$(usage_field "${compute_usage}" limit "${REGIONAL_VCPU_QUOTA}")"
  ip_usage="$(usage_field "${network_usage}" currentValue "${PUBLIC_IP_USAGE_NAMES[@]}")"
  ip_limit="$(usage_field "${network_usage}" limit "${PUBLIC_IP_USAGE_NAMES[@]}")"

  # The regional total also has to cover every other family running there.
  if [[ "${cores_usage}" =~ ^[0-9]+$ && "${family_usage}" =~ ^[0-9]+$ ]]; then
    other_vcpus=$(( cores_usage - family_usage ))
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${COMPUTE_SCOPE}" "${VM_FAMILY}" "${VM_FAMILY_RESOURCE_TYPE}" \
      "${family_usage}" "${family_limit}" "${required_vcpus}" \
    "${COMPUTE_SCOPE}" "${REGIONAL_VCPU_QUOTA}" "-" \
      "${cores_usage}" "${cores_limit}" "$(( other_vcpus + required_vcpus ))" \
    "${NETWORK_SCOPE}" "${PUBLIC_IP_QUOTA}" "${PUBLIC_IP_RESOURCE_TYPE}" \
      "${ip_usage}" "${ip_limit}" "${required_ips}"
}

# tr: the Windows az, called from WSL, ends tsv lines with \r.
quota_provider_state() {
  az provider show "${SUB_ARGS[@]}" --namespace Microsoft.Quota \
    --query registrationState --output tsv 2>/dev/null | tr -d '\r' || echo "Unknown"
}

# Quota requests go through the Microsoft.Quota provider, which a subscription
# may not have registered yet. Only called right before a real submission.
ensure_quota_provider() {
  [[ "${QUOTA_PROVIDER_STATE}" == "Registered" ]] && return 0
  log "Registering the Microsoft.Quota resource provider (one-off, a minute or two)..."
  az provider register "${SUB_ARGS[@]}" --namespace Microsoft.Quota --wait --output none
  QUOTA_PROVIDER_STATE="Registered"
}

# Prints the quota requests on a scope as JSON, or [] when there are none or
# the provider is not registered yet.
list_requests() {
  if [[ "${QUOTA_PROVIDER_STATE}" != "Registered" ]]; then
    echo '[]'
    return 0
  fi
  az quota request status list --scope "$1" --only-show-errors --output json 2>/dev/null || echo '[]'
}

pending_request() {
  list_requests "$1" | jq -e --arg q "$2" "${JQ_REQUESTS}"'
    requests
    | select((.quota | ascii_downcase) == ($q | ascii_downcase))
    | select(.state | test("^(Accepted|InProgress)$"; "i"))' >/dev/null
}

request_increase() {
  local scope="$1" quota="$2" resource_type="$3" usage="$4" limit="$5" required="$6"
  local -a type_args=()

  log "${quota}: usage = ${usage}, limit = ${limit}, required = ${required}"

  # Without a known limit the request could lower it; leave that to a human.
  if [[ ! "${limit}" =~ ^[0-9]+$ ]]; then
    log "Skipping ${quota}: current limit unknown. Check it in the portal (Quotas > My quotas)."
    return 1
  fi

  if (( limit >= required )); then
    log "Skipping ${quota}: current limit already satisfies the requirement."
    return 0
  fi

  if pending_request "${scope}" "${quota}"; then
    log "A request for ${quota} is already pending. Track it with: $0 status"
    return 0
  fi

  if [[ "${resource_type}" != "-" ]]; then
    type_args=(--resource-type "${resource_type}")
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY_RUN: would request ${quota} = ${required} (az quota create --resource-name ${quota}${type_args[*]:+ ${type_args[*]}} --limit-object value=${required})"
    return 0
  fi

  # errexit is suspended when this function runs inside "|| ...", so the
  # exit status must be checked explicitly.
  if ! ensure_quota_provider \
     || ! az quota create \
            --scope "${scope}" \
            --resource-name "${quota}" \
            "${type_args[@]}" \
            --limit-object value="${required}" \
            --no-wait \
            --only-show-errors \
            --output none; then
    log "FAILED to submit ${quota}. If Azure asks for a support request, file it in the portal (Quotas > My quotas)."
    return 1
  fi

  log "Submitted ${quota} = ${required}."
}

# ---- Commands ----------------------------------------------------------------
show_status() {
  local rows requests scope quota usage limit required state

  QUOTA_PROVIDER_STATE="$(quota_provider_state)"
  rows="$(quota_rows)"

  {
    printf 'QUOTA\tUSAGE\tLIMIT\tREQUIRED\tSTATE\n'
    while IFS=$'\t' read -r scope quota _ usage limit required; do
      if [[ ! "${limit}" =~ ^[0-9]+$ ]]; then
        state="unknown"
      elif (( limit >= required )); then
        state="ok"
      else
        state="below target"
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "${quota}" "${usage}" "${limit}" "${required}" "${state}"
    done <<<"${rows}"
  } | column -t -s $'\t'
  printf '\n'

  if [[ "${QUOTA_PROVIDER_STATE}" != "Registered" ]]; then
    log "No quota requests: Microsoft.Quota is ${QUOTA_PROVIDER_STATE} (the first submission registers it)."
    return 0
  fi

  # Newest first, the last 10 that touch one of the quotas above.
  requests="$(
    for scope in "${COMPUTE_SCOPE}" "${NETWORK_SCOPE}"; do
      list_requests "${scope}"
    done | jq -rs "${JQ_REQUESTS}"'
      ($ARGS.positional | map(ascii_downcase)) as $names
      | [ (add // []) | requests | select(.quota | ascii_downcase | IN($names[])) ]
      | sort_by(.submitted) | reverse | .[:10][]
      | [.submitted, .state, .quota, .requested, .message[0:100]]
      | @tsv' --args "${VM_FAMILY}" "${REGIONAL_VCPU_QUOTA}" "${PUBLIC_IP_QUOTA}"
  )"

  if [[ -z "${requests}" ]]; then
    log "No quota requests found for these quotas in ${LOCATION}."
    return 0
  fi
  { printf 'SUBMITTED\tSTATE\tQUOTA\tREQUESTED\tMESSAGE\n'; printf '%s\n' "${requests}"; } \
    | column -t -s $'\t'
}

watch_status() {
  while true; do
    clear
    log "Quotas in ${LOCATION} (refresh every ${WATCH_INTERVAL_SECONDS}s, Ctrl+C to stop)"
    show_status || log "Failed to fetch status, retrying..."
    sleep "${WATCH_INTERVAL_SECONDS}"
  done
}

submit_requests() {
  local failures=0
  local rows scope quota resource_type usage limit required

  log "Target: ${TARGET_NODES} nodes (${NODES_WITH_HEADROOM} with ${HEADROOM_PERCENT}% headroom) of ${VM_SIZE}, DRY_RUN=${DRY_RUN}"
  rows="$(quota_rows)"

  # stdin of each request comes from /dev/null, so az cannot eat the rows.
  while IFS=$'\t' read -r scope quota resource_type usage limit required; do
    request_increase "${scope}" "${quota}" "${resource_type}" "${usage}" "${limit}" "${required}" \
      </dev/null || failures=$((failures + 1))
  done <<<"${rows}"

  if [[ "${DRY_RUN}" != "true" ]]; then
    log "Current status:"
    show_status || true
  fi

  if (( failures > 0 )); then
    die "Finished with ${failures} unresolved item(s). Review the output above; re-running is safe."
  fi
  log "All requests processed."
}

main() {
  local command="${1:-submit}"

  case "${command}" in
    submit|status|watch) ;;
    *) die "Unknown command '${command}'. Use: submit | status | watch" ;;
  esac

  check_dependencies
  resolve_context
  resolve_vm_sku
  QUOTA_PROVIDER_STATE="$(quota_provider_state)"

  case "${command}" in
    submit) submit_requests ;;
    status) show_status ;;
    watch)  watch_status ;;
  esac
}

main "$@"
