#!/usr/bin/env bash
################################################################################
# bootstrap-terraform.sh — wizard that creates a self-contained demo project.
#
# Asks for the parameters of one demo, then renders a complete, ready-to-apply
# Terraform tree into demos/<name>/. Several demos can exist side by side in
# different GCP projects and Cloudflare hostnames; nothing is shared between
# them except the templates they were rendered from.
#
# Versioning a demo folder is your choice. Commit it when you want a record of
# exactly what a given demo was; leave it alone otherwise. Local state,
# .envconfig and tfvars are gitignored either way.
#
# Usage:
#   ./scripts/bootstrap-terraform.sh                       # interactive wizard
#   ./scripts/bootstrap-terraform.sh --non-interactive \
#       --name cfdemo-001 --project my-gcp-project \
#       --zone-id abc123 --subdomain demo --domain example.com
#
# Options (each also prompted for when interactive):
#   --name <s>          demo folder and resource prefix
#   --project <s>       GCP project ID
#   --region <s>        GCP region                      (default europe-west1)
#   --bucket <s>        audit bucket name
#   --zone-id <s>       Cloudflare zone ID
#   --domain <s>        apex domain of that zone
#   --subdomain <s>     record name within the zone     (default demo)
#   --feature <id:slug> edge feature module, repeatable (default 0002:bot-management)
#   --non-interactive   take every answer from flags and defaults
#   -h | --help         this message
#
# Tear a demo down with: ./scripts/project-nuke.sh <name>
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
TEMPLATES="$ROOT/src/terraform/_templates"
DEMOS="$ROOT/demos"
TODAY="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

NON_INTERACTIVE=0
NAME=""; PROJECT_ID=""; REGION=""; AUDIT_BUCKET=""
ZONE_ID=""; DOMAIN=""; SUBDOMAIN=""
FEATURES=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)            NAME="${2:?}"; shift 2 ;;
    --project)         PROJECT_ID="${2:?}"; shift 2 ;;
    --region)          REGION="${2:?}"; shift 2 ;;
    --bucket)          AUDIT_BUCKET="${2:?}"; shift 2 ;;
    --zone-id)         ZONE_ID="${2:?}"; shift 2 ;;
    --domain)          DOMAIN="${2:?}"; shift 2 ;;
    --subdomain)       SUBDOMAIN="${2:?}"; shift 2 ;;
    --feature)         FEATURES+=("${2:?}"); shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    -h|--help)         sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                 die "Unknown option '$1'. Try --help." ;;
  esac
done

[ -d "$TEMPLATES" ] || die "Templates not found at $TEMPLATES"
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
header "Prerequisites"

if command -v tofu >/dev/null 2>&1; then
  info "OpenTofu: $(tofu --version 2>/dev/null | head -1)"
elif command -v terraform >/dev/null 2>&1; then
  info "Terraform: $(terraform --version 2>/dev/null | head -1)"
else
  warn "Neither tofu nor terraform on PATH. The tree will still be rendered,"
  warn "but you will need one of them to apply it. See docs/prerequisites.md."
fi

if command -v gcloud >/dev/null 2>&1; then
  ACTIVE_ACCOUNT="$(gcloud config list account --format='value(core.account)' 2>/dev/null || true)"
  [ -n "$ACTIVE_ACCOUNT" ] && info "gcloud account: ${ACTIVE_ACCOUNT}"
else
  ACTIVE_ACCOUNT=""
  warn "gcloud not on PATH — cannot pre-fill the build submitter."
fi

# ── Wizard ───────────────────────────────────────────────────────────────────
header "Demo configuration"

ask NAME         "Demo name"              "cfdemo-$(date +%s)"
case "$NAME" in
  *[!a-z0-9-]*) die "Demo name '$NAME' must be lowercase letters, digits and hyphens." ;;
esac

ask PROJECT_ID   "GCP project ID"         "$NAME"
ask REGION       "GCP region"             "europe-west1"
ask AUDIT_BUCKET "Audit bucket"           "${NAME%%-*}-audit"
ask ZONE_ID      "Cloudflare zone ID"     "REPLACE_ME"
ask DOMAIN       "Zone apex domain"       "example.com"
ask SUBDOMAIN    "Record name in the zone" "demo"

HOSTNAME_FQDN="${SUBDOMAIN}.${DOMAIN}"

if [ "${#FEATURES[@]}" -eq 0 ]; then
  FEATURES_DEFAULT="0002:bot-management"
  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    FEATURES_INPUT="$FEATURES_DEFAULT"
  else
    read -rp "${BOLD}Edge feature modules${NC} (space-separated id:slug) [${FEATURES_DEFAULT}]: " FEATURES_INPUT || true
    FEATURES_INPUT="${FEATURES_INPUT:-$FEATURES_DEFAULT}"
  fi
  read -r -a FEATURES <<< "$FEATURES_INPUT"
fi

if [ -n "$ACTIVE_ACCOUNT" ]; then
  case "$ACTIVE_ACCOUNT" in
    *.gserviceaccount.com) SUBMITTER="serviceAccount:${ACTIVE_ACCOUNT}" ;;
    *)                     SUBMITTER="user:${ACTIVE_ACCOUNT}" ;;
  esac
else
  SUBMITTER="user:REPLACE_ME"
fi

TARGET="$DEMOS/$NAME"

header "Summary"
cat <<SUMMARY
  Demo name     : ${GREEN}${NAME}${NC}
  GCP project   : ${GREEN}${PROJECT_ID}${NC}
  Region        : ${GREEN}${REGION}${NC}
  Audit bucket  : ${GREEN}${AUDIT_BUCKET}${NC}
  Cloudflare    : ${GREEN}${HOSTNAME_FQDN}${NC}  (zone ${ZONE_ID})
  Submitter     : ${GREEN}${SUBMITTER}${NC}
  Features      : ${GREEN}${FEATURES[*]}${NC}
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

