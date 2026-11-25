#!/usr/bin/env bash
# harnessoperator-skills — brief guard: a PreToolUse hook that refuses edits to the files
# the task brief (/brief) lists under "Don't touch".
#
# The brief is the contract the user confirmed, but a list in a markdown file is only a
# request: deep in a task, the model edits the generated file or the production config
# anyway. This hook makes the list binding. Every path or glob written in backticks in
# the brief's "Don't touch" section is enforced against Edit, Write, MultiEdit,
# NotebookEdit and lean-ctx patches. Prose items ("production data") stay advisory.
#
# Which brief: BRIEF.md in the checkpoint folder of the edited file's project (its repo
# root, else the session's folder). It binds only a session whose transcript names that
# brief, i.e. one that wrote, read or was pointed at it, so a brief left over from an old
# task never blocks an unrelated session.
# shortcut: shell commands (sed -i, rm, >) are not checked; upgrade if a brief is broken
# that way in practice.
#
# Disable with HO_BRIEF_GUARD=off. Must always exit 0. Needs bash and jq.
# Tests: bash tests/test-checkpoint.sh

[ "${HO_BRIEF_GUARD:-on}" = off ] && exit 0
input=$(cat)
field() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
file=$(field '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path')
[ -n "$file" ] || exit 0
cwd=$(field .cwd); cwd=${cwd:-$PWD}
case "$file" in (/*) ;; (~/*) file="$HOME/${file#\~/}" ;; (*) file="$cwd/$file" ;; esac
transcript=$(field .transcript_path)
slugify() { printf '%s' "$1" | sed 's#[^A-Za-z0-9]#-#g'; }

# The file may not exist yet (Write creates it): resolve its nearest existing folder,
# symlink-free, so it compares with git's roots.
e=$(dirname "$file"); while [ ! -d "$e" ] && [ "$e" != / ]; do e=$(dirname "$e"); done
d=$(cd "$e" && pwd -P) || exit 0
abs="${d%/}/${file#"${e%/}"/}"
root=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || root=$(cd "$cwd" 2>/dev/null && pwd -P) || exit 0
brief="$HOME/.claude/checkpoints/$(slugify "$root")/BRIEF.md"
[ -f "$brief" ] || exit 0
[ -f "$transcript" ] && grep -qF -- "$brief" "$transcript" || exit 0

case "$abs" in ("$root"/*) rel=${abs#"$root"/} ;; (*) rel=$abs ;; esac
# Backticked tokens of the section, one per line, that look like a path or a glob.
pats=$(awk '/^## /{on = ($0 ~ /^## Don.t touch/); next} on' "$brief" |
  grep -oE '`[^`]+`' | tr -d '`' | grep -E '[/.*]' | grep -vE '[[:space:]]')
hit=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in (~/*) p="$HOME/${p#\~/}" ;; esac
  p=${p%/}
  # Relative patterns are from the project root; a folder covers what is inside it.
  # The pattern is unquoted on purpose: it is a glob.
  case "$p" in (/*) t=$abs ;; (*) t=$rel ;; esac
  case "$t" in ($p|$p/*) hit=$p; break ;; esac
done <<<"$pats"
[ -n "$hit" ] || exit 0

reason="Brief guard: $rel is under \"Don't touch\" (\`$hit\`) in the task brief $brief. Leave it as it is. If the task really needs it changed, say why and ask the user; once they agree, update the brief's Don't touch section first, then edit."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
