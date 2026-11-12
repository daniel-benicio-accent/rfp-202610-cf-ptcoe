#!/usr/bin/env bash
################################################################################
# bootstrap-nginx.sh — wizard that creates a self-contained GKE + Istio demo.
#
# Renders a ready-to-apply Terraform tree into demos/<name>/ which, in a single
# apply, creates:
#
#   - a new GCP project, linked to your billing account
#   - a public GKE cluster: regional control plane, nodes in one zone, each
#     node with its own public IP, which its pods also egress from
#   - one node pool of Arm (Google Axion) nodes by default, that starts with a
#     single node and autoscales between --min-nodes and --max-nodes
#   - Istio (sidecar mode), STRICT mTLS in the app namespace, and an ingress
#     gateway published as a NodePort on every node
#   - nginx:alpine serving its default page, at most one pod per node, scaled
#     on CPU — more pods means more nodes
#
# The script only writes files. It never runs tofu; init, plan and apply are
# yours to run.
#
# Usage:
#   ./scripts/bootstrap-nginx.sh                          # interactive wizard
#   ./scripts/bootstrap-nginx.sh --non-interactive \
#       --name 2-demonginx --project my-new-project-id
#
# Options (each also prompted for when interactive):
#   --name <s>          demo folder                        (default demonginx)
#   --prefix <s>        resource prefix: starts with a letter, at most 24
#                       characters (default: the name minus leading digits)
#   --project <s>       ID of the GCP project to CREATE    (default rfp-202610-<prefix>)
#   --region <s>        GCP region                         (default us-east1)
#   --zone <s>          zone the nodes run in              (default <region>-b)
#   --machine-type <s>  node machine type, Arm or x86      (default c4a-standard-1)
#   --min-nodes <n>     fewest nodes, and fewest nginx pods (default 1)
#   --max-nodes <n>     most nodes, and most nginx pods    (default 20)
#   --org-id <s>        create the project in this organization
#   --folder-id <s>     ...or in this folder; never both
#   --non-interactive   take every answer from flags and defaults
#   -h | --help         this message
#
# The billing account never goes into a file: export TF_VAR_billing_account
# before applying.
#
# Tear the demo down with: ./scripts/project-nuke.sh <name>
################################################################################

set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; BLUE=$'\033[0;34m'
YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

info()    { echo "${BLUE}i ${NC} $*"; }
created() { echo "${GREEN}+ ${NC} $*"; }
skipped() { echo "${YELLOW}= ${NC} $*  ${YELLOW}(exists, left alone)${NC}"; }
warn()    { echo "${YELLOW}! ${NC} $*"; }
die()     { echo "${RED}x ${NC} $*" >&2; exit 1; }
header()  { echo; echo "${CYAN}${BOLD}$*${NC}"; echo; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$ROOT/src/terraform/_templates/gke-nginx"
CHART="$ROOT/src/charts/nginx-site"
DEMOS="$ROOT/demos"
TODAY="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Must match node_port_http in the template's variables.tf. Only used in the
# messages below; the module itself takes it from there.
NODE_PORT_HTTP=30080

NON_INTERACTIVE=0
NAME=""; PREFIX=""; PROJECT_ID=""; REGION=""; ZONE=""; MACHINE_TYPE=""
MIN_NODES=""; MAX_NODES=""; ORG_ID=""; FOLDER_ID=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)            NAME="${2:?}"; shift 2 ;;
    --prefix)          PREFIX="${2:?}"; shift 2 ;;
    --project)         PROJECT_ID="${2:?}"; shift 2 ;;
    --region)          REGION="${2:?}"; shift 2 ;;
    --zone)            ZONE="${2:?}"; shift 2 ;;
    --machine-type)    MACHINE_TYPE="${2:?}"; shift 2 ;;
    --min-nodes)       MIN_NODES="${2:?}"; shift 2 ;;
    --max-nodes)       MAX_NODES="${2:?}"; shift 2 ;;
    --org-id)          ORG_ID="${2:?}"; shift 2 ;;
    --folder-id)       FOLDER_ID="${2:?}"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    -h|--help)         sed -n '3,/^#\{10,\}$/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                 die "Unknown option '$1'. Try --help." ;;
  esac
done

[ -d "$TEMPLATES" ] || die "Templates not found at $TEMPLATES"
[ -d "$CHART" ]     || die "Chart not found at $CHART"
[ -t 0 ] || NON_INTERACTIVE=1

