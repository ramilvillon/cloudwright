#!/usr/bin/env bash
# Install the cloudwright skills into ~/.agents/skills/ so Agent-Skills-conformant
# runtimes (Codex, Gemini CLI, opencode, Cursor, Copilot, Antigravity) discover them.
#
# Usage:
#   ./install.sh            # copy the skills (default)
#   ./install.sh --symlink  # symlink instead of copy (edits in the repo take effect live)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.agents/skills" && pwd)"
DEST="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"
MODE="copy"
[ "${1:-}" = "--symlink" ] && MODE="symlink"

mkdir -p "$DEST"
for dir in "$SRC"/*/; do
  name="$(basename "$dir")"
  target="$DEST/$name"
  if [ -e "$target" ]; then
    echo "warning: $target already exists — skipping (remove it first to reinstall)" >&2
    continue
  fi
  if [ "$MODE" = "symlink" ]; then
    ln -s "${dir%/}" "$target"
    echo "linked  $name -> $target"
  else
    cp -R "$dir" "$target"
    echo "copied  $name -> $target"
  fi
done
echo "Done. Installed ($MODE) into $DEST"
