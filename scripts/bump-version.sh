#!/usr/bin/env bash
# bump-version.sh — set or check the version across all manifests declared in
# .version-bump.json. Handles JSON (via jq, incl. nested paths like
# "plugins.0.version") and YAML top-level "version:" fields (via sed).
#
# Usage:
#   scripts/bump-version.sh <new-version>   # set every declared field
#   scripts/bump-version.sh --check         # report versions; exit 1 on drift/missing
#
# bash 3.2 + BSD/GNU sed safe.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$REPO_ROOT/.version-bump.json"
[ -f "$CONFIG" ] || { echo "error: $CONFIG not found" >&2; exit 1; }

# dotted field path -> jq path: "plugins.0.version" -> .plugins[0].version
jq_path() { echo "$1" | sed -E 's/\.([0-9]+)/[\1]/g; s/^/./'; }

read_field() {  # file field
  case "$1" in
    *.json) jq -r "$(jq_path "$2")" "$1" ;;
    *.yaml|*.yml) sed -nE "s/^$2:[[:space:]]*\"?([^\"]+)\"?[[:space:]]*\$/\1/p" "$1" | head -1 ;;
  esac
}

write_field() {  # file field value
  case "$1" in
    *.json) jq "$(jq_path "$2") = \"$3\"" "$1" > "$1.tmp" && mv "$1.tmp" "$1" ;;
    *.yaml|*.yml) sed -E -i.bak "s/^($2:[[:space:]]*).*/\1$3/" "$1" && rm -f "$1.bak" ;;
  esac
}

if [ "${1:-}" = "--check" ]; then
  drift=0; first=""
  while IFS=$'\t' read -r path field; do
    f="$REPO_ROOT/$path"
    if [ ! -f "$f" ]; then printf "  %-44s MISSING\n" "$path"; drift=1; continue; fi
    v="$(read_field "$f" "$field")"
    printf "  %-44s %s\n" "$path ($field)" "$v"
    if [ -z "$first" ]; then first="$v"; elif [ "$v" != "$first" ]; then drift=1; fi
  done < <(jq -r '.files[] | "\(.path)\t\(.field)"' "$CONFIG")
  if [ "$drift" -eq 0 ]; then echo "OK: all versions match ($first)"; else echo "DRIFT detected" >&2; exit 1; fi
  exit 0
fi

NEW="${1:?usage: bump-version.sh <new-version> | --check}"
while IFS=$'\t' read -r path field; do
  f="$REPO_ROOT/$path"
  if [ ! -f "$f" ]; then echo "warning: $path missing, skipping" >&2; continue; fi
  write_field "$f" "$field" "$NEW"
  echo "set $path ($field) -> $NEW"
done < <(jq -r '.files[] | "\(.path)\t\(.field)"' "$CONFIG")
