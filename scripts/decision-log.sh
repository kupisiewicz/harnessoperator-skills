#!/usr/bin/env bash
# harnessoperator-skills — decision log: the mechanical half of /decision.
# A settled choice that lives only in one session's summary gets argued again in the
# next. DECISIONS.md keeps them per project, beside the checkpoints, append-only: an entry
# is never rewritten, only marked superseded by a later one. This script owns the parts
# that must be exact: where the file is, which IDs exist, and what is still in force.
#
# Usage:
#   decision-log.sh path [dir]   print the DECISIONS.md path (creating its folder, 700)
#   decision-log.sh list [dir]   the active decisions, one line each, then a count
#   decision-log.sh next [dir]   the next free ID, e.g. D4
# [dir] defaults to $PWD. Keyed exactly like checkpoints: the repo root, or the
# symlink-free folder outside a repo. Read-only except `path` making the folder.
# Needs bash; git is optional. Tests: bash tests/test-checkpoint.sh

umask 077   # decisions quote the session; owner-only like the checkpoints beside them
cmd=$1; dir=${2:-$PWD}
[ -d "$dir" ] || { echo "No such folder: $dir" >&2; exit 1; }
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=$(cd "$dir" && pwd -P)
file="$HOME/.claude/checkpoints/$(printf '%s' "$root" | sed 's#[^A-Za-z0-9]#-#g')/DECISIONS.md"

# Entries are "## D<n> — <date> — <title>" headings, each with a "- **Status:**" line.
case "$cmd" in
  path)
    mkdir -p "$(dirname "$file")" && echo "$file" ;;
  next)
    n=$( [ -f "$file" ] && grep -oE '^## D[0-9]+' "$file" | tr -dc '0-9\n' | sort -n | tail -1)
    echo "D$(( ${n:-0} + 1 ))" ;;
  list)
    [ -f "$file" ] || { echo "No decisions logged yet for $root ($file)"; exit 0; }
    awk '
      /^## D[0-9]+/ { if (h != "") out(); h = substr($0, 4); s = "active"; next }
      /^- \*\*Status:\*\*/ { s = tolower($0); sub(/^- \*\*status:\*\* */, "", s) }
      END { if (h != "") out(); printf "%d active, %d superseded — %s\n", a, x, FILENAME }
      function out() { if (s ~ /^superseded/) x++; else { a++; print "- " h } }' "$file" ;;
  *)
    echo "Usage: decision-log.sh path|list|next [dir]" >&2; exit 1 ;;
esac