# ask VAR "Prompt" "default" — a flag already set wins over the default.
ask() {
  local var="$1" prompt="$2" def="$3" cur="${!1:-}" reply
  [ -n "$cur" ] && def="$cur"
  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    printf -v "$var" '%s' "$def"
    return
  fi
  read -rp "${BOLD}${prompt}${NC} [${def}]: " reply || true
  printf -v "$var" '%s' "${reply:-$def}"
}

# ── Prerequisites ────────────────────────────────────────────────────────────
# Nothing here is needed to render the files, so a missing tool is a warning.
header "Prerequisites"

if command -v tofu >/dev/null 2>&1; then
  info "OpenTofu: $(tofu --version 2>/dev/null | head -1)"
elif command -v terraform >/dev/null 2>&1; then
  info "Terraform: $(terraform --version 2>/dev/null | head -1)"
else
  warn "Neither tofu nor terraform on PATH. See docs/prerequisites.md."
fi

HAVE_GCLOUD=0
if command -v gcloud >/dev/null 2>&1; then
  HAVE_GCLOUD=1
  ACTIVE_ACCOUNT="$(gcloud config list account --format='value(core.account)' 2>/dev/null || true)"
  [ -n "$ACTIVE_ACCOUNT" ] && info "gcloud account: ${ACTIVE_ACCOUNT}"
else
  warn "gcloud not on PATH — needed for credentials and to reach the cluster."
fi

command -v kubectl >/dev/null 2>&1 \
  || warn "kubectl not on PATH — only needed to look at the cluster after apply."
command -v gke-gcloud-auth-plugin >/dev/null 2>&1 \
  || warn "gke-gcloud-auth-plugin not on PATH — kubectl needs it for GKE:
     gcloud components install gke-gcloud-auth-plugin
     (or, for a packaged gcloud: sudo apt-get install google-cloud-cli-gke-gcloud-auth-plugin)"

if [ -n "${TF_VAR_billing_account:-}" ]; then
  info "Billing account: from TF_VAR_billing_account"
else
  warn "TF_VAR_billing_account is not set. The apply needs it to create the project:
     export TF_VAR_billing_account=\"\$(gcloud billing accounts list --filter=open=true --format='value(name.basename())' --limit=1)\""
fi

# ── Wizard ───────────────────────────────────────────────────────────────────
header "Demo configuration"

ask NAME "Demo name" "demonginx"
case "$NAME" in
  ''|*[!a-z0-9-]*) die "Demo name '$NAME' must be lowercase letters, digits and hyphens." ;;
esac

# The folder may start with a digit; GCP resource names may not. Strip leading
# digits and hyphens, cap at 24 so "<prefix>-nodes" fits a service account ID,
# and drop any trailing hyphen the cut leaves.
PREFIX_DEFAULT="$(printf '%s' "$NAME" | sed -e 's/^[^a-z]*//' | cut -c1-24 | sed -e 's/-*$//')"
ask PREFIX "Resource prefix" "${PREFIX_DEFAULT:-demonginx}"
printf '%s' "$PREFIX" | grep -Eq '^[a-z][a-z0-9-]{0,22}[a-z0-9]$' \
  || die "Prefix '$PREFIX' must start with a letter, end with a letter or digit, and be 2-24 characters of a-z, 0-9 and '-'."

ask PROJECT_ID "GCP project ID to create" "rfp-202610-${PREFIX}"
printf '%s' "$PROJECT_ID" | grep -Eq '^[a-z][a-z0-9-]{4,28}[a-z0-9]$' \
  || die "Project ID '$PROJECT_ID' must be 6-30 characters, start with a letter, and use only a-z, 0-9 and '-'."

# us-east1 rather than europe-west1, which on 2 Nov 2026 could not supply a
# cluster at all (GCE_STOCKOUT before any node was requested).
ask REGION       "GCP region"                  "us-east1"
# "-b" rather than "-a": us-east1 and europe-west1, among others, have no zone a.
ask ZONE         "Zone for the nodes"          "${REGION}-b"
case "$ZONE" in
  "$REGION"-*) ;;
  *) die "Zone '$ZONE' is not in region '$REGION'." ;;
esac
# Arm by default. The module derives the pod architecture and the boot disk
# type from the family, so an x86 type needs nothing else changed.
ask MACHINE_TYPE "Node machine type"           "c4a-standard-1"
ask MIN_NODES    "Minimum nodes"               "1"
ask MAX_NODES    "Maximum nodes"               "20"

case "$MIN_NODES$MAX_NODES" in
  *[!0-9]*) die "Node counts must be whole numbers." ;;
