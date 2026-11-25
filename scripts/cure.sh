#!/usr/bin/env bash
# harnessoperator-skills — cure: applies one fix that /doctor (scripts/doctor.sh) named.
# Every fix doctor prints is spelled as a call to this script, so /cure never improvises
# an edit to settings.json: each repair is one known, tested operation that backs up what
# it changes. Doctor labels each fix safe (/cure applies it unasked) or ask (only after the
# user's yes). This script applies whatever it is given; the labels are /cure's to honour.
#
# Usage: cure.sh <fix> [arg]
#   reinstall              re-run install.sh from the recorded checkout (idempotent, backs up)
#   chmod <file>           make an installed hook executable (only files in its own folder)
#   unset-env <HO_NAME>    remove HO_NAME from settings.json "env"
#   remove-hook <command>  remove every hook entry that runs exactly <command>
#   restore-settings       replace an unparseable settings.json with its newest valid backup
#   archive-brief <dir>    move <dir>/BRIEF.md aside as BRIEF-<its date>.md
# Exit 0 = applied (or nothing to do), 1 = refused or failed. Needs bash and jq.
# Tests: bash tests/test-checkpoint.sh

claude="$HOME/.claude"
hd="$claude/hooks/harnessoperator"
settings="$claude/settings.json"
stamp=$(date +%Y%m%d-%H%M%S)
die() { echo "cure: $*" >&2; exit 1; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
backup() { cp -p "$1" "$1.bak-harnessoperator-$stamp" && echo "backup: $1.bak-harnessoperator-$stamp"; }
# Writes jq's output over settings.json only if it is valid JSON: a half-written settings
# file switches off every setting in it.
edit_settings() {
  [ -f "$settings" ] && jq empty "$settings" 2>/dev/null || die "$settings is missing or not valid JSON; run restore-settings first"
  local tmp="$settings.cure-$$"
  jq "$@" "$settings" > "$tmp" && jq empty "$tmp" 2>/dev/null || { rm -f "$tmp"; die "jq failed; nothing changed"; }
  backup "$settings" >/dev/null && mv "$tmp" "$settings"
}

fix=$1; arg=$2
case "$fix" in
  (reinstall)
    src=$(cat "$hd/source" 2>/dev/null)
    [ -n "$src" ] && [ -f "$src/install.sh" ] || die "no recorded checkout; run install.sh from yours"
    bash "$src/install.sh" ;;
  (chmod)
    # Only the installed hooks and helpers: this is not a general chmod.
    case "$arg" in ("$hd"/*.sh) ;; (*) die "chmod only touches files in $hd" ;; esac
    [ -f "$arg" ] || die "no such file: $arg"
    chmod +x "$arg" && echo "made executable: $arg" ;;
  (unset-env)
    case "$arg" in (HO_[A-Z_]*) ;; (*) die "unset-env only removes HO_* variables" ;; esac
    edit_settings --arg v "$arg" 'if .env then .env |= del(.[$v]) else . end | if .env == {} then del(.env) else . end' &&
      echo "removed $arg from $settings (start a new session for it to apply)" ;;
  (remove-hook)
    [ -n "$arg" ] || die "remove-hook needs the exact command"
    n=$(jq --arg c "$arg" '[.hooks // {} | .[][]?.hooks[]? | select(.command == $c)] | length' "$settings" 2>/dev/null)
    [ "${n:-0}" -gt 0 ] || { echo "no hook runs exactly: $arg"; exit 0; }
    edit_settings --arg c "$arg" '.hooks |= (with_entries(.value |= (map(.hooks |= map(select(.command != $c)))
        | map(select((.hooks | length) > 0)))) | with_entries(select((.value | length) > 0)))' &&
      echo "removed $n hook entry(s) that ran: $arg" ;;
  (restore-settings)
    jq empty "$settings" 2>/dev/null && { echo "$settings is valid JSON; nothing to restore"; exit 0; }
    good=""
    while IFS= read -r b; do
      jq empty "$b" 2>/dev/null && { good=$b; break; }
    done <<<"$(ls -t "$settings".bak-harnessoperator-* 2>/dev/null)"
    [ -n "$good" ] || die "no valid backup of $settings; fix it by hand (jq empty shows where)"
    cp -p "$settings" "$settings.broken-$stamp" && cp -p "$good" "$settings" &&
      echo "restored $settings from $good; the broken file is kept as $settings.broken-$stamp" ;;
  (archive-brief)
    [ -f "$arg/BRIEF.md" ] || die "no BRIEF.md in $arg"
    case "$arg" in ("$claude/checkpoints/"*) ;; (*) die "archive-brief only works in $claude/checkpoints" ;; esac
    to="$arg/BRIEF-$(date -r "$(mtime "$arg/BRIEF.md")" +%F_%H%M%S 2>/dev/null || date -d "@$(mtime "$arg/BRIEF.md")" +%F_%H%M%S).md"
    mv "$arg/BRIEF.md" "$to" && echo "archived: $to" ;;
  (*) die "unknown fix '$fix'. Fixes: reinstall, chmod, unset-env, remove-hook, restore-settings, archive-brief" ;;
esac
