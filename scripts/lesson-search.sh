#!/usr/bin/env bash
# harnessoperator-skills — lesson search: the mechanical half of /lesson.
# A lesson is worth writing down only once, in one place. Before /lesson writes a rule,
# this script prints where rules for this project can live, and every existing line that
# mentions the lesson's keywords. The model can then strengthen a rule that's already
# there, or flag the one it contradicts, instead of adding a near-duplicate.
#
# Usage: lesson-search.sh <keyword> [keyword ...]   (case-insensitive, any keyword matches)
# Run it from the session's working directory. Read-only. Needs bash; git is optional.
# Tests: bash tests/test-checkpoint.sh

MAX_HITS=${HO_LESSON_MAX_HITS:-60}
[ $# -gt 0 ] || { echo "Usage: lesson-search.sh <keyword> [keyword ...]" >&2; exit 1; }

slugify() { printf '%s' "$1" | sed 's#[^A-Za-z0-9]#-#g'; }
root=$(git rev-parse --show-toplevel 2>/dev/null)

# @path imports in a CLAUDE.md load with it, so a rule can live in one. Resolved one level
# deep, relative to the importing file, ignoring code spans.
imports() {
  sed 's/`[^`]*`//g' "$1" | grep -oE '(^|[[:space:]])@[~./A-Za-z0-9_-]+\.md' | sed -E 's/^[[:space:]]*@//' |
    while IFS= read -r p; do
      case "$p" in ("~/"*) p="$HOME/${p#\~/}" ;; (/*) ;; (*) p="$(dirname "$1")/$p" ;; esac
      [ -f "$p" ] && echo "$p"
    done
}

# Claude Code keys auto memory by the launch directory, spelled as launched (symlinks
# kept). The script may run deeper than that, so walk up from here, then try the repo root.
memdir=
d=$PWD
while :; do
  [ -d "$HOME/.claude/projects/$(slugify "$d")/memory" ] && { memdir="$HOME/.claude/projects/$(slugify "$d")/memory"; break; }
  [ "$d" = / ] && break; d=$(dirname "$d")
done
[ -z "$memdir" ] && [ -n "$root" ] && [ -d "$HOME/.claude/projects/$(slugify "$root")/memory" ] && memdir="$HOME/.claude/projects/$(slugify "$root")/memory"

echo "# Lesson search: $*"
echo
echo "## Where a rule can live"
echo
echo "- global (every project): $HOME/.claude/CLAUDE.md$([ -f "$HOME/.claude/CLAUDE.md" ] || echo ' (does not exist yet)')"
if [ -n "$root" ]; then
  echo "- this repo (committed, shared with anyone who clones it): $root/CLAUDE.md$([ -f "$root/CLAUDE.md" ] || echo ' (does not exist yet)')"
else
  echo "- this folder (no git repo): $PWD/CLAUDE.md$([ -f "$PWD/CLAUDE.md" ] || echo ' (does not exist yet)')"
fi
if [ -n "$memdir" ]; then
  echo "- auto memory (this machine only): $memdir/ — index MEMORY.md, $(ls "$memdir" | grep -c '\.md$') files"
else
  echo "- auto memory: none yet for this folder ($HOME/.claude/projects/$(slugify "$PWD")/memory/)"
fi
echo

# Every file a rule could already be in: the global file and its imports, CLAUDE.md files
# from here up to / (Claude Code loads them all), rules folders, and the memory folder.
files=$(
  g="$HOME/.claude/CLAUDE.md"; [ -f "$g" ] && { echo "$g"; imports "$g"; }
  ls "$HOME/.claude/rules"/*.md 2>/dev/null
  d=$PWD
  while :; do
    for f in "$d/CLAUDE.md" "$d/CLAUDE.local.md" "$d/.claude/CLAUDE.md"; do [ -f "$f" ] && { echo "$f"; imports "$f"; }; done
    ls "$d/.claude/rules"/*.md 2>/dev/null
    [ "$d" = / ] && break; d=$(dirname "$d")
  done
  [ -n "$memdir" ] && ls "$memdir"/*.md 2>/dev/null
)
files=$(printf '%s\n' "$files" | grep . | awk '!seen[$0]++')

pattern=$(printf '%s\n' "$@" | sed 's/[][\.*^$(){}+?|/]/\\&/g' | paste -sd'|' -)
echo "## Existing lines that mention it (max $MAX_HITS)"
echo
# Memory notes are mostly project history, where words like "merged" or "deploy" appear as
# status on every page. Rules live in the index, in each note's one-line description, and
# in feedback notes, so only those are searched in the memory folder.
hits=$(printf '%s\n' "$files" | while IFS= read -r f; do
    if [ -n "$memdir" ] && [ "$(dirname "$f")" = "$memdir" ] && [ "$(basename "$f")" != MEMORY.md ] &&
       ! grep -qE '^[[:space:]]*type:[[:space:]]*feedback' "$f"; then
      grep -niE -- "$pattern" "$f" 2>/dev/null | grep -E '^[0-9]+:description:'
    else
      grep -niE -- "$pattern" "$f" 2>/dev/null | grep -v '^[0-9]*:---$'
    fi | cut -c1-220 | sed "s#^#$f:#"
  done)
n=$(printf '%s\n' "$hits" | grep -c .)
if [ "$n" -eq 0 ]; then
  echo "- none: nothing written down mentions these words yet"
else
  printf '%s\n' "$hits" | head -"$MAX_HITS" | sed 's/^/- /'
  [ "$n" -gt "$MAX_HITS" ] && echo "- … $((n - MAX_HITS)) more; narrow the keywords"
fi
echo
echo "searched $(printf '%s\n' "$files" | grep -c .) files"
exit 0