esac
[ "$MIN_NODES" -ge 1 ] && [ "$MIN_NODES" -le "$MAX_NODES" ] \
  || die "Need 1 <= min-nodes <= max-nodes; got ${MIN_NODES} and ${MAX_NODES}."

[ -n "$ORG_ID" ] && [ -n "$FOLDER_ID" ] && die "Set --org-id or --folder-id, not both."

# The module creates the project, so an ID that already exists fails the apply
# after the API calls start. Only a hit is conclusive: a project in someone
# else's organization looks the same as one that does not exist.
if [ "$HAVE_GCLOUD" -eq 1 ] && gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  die "Project '$PROJECT_ID' already exists. This module creates its project; pick a new ID."
fi

# A zone that does not exist, or a machine type the zone does not offer (T2A,
# found in only a few regions, or C4A in a zone without Axion hosts), fails at
# the cluster, minutes into the apply. The new project cannot answer yet, so
# ask in the active gcloud project; if that cannot read Compute, skip. Nothing
# checks for a stockout: capacity is only known when the VM is requested.
CHECK_PROJECT=""
[ "$HAVE_GCLOUD" -eq 1 ] && CHECK_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [ -n "$CHECK_PROJECT" ] \
  && gcloud compute regions describe "$REGION" --project "$CHECK_PROJECT" >/dev/null 2>&1; then
  gcloud compute zones describe "$ZONE" --project "$CHECK_PROJECT" >/dev/null 2>&1 \
    || die "Zone '$ZONE' does not exist. Zones in ${REGION}: $(gcloud compute zones list --project "$CHECK_PROJECT" \
         --filter="region:$REGION" --format='value(name)' 2>/dev/null | sort | tr '\n' ' ')"
  if ! gcloud compute machine-types describe "$MACHINE_TYPE" --zone "$ZONE" --project "$CHECK_PROJECT" >/dev/null 2>&1; then
    OFFERED_IN="$(gcloud compute machine-types list --project "$CHECK_PROJECT" --filter="name=$MACHINE_TYPE" \
      --format='value(zone)' 2>/dev/null | grep "^${REGION}-" | sort | tr '\n' ' ' || true)"
    die "Machine type '$MACHINE_TYPE' is not offered in ${ZONE}. In ${REGION}: ${OFFERED_IN:-none}"
  fi
  info "Zone ${ZONE} offers ${MACHINE_TYPE}"
else
  warn "Could not check that ${ZONE} offers ${MACHINE_TYPE}: the active gcloud project ('${CHECK_PROJECT:-unset}')
     cannot read Compute. Any project with Compute enabled can answer: rerun with
     CLOUDSDK_CORE_PROJECT=<project-id> in front."
fi

TARGET="$DEMOS/$NAME"

PARENT_DESC="none (account without an organization)"
[ -n "$ORG_ID" ]    && PARENT_DESC="organization ${ORG_ID}"
[ -n "$FOLDER_ID" ] && PARENT_DESC="folder ${FOLDER_ID}"

header "Summary"
cat <<SUMMARY
  Demo name     : ${GREEN}${NAME}${NC}
  Prefix        : ${GREEN}${PREFIX}${NC}  (cluster ${PREFIX}-gke)
  New project   : ${GREEN}${PROJECT_ID}${NC}
  Parent        : ${GREEN}${PARENT_DESC}${NC}
  Region        : ${GREEN}${REGION}${NC}  (nodes in ${ZONE})
  Nodes         : ${GREEN}${MACHINE_TYPE}, ${MIN_NODES} to ${MAX_NODES}, public IP each${NC}
  Target folder : ${GREEN}demos/${NAME}/${NC}
SUMMARY
echo

if [ "$NON_INTERACTIVE" -eq 0 ]; then
  read -rp "${BOLD}Proceed?${NC} (Y/n): " CONFIRM || true
  case "${CONFIRM:-y}" in
    [Yy]*) ;;
    *) info "Aborted."; exit 0 ;;
  esac
fi

# ── Render ───────────────────────────────────────────────────────────────────
CREATED=0; SKIPPED=0

