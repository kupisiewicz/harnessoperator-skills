#!/usr/bin/env bash
# Installs harnessoperator-skills into ~/.claude (user scope, all projects):
#   commands/*.md                   -> ~/.claude/commands/
#   hooks/checkpoint.sh             -> ~/.claude/hooks/harnessoperator/checkpoint.sh
#   hooks/evidence-gate.sh          -> ~/.claude/hooks/harnessoperator/evidence-gate.sh (Stop)
#   hooks/brief-guard.sh            -> ~/.claude/hooks/harnessoperator/brief-guard.sh (PreToolUse)
#   scripts/*.sh                    -> ~/.claude/hooks/harnessoperator/ (helpers the commands run)
#   hook wiring                     -> ~/.claude/settings.json (merged, never replaced)
#   compact/compact-instructions.md -> ~/.claude/CLAUDE.md (between marker comments)
# Safe to run again: it updates in place and never duplicates anything. Every file it
# changes is backed up first as <file>.bak-harnessoperator-<timestamp>.
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd)
claude="$HOME/.claude"
hook="$claude/hooks/harnessoperator/checkpoint.sh"
gate="$claude/hooks/harnessoperator/evidence-gate.sh"
guard="$claude/hooks/harnessoperator/brief-guard.sh"
settings="$claude/settings.json"
claude_md="$claude/CLAUDE.md"
stamp=$(date +%Y%m%d-%H%M%S)
begin='<!-- harnessoperator:compact-instructions:begin -->'
end='<!-- harnessoperator:compact-instructions:end -->'

say()    { printf '  %s\n' "$*"; }
backup() { [ -s "$1" ] && cp -p "$1" "$1.bak-harnessoperator-$stamp" && say "backup: $1.bak-harnessoperator-$stamp"; return 0; }

command -v jq >/dev/null || { echo "jq is required (brew install jq / apt install jq)." >&2; exit 1; }
# A broken settings.json silently disables every setting in it, so never write over one.
if [ -f "$settings" ] && ! jq empty "$settings" 2>/dev/null; then
  echo "$settings is not valid JSON. Fix it first; nothing was changed." >&2; exit 1
fi

echo "Installing harnessoperator-skills into $claude"
mkdir -p "$claude/commands" "$(dirname "$hook")"

# 1. Commands. A different file with the same name is someone else's: back it up.
for f in "$repo"/commands/*.md; do
  dest="$claude/commands/$(basename "$f")"
  if [ -f "$dest" ] && ! cmp -s "$f" "$dest"; then backup "$dest"; fi
  cp "$f" "$dest"; say "command: /$(basename "$f" .md)"
done

# 2. Hook script, plus the helper scripts commands call (they live beside the hook).
cp "$repo/hooks/checkpoint.sh" "$hook"; chmod +x "$hook"; say "hook: $hook"
cp "$repo/hooks/evidence-gate.sh" "$gate"; chmod +x "$gate"; say "hook: $gate"
cp "$repo/hooks/brief-guard.sh" "$guard"; chmod +x "$guard"; say "hook: $guard"
for f in "$repo"/scripts/*.sh; do
  cp "$f" "$(dirname "$hook")/"; chmod +x "$(dirname "$hook")/$(basename "$f")"; say "helper: $(basename "$f")"
done
# Where this came from: /doctor compares the installed copies with it, and /cure
# re-runs this installer from it.
printf '%s\n' "$repo" > "$(dirname "$hook")/source"

# 3. Wiring. Drop any earlier entry that runs our hook, then add one per event, so
#    re-running never duplicates. Other hooks in the file are left untouched.
backup "$settings"
[ -f "$settings" ] || echo '{}' > "$settings"
tmp=$(mktemp)
jq --arg cmd "$hook" --arg gate "$gate" --arg guard "$guard" '
  def wire($event; $matcher; $timeout; $c):
    .hooks[$event] = (
      ((.hooks[$event] // [])
        | map(.hooks |= map(select(.command != $c)))
        | map(select((.hooks | length) > 0)))
      + [ ({hooks: [{type: "command", command: $c, timeout: $timeout}]}
           + (if $matcher then {matcher: $matcher} else {} end)) ]);
  .hooks //= {}
  | wire("PreCompact";   null;              30; $cmd)
  | wire("PostCompact";  null;              30; $cmd)
  | wire("SessionStart"; "compact|startup"; 10; $cmd)
  | wire("Stop";         null;              10; $gate)
  | wire("PreToolUse";   "Edit|Write|MultiEdit|NotebookEdit|mcp__.*ctx_patch"; 10; $guard)
' "$settings" > "$tmp" && mv "$tmp" "$settings"
say "hooks: PreCompact, PostCompact, SessionStart (compact|startup), Stop (evidence gate), PreToolUse (brief guard) in $settings"

# 4. Compact instructions. Replace our own marked block; never touch a hand-written one.
touch "$claude_md"
if grep -qF "$begin" "$claude_md"; then
  backup "$claude_md"
  awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$claude_md" > "$tmp"
  mv "$tmp" "$claude_md"
elif grep -q '^## Compact instructions' "$claude_md"; then
  say "SKIPPED compact instructions: $claude_md already has its own '## Compact instructions'."
  say "Merge $repo/compact/compact-instructions.md into it by hand."
  claude_md=""
else
  backup "$claude_md"
fi
if [ -n "$claude_md" ]; then
  # One blank line before the block, and never a growing run of them on re-install.
  { [ -n "$(tail -n 1 "$claude_md")" ] && echo; echo "$begin"; cat "$repo/compact/compact-instructions.md"; echo "$end"; } >> "$claude_md"
  say "compact instructions: $claude_md"
fi

echo "Done. Start a new Claude Code session so the hooks load. Checkpoints go to $claude/checkpoints/"
