#!/usr/bin/env bash
# harnessoperator-skills — doctor: the checks behind /doctor. /cure applies the fixes.
# The hooks fail silently by design (a hook must never break a session), so a broken
# install looks exactly like a working one: no checkpoint gets written, the evidence gate
# never fires, and nobody notices for weeks. This script looks for each way it breaks and
# prints one finding per problem, each with the fix that cures it:
#
#   FAIL <id>  <what is wrong>          broken: a feature is off right now
#   WARN <id>  <what is wrong>          degraded, stale, or switched off on purpose
#     fix (safe): cure.sh <args>        /cure applies it unasked: idempotent, backed up
#     fix (ask):  cure.sh <args>        /cure applies it only after the user's yes
#     fix (manual): <what to do>        only the user (or the model, by hand) can do it
#
# Usage: doctor.sh   (run from the project folder; the project checks use it)
# Read-only. Always exits 0; the last line counts the findings. Needs bash; jq for most.
# Tests: bash tests/test-checkpoint.sh

claude="$HOME/.claude"
hd="$claude/hooks/harnessoperator"
settings="$claude/settings.json"
cure="bash ~/.claude/hooks/harnessoperator/cure.sh"
fails=0; warns=0; oks=0
fail() { fails=$((fails + 1)); printf 'FAIL %-22s %s\n' "$1" "$2"; [ -n "$3" ] && printf '  fix (%s): %s\n' "$3" "$4"; }
warn() { warns=$((warns + 1)); printf 'WARN %-22s %s\n' "$1" "$2"; [ -n "$3" ] && printf '  fix (%s): %s\n' "$3" "$4"; }
ok()   { oks=$((oks + 1)); printf 'OK   %-22s %s\n' "$1" "$2"; }
done_() { echo; echo "doctor: $fails fail, $warns warn, $oks ok"; exit 0; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

# The checkout install.sh ran from: the reinstall fix needs it, and installed copies are
# compared against it. Installs older than the doctor didn't record one.
src=$(cat "$hd/source" 2>/dev/null)
fi_cls=safe; fi_cmd="$cure reinstall"
if [ -n "$src" ] && [ -f "$src/install.sh" ]; then ok source "installed from $src"
else
  fi_cls=manual; fi_cmd="cd <your harnessoperator-skills checkout> && bash install.sh"
  warn source "can't find the checkout this was installed from, so the reinstall fix is off" \
    manual "cd <your harnessoperator-skills checkout> && git pull && bash install.sh"
fi

if command -v jq >/dev/null; then ok jq "$(jq --version)"
else fail jq "jq is missing: every hook needs it, so all of them do nothing" manual "brew install jq (macOS) or apt install jq"; done_; fi

if [ ! -f "$settings" ]; then fail settings "$settings does not exist, so no hook is wired" "$fi_cls" "$fi_cmd"; done_
elif ! jq empty "$settings" 2>/dev/null; then
  # Claude Code ignores a settings file it can't parse: every setting in it is off.
  if ls "$settings".bak-harnessoperator-* >/dev/null 2>&1; then
    fail settings "$settings is not valid JSON, so Claude Code ignores all of it" ask "$cure restore-settings"
  else fail settings "$settings is not valid JSON, so Claude Code ignores all of it" manual "fix the JSON by hand: jq empty $settings shows where"; fi
  done_
else ok settings "valid JSON"; fi

# Hook files: present, executable, and the same as the checkout's.
for h in checkpoint.sh evidence-gate.sh brief-guard.sh; do
  f="$hd/$h"
  if [ ! -f "$f" ]; then fail "hook:$h" "missing: $f" "$fi_cls" "$fi_cmd"
  elif [ ! -x "$f" ]; then fail "hook:$h" "not executable, so Claude Code can't run it: $f" safe "$cure chmod $f"
  elif ! bash -n "$f" 2>/dev/null; then fail "hook:$h" "syntax error: $f" "$fi_cls" "$fi_cmd"
  elif [ -n "$src" ] && [ -f "$src/hooks/$h" ] && ! cmp -s "$src/hooks/$h" "$f"; then
    warn "hook:$h" "differs from $src/hooks/$h (an older install, or a newer checkout)" "$fi_cls" "$fi_cmd"
  else ok "hook:$h" "installed"; fi
done

# Wiring: each hook once per event, with the matchers install.sh sets. Two entries run the
# hook twice; none means the feature is off.
wired() { jq --arg c "$hd/$2" "[.hooks.$1[]? | select(any(.hooks[]?; .command == \$c))] | length" "$settings"; }
for w in PreCompact:checkpoint.sh PostCompact:checkpoint.sh SessionStart:checkpoint.sh Stop:evidence-gate.sh PreToolUse:brief-guard.sh; do
  e=${w%%:*}; h=${w#*:}; n=$(wired "$e" "$h")
  if [ "$n" = 0 ]; then fail "wiring:$e" "$h is not wired to $e" "$fi_cls" "$fi_cmd"
  elif [ "$n" != 1 ]; then warn "wiring:$e" "$h is wired to $e $n times, so it runs $n times" "$fi_cls" "$fi_cmd"
  else ok "wiring:$e" "$h"; fi
done
m=$(jq -r --arg c "$hd/checkpoint.sh" '[.hooks.SessionStart[]? | select(any(.hooks[]?; .command == $c)) | .matcher // ""] | first // ""' "$settings")
case "$m" in (*compact*startup*|*startup*compact*) ;; (*) [ -n "$m" ] &&
  warn "wiring:matcher" "SessionStart matcher is \"$m\"; it needs compact and startup" "$fi_cls" "$fi_cmd" ;; esac

# Smoke test: each hook must exit 0 and stay silent on an event it ignores. A crash here
# means it crashes on every real event too.
for h in checkpoint.sh evidence-gate.sh brief-guard.sh; do
  [ -x "$hd/$h" ] || continue
  out=$(printf '{"hook_event_name":"DoctorProbe"}' | "$hd/$h" 2>&1); rc=$?
  if [ $rc -ne 0 ] || [ -n "$out" ]; then fail "smoke:$h" "exits $rc on a harmless probe: ${out:0:120}" "$fi_cls" "$fi_cmd"
  else ok "smoke:$h" "runs clean"; fi
done

# Commands: every one the checkout ships, installed and current.
if [ -n "$src" ] && [ -d "$src/commands" ]; then
  miss=""; old=""
  for f in "$src"/commands/*.md; do
    b=$(basename "$f"); dest="$claude/commands/$b"
    if [ ! -f "$dest" ]; then miss="$miss /${b%.md}"; elif ! cmp -s "$f" "$dest"; then old="$old /${b%.md}"; fi
  done
  if [ -n "$miss" ]; then fail commands "not installed:$miss" "$fi_cls" "$fi_cmd"
  elif [ -n "$old" ]; then warn commands "differ from the checkout:$old (edited by hand, or an older install)" "$fi_cls" "$fi_cmd"
  else ok commands "all installed"; fi
fi

# Compact instructions: without them a compact summary misses the sections the hook needs.
md="$claude/CLAUDE.md"; nb=$(grep -c 'harnessoperator:compact-instructions:begin' "$md" 2>/dev/null); nb=${nb:-0}
if [ "$nb" = 1 ]; then ok compact-instructions "in $md"
elif [ "$nb" = 0 ] && grep -q '^## Compact instructions' "$md" 2>/dev/null; then ok compact-instructions "hand-written in $md"
elif [ "$nb" = 0 ]; then fail compact-instructions "missing from $md, so compact summaries lack the resume sections" "$fi_cls" "$fi_cmd"
else warn compact-instructions "$nb copies in $md" "$fi_cls" "$fi_cmd"; fi

# Switched off on purpose is still worth saying: it is easy to forget.
for v in HO_EVIDENCE_GATE HO_BRIEF_GUARD; do
  if [ "$(jq -r --arg v "$v" '.env[$v] // empty' "$settings")" = off ]; then
    warn "off:$v" "$v=off in $settings, so it is off in every session" ask "$cure unset-env $v"
  elif [ "${!v:-}" = off ]; then
    warn "off:$v" "$v=off in this shell's environment" manual "unset $v where it is exported"
  fi
done

# Other hooks whose script is gone: Claude Code reports an error on every event for them.
# Read in this shell (a here-string, not a pipe) so warn() can count.
dead=$(jq -r '.hooks // {} | to_entries[] | .value[]?.hooks[]? | .command // empty' "$settings" | sort -u |
while IFS= read -r c; do
  set -f; set -- $c; set +f
  case "$1" in (bash|sh|zsh|node|bun|python|python3|ruby|perl) shift ;; esac
  p=${1:-}; case "$p" in ("~/"*) p="$HOME/${p#\~/}" ;; ('$HOME/'*) p="$HOME/${p#\$HOME/}" ;; esac
  case "$p" in (/*) [ -e "$p" ] || printf '%s\n' "$c" ;; esac
done)
while IFS= read -r c; do
  [ -n "$c" ] || continue
  warn dead-hook "a hook runs a file that doesn't exist: $c" ask "$cure remove-hook '$c'"
done <<<"$dead"

# This project: its last checkpoint and its brief.
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
d="$claude/checkpoints/$(printf '%s' "$root" | sed 's#[^A-Za-z0-9]#-#g')"
if [ -f "$d/latest.md" ] && grep -q 'INCOMPLETE' "$d/latest.md"; then
  warn checkpoint "the last compact summary is INCOMPLETE: $d/latest.md" manual "run /checkpoint to write a complete one"
elif [ -f "$d/latest.md" ]; then ok checkpoint "$d/latest.md"; fi
if [ -f "$d/BRIEF.md" ]; then
  days=$(( ($(date +%s) - $(mtime "$d/BRIEF.md")) / 86400 ))
  if [ "$days" -ge "${HO_BRIEF_STALE_DAYS:-14}" ]; then
    warn brief "BRIEF.md is $days days old; a session that reads it is held to it" ask "$cure archive-brief $d"
  else ok brief "$days days old"; fi
fi
done_