render_dir() {
  local tdir="$1" dest="$2"; shift 2
  local f base
  mkdir -p "$dest"
  for f in "$tdir"/*.tmpl; do
    [ -e "$f" ] || continue
    base="$(basename "$f" .tmpl)"
    if [ -e "$dest/$base" ]; then
      skipped "${dest#"$ROOT/"}/$base"; SKIPPED=$((SKIPPED + 1)); continue
    fi
    sed "$@" "$f" > "$dest/$base"
    created "${dest#"$ROOT/"}/$base"; CREATED=$((CREATED + 1))
  done
}

write_file() {
  local dest="$1"
  if [ -e "$dest" ]; then
    skipped "${dest#"$ROOT/"}"; SKIPPED=$((SKIPPED + 1)); cat >/dev/null; return
  fi
  mkdir -p "$(dirname "$dest")"
  cat > "$dest"
  created "${dest#"$ROOT/"}"; CREATED=$((CREATED + 1))
}

header "Rendering demos/$NAME"

render_dir "$TEMPLATES" "$TARGET/terraform/gcp" -e "s|__DATE__|$TODAY|g"

if [ -n "$ORG_ID" ];    then PARENT_LINE="org_id = \"${ORG_ID}\""
elif [ -n "$FOLDER_ID" ]; then PARENT_LINE="folder_id = \"${FOLDER_ID}\""
else PARENT_LINE="# org_id    = \"\"
# folder_id = \"\""
fi

write_file "$TARGET/terraform/gcp/terraform.tfvars" <<TFVARS
# Generated by bootstrap-nginx.sh on ${TODAY}
# billing_account comes from TF_VAR_billing_account, not from this file.
project_id   = "${PROJECT_ID}"
region       = "${REGION}"
node_zones   = ["${ZONE}"]
app_name     = "${PREFIX}"
machine_type = "${MACHINE_TYPE}"
min_nodes    = ${MIN_NODES}
max_nodes    = ${MAX_NODES}

# One nginx pod per node, so the pod and node bounds move together. Raise
# nginx_min_replicas here to scale out by hand: N pods, so N nodes.
nginx_min_replicas = ${MIN_NODES}
nginx_max_replicas = ${MAX_NODES}

# Only if the account belongs to an organization. One or the other, not both.
${PARENT_LINE}

# Everything else has a default in variables.tf — Istio version, nginx image,
# CPU target, NodePorts and who may reach them. Override here.
TFVARS

# ── The page's Helm chart ────────────────────────────────────────────────────
# app.tf installs ../../chart, so each demo carries its own copy and can change
# the page without touching any other demo.
if [ -d "$TARGET/chart" ]; then
  skipped "demos/$NAME/chart"; SKIPPED=$((SKIPPED + 1))
else
  cp -r "$CHART" "$TARGET/chart"
  created "demos/$NAME/chart  (copied from src/charts/nginx-site)"; CREATED=$((CREATED + 1))
fi

# ── Demo metadata ────────────────────────────────────────────────────────────
# project-nuke.sh reads every variable below, under set -u, so none may be
# dropped. There is no hostname or audit bucket in this demo; nuke keeps its
# log locally when the upload fails.
write_file "$TARGET/.envconfig" <<ENVCONFIG
# Demo metadata — generated by bootstrap-nginx.sh. Read by project-nuke.sh.
DEMO_NAME="${NAME}"
DEMO_KIND="gke-nginx"
PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
CLUSTER_NAME="${PREFIX}-gke"
HOSTNAME_FQDN="none (NodePort ${NODE_PORT_HTTP} on the node IPs)"
AUDIT_BUCKET=""
CREATED_AT="${TODAY}"
CREATED_BY="$(whoami 2>/dev/null || echo unknown)"
ENVCONFIG

# ── Done ─────────────────────────────────────────────────────────────────────
header "Done — $CREATED created, $SKIPPED left alone"

cat <<MSG
demos/${NAME}/
├── .envconfig            metadata, read by project-nuke.sh
├── chart/                the page: nginx, HPA, PDB, Istio Gateway, mTLS policy
└── terraform/gcp/        project, network, GKE, Istio, and the chart's release

Next:
  1. export TF_VAR_billing_account=<billing-account-id>
  2. cd demos/${NAME}/terraform/gcp
     tofu init && tofu plan -out=tfplan && tofu apply tfplan
     (15-20 minutes: project, cluster, node pool, then Istio)
  3. eval "\$(tofu output -raw get_credentials_command)"
     eval "\$(tofu output -raw node_ips_command)"
     curl -i http://<node-public-ip>:${NODE_PORT_HTTP}/
     eval "\$(tofu output -raw egress_ip_check_command)"   # pod egress = node IP
     eval "\$(tofu output -raw quota_check_command)"       # external IPs cap the nodes

Scaling, by hand: set nginx_min_replicas = N in terraform.tfvars and apply
(N pods, so N nodes).

When you are finished:
  ./scripts/project-nuke.sh ${NAME}

Leaving a demo running costs money. Tear it down the same day if you can.
MSG
