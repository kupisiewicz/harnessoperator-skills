#!/usr/bin/env bash
# Removes what install.sh added. Keeps your checkpoints (~/.claude/checkpoints) and any
# command file you changed after installing. Backs up every file it edits first.
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd)
claude="$HOME/.claude"
hook="$claude/hooks/harnessoperator/checkpoint.sh"
settings="$claude/settings.json"
claude_md="$claude/CLAUDE.md"
stamp=$(date +%Y%m%d-%H%M%S)
begin='<!-- harnessoperator:compact-instructions:begin -->'
end='<!-- harnessoperator:compact-instructions:end -->'
say() { printf '  %s\n' "$*"; }

command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }
echo "Uninstalling harnessoperator-skills from $claude"
tmp=$(mktemp)

if [ -f "$settings" ] && jq empty "$settings" 2>/dev/null; then
  cp -p "$settings" "$settings.bak-harnessoperator-$stamp"
  jq --arg cmd "$hook" '
    if .hooks then .hooks |= with_entries(
      .value |= (map(.hooks |= map(select(.command != $cmd))) | map(select((.hooks | length) > 0))))
      | .hooks |= with_entries(select((.value | length) > 0))
    else . end' "$settings" > "$tmp" && mv "$tmp" "$settings"
  say "hooks removed from $settings"
fi

rm -f "$hook"
for f in "$repo"/scripts/*.sh; do rm -f "$(dirname "$hook")/$(basename "$f")"; done
rmdir "$(dirname "$hook")" 2>/dev/null || true; say "hook and helpers removed"

for f in "$repo"/commands/*.md; do
  dest="$claude/commands/$(basename "$f")"
  if cmp -s "$f" "$dest"; then rm -f "$dest"; say "command removed: /$(basename "$f" .md)"
  elif [ -f "$dest" ]; then say "kept $dest (it differs from the installed version)"; fi
done

if [ -f "$claude_md" ] && grep -qF "$begin" "$claude_md"; then
  cp -p "$claude_md" "$claude_md.bak-harnessoperator-$stamp"
  awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$claude_md" > "$tmp"
  mv "$tmp" "$claude_md"; say "compact instructions removed from $claude_md"
fi

echo "Done. Your checkpoints are still in $claude/checkpoints/ (delete that folder to remove them)."