render_dir "$TEMPLATES/gcp"  "$TARGET/terraform/gcp"             -e "s|__DATE__|$TODAY|g"
render_dir "$TEMPLATES/zone" "$TARGET/terraform/cloudflare/zone" -e "s|__DATE__|$TODAY|g"

write_file "$TARGET/terraform/gcp/terraform.tfvars" <<TFVARS
# Generated by bootstrap-terraform.sh on ${TODAY}
project_id   = "${PROJECT_ID}"
region       = "${REGION}"
app_name     = "${NAME}"
audit_bucket = "${AUDIT_BUCKET}"
submitter    = "${SUBMITTER}"
TFVARS

write_file "$TARGET/terraform/cloudflare/zone/terraform.tfvars" <<TFVARS
# Generated by bootstrap-terraform.sh on ${TODAY}
zone_id   = "${ZONE_ID}"
subdomain = "${SUBDOMAIN}"
hostname  = "${HOSTNAME_FQDN}"

# Fill this in after the gcp module is applied:
#   cd ../../gcp && tofu output -raw service_url
# then strip the https:// prefix.
origin_hostname = "REPLACE_AFTER_GCP_APPLY"
TFVARS

for arg in "${FEATURES[@]}"; do
  [ -n "$arg" ] || continue
  case "$arg" in
    *:*) ;;
    *) die "Expected <spec-id>:<slug>, got '$arg'." ;;
  esac
  spec_id="${arg%%:*}"; slug="${arg#*:}"
  [ -n "$spec_id" ] && [ -n "$slug" ] || die "Malformed feature '$arg'."
  case "$slug" in
    *[!a-z0-9-]*) die "Slug '$slug' must be lowercase letters, digits and hyphens." ;;
  esac

  fname="$(printf '%s' "$slug" | tr '-' ' ')"
  fname="$(printf '%s' "${fname%"${fname#?}"}" | tr '[:lower:]' '[:upper:]')${fname#?}"
  enable_var="enable_$(printf '%s' "$slug" | tr '-' '_')"

  info "feature ${BOLD}${slug}${NC} — spec ${spec_id}, toggle \$${enable_var}"
  render_dir "$TEMPLATES/feature" "$TARGET/terraform/cloudflare/$slug" \
    -e "s|__FEATURE_SLUG__|$slug|g" \
    -e "s|__FEATURE_NAME__|$fname|g" \
    -e "s|__SPEC_ID__|$spec_id|g" \
    -e "s|__ENABLE_VAR__|$enable_var|g" \
    -e "s|__DATE__|$TODAY|g"

  write_file "$TARGET/terraform/cloudflare/$slug/terraform.tfvars" <<TFVARS
# Generated by bootstrap-terraform.sh on ${TODAY}
zone_id  = "${ZONE_ID}"
hostname = "${HOSTNAME_FQDN}"

# TODO(${spec_id}): set these before applying. See main.tf for the phase table.
# phase      = ""
# expression = ""
TFVARS
done

# ── Application sources ──────────────────────────────────────────────────────
# The gcp module hashes ../../app to decide when to rebuild the image, so each
# demo carries its own copy and can be tweaked independently.
if [ -d "$ROOT/src/app" ]; then
  if [ -d "$TARGET/app" ]; then
    skipped "demos/$NAME/app"; SKIPPED=$((SKIPPED + 1))
  else
    cp -r "$ROOT/src/app" "$TARGET/app"
    created "demos/$NAME/app  (copied from src/app)"; CREATED=$((CREATED + 1))
  fi
else
  warn "src/app does not exist yet (spec 0001 task 4)."
  warn "Until it does, 'tofu validate' in terraform/gcp fails with filesha256 errors."
fi

# ── Demo metadata ────────────────────────────────────────────────────────────
write_file "$TARGET/.envconfig" <<ENVCONFIG
# Demo metadata — generated by bootstrap-terraform.sh. Read by project-nuke.sh.
DEMO_NAME="${NAME}"
PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
AUDIT_BUCKET="${AUDIT_BUCKET}"
ZONE_ID="${ZONE_ID}"
HOSTNAME_FQDN="${HOSTNAME_FQDN}"
SUBMITTER="${SUBMITTER}"
FEATURES="${FEATURES[*]}"
CREATED_AT="${TODAY}"
CREATED_BY="$(whoami 2>/dev/null || echo unknown)"
ENVCONFIG

# ── Done ─────────────────────────────────────────────────────────────────────
header "Done — $CREATED created, $SKIPPED left alone"

cat <<MSG
demos/${NAME}/
├── .envconfig                       metadata, read by project-nuke.sh
├── app/                             application sources for this demo
└── terraform/
    ├── gcp/                         origin infrastructure
    └── cloudflare/
        ├── zone/                    proxied record, Host rewrite, edge secret
        └── <feature>/               one per edge capability, each toggled off

Next:
  1. export CLOUDFLARE_API_TOKEN=...
     export TF_VAR_edge_secret="\$(openssl rand -hex 24)"
  2. cd demos/${NAME}/terraform/gcp && tofu init && tofu apply
  3. Put 'tofu output -raw service_url' (without https://) into
     terraform/cloudflare/zone/terraform.tfvars as origin_hostname.
  4. cd ../cloudflare/zone && tofu init && tofu apply
  5. Fill the TODO(<spec-id>) markers in each feature module, then enable one
     at a time with: tofu apply -var '<enable_var>=true'

When you are finished, destroy everything in the right order:
  ./scripts/project-nuke.sh ${NAME}

Leaving a demo running costs money. Tear it down the same day if you can.
MSG
