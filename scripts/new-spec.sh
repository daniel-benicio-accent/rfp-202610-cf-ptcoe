#!/usr/bin/env bash
#
# Scaffold a new specification folder from the templates in specs/_templates.
#
# Usage: ./scripts/new-spec.sh "Customer onboarding demo flow"

set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "${1// /}" ]; then
  echo 'Usage: ./scripts/new-spec.sh "Spec title"' >&2
  exit 1
fi

title="$*"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
specs="$root/specs"
templates="$specs/_templates"

[ -d "$templates" ] || { echo "Templates not found at $templates" >&2; exit 1; }

# Next sequential id, never reusing a number.
next=1
for dir in "$specs"/[0-9][0-9][0-9][0-9]-*/; do
  [ -d "$dir" ] || continue
  n=$((10#$(basename "$dir" | cut -d- -f1) + 1))
  if [ "$n" -gt "$next" ]; then next="$n"; fi
done
id="$(printf '%04d' "$next")"

slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
[ -n "$slug" ] || { echo 'Title must contain at least one letter or digit.' >&2; exit 1; }

target="$specs/$id-$slug"
[ -e "$target" ] && { echo "$target already exists." >&2; exit 1; }
mkdir -p "$target"

today="$(date +%Y-%m-%d)"
for name in spec plan tasks; do
  sed -e "s|{{ID}}|$id|g" -e "s|{{TITLE}}|$title|g" -e "s|{{DATE}}|$today|g" \
    "$templates/$name.md" > "$target/$name.md"
done

cat <<MSG
Created specs/$id-$slug/

Next steps:
  1. Fill in specs/$id-$slug/spec.md (what and why, no implementation detail).
  2. Add a row to specs/README.md.
  3. Get it reviewed, then set Status: Approved before writing plan.md.
MSG
