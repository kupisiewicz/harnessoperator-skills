#!/usr/bin/env bash
# Black-box tests for hooks/checkpoint.sh, install.sh, uninstall.sh and the prompts.
# Everything runs with HOME pointed at a temp dir, so your real ~/.claude is never touched.
# Usage: bash tests/test-checkpoint.sh   (exit 0 = all pass). Needs bash, jq, git.

REPO=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$REPO/hooks/checkpoint.sh"
CMDS="$REPO/commands"
SH=${SH:-bash}   # SH=/bin/bash runs everything under macOS's stock bash 3.2
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "PASS  $1"; }
bad()  { fail=$((fail+1)); echo "FAIL  $1${2:+ — $2}"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1" "$3"; fi; }
perm() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }   # GNU, then BSD
inode(){ ls -i "$1" | awk '{print $1}'; }

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
run() { HOME="$sandbox" "$SH" "$HOOK"; }   # stdin = JSON payload
ev()  { jq -nc --arg e "$1" --arg s "$2" --arg c "$cwd" '{hook_event_name:$e,source:"compact",session_id:$s,cwd:$c}'; }
ctx() { jq -r .hookSpecificOutput.additionalContext <<<"$1"; }

cwd="/Volumes/Test Dir/my.project"              # spaces + dots exercise the slug rule
slug=$(printf '%s' "$cwd" | sed 's#[^A-Za-z0-9]#-#g')
dir="$sandbox/.claude/checkpoints/$slug"
transcript="$sandbox/transcript.jsonl"
printf '{"type":"user","message":"hello"}\n' > "$transcript"
post() { jq -nc --arg c "$cwd" --arg s "$1" --arg m "$2" '{hook_event_name:"PostCompact",trigger:"auto",session_id:$s,cwd:$c,compact_summary:$m}' | run; }

# --- basics -------------------------------------------------------------------
for f in "$HOOK" "$REPO/install.sh" "$REPO/uninstall.sh"; do
  check "$(basename "$f"): executable" '[ -x "$f" ]'
  check "$(basename "$f"): bash -n syntax" 'bash -n "$f"'
done

# --- no junk folders, silent start ------------------------------------------
out=$(ev SessionStart s1 | run); rc=$?
check "SessionStart w/o checkpoint: rc=0, no output" '[ $rc -eq 0 ] && [ -z "$out" ]'
echo '{"hook_event_name":"Stop","cwd":"/junk/a"}' | run; echo 'not json' | run 2>/dev/null; rc=$?
check "garbage stdin: rc=0 (never blocks compaction)" '[ $rc -eq 0 ]'
check "unknown event / garbage / SessionStart create no folders" '[ ! -d "$sandbox/.claude/checkpoints" ]'

# --- PreCompact: one hardlinked transcript per session ------------------------
for i in 1 2; do
  printf '{"n":%d}\n' $i >> "$transcript"
  jq -nc --arg c "$cwd" --arg t "$transcript" '{hook_event_name:"PreCompact",session_id:"s1",cwd:$c,transcript_path:$t}' | run
done
check "PreCompact: transcript saved as <session>.transcript.jsonl" '[ -f "$dir/s1.transcript.jsonl" ]'
check "PreCompact: two compacts -> still one file per session" '[ $(ls "$dir"/*.transcript.jsonl | wc -l) -eq 1 ]'
check "PreCompact: hardlink, no extra disk (same inode)" '[ "$(inode "$transcript")" = "$(inode "$dir/s1.transcript.jsonl")" ]'
check "PreCompact: content identical" 'cmp -s "$transcript" "$dir/s1.transcript.jsonl"'
jq -nc --arg c "$cwd" '{hook_event_name:"PreCompact",session_id:"s2",cwd:$c,transcript_path:"/nonexistent.jsonl"}' | run; rc=$?
check "PreCompact missing transcript: rc=0" '[ $rc -eq 0 ]'
jq -nc --arg c "$cwd" --arg t "$transcript" '{hook_event_name:"PreCompact",session_id:"../../evil",cwd:$c,transcript_path:$t}' | run
check "PreCompact: session id cannot escape the folder (../)" '[ -f "$dir/evil.transcript.jsonl" ] && [ ! -e "$sandbox/.claude/evil.transcript.jsonl" ]'
rm -f "$dir/evil.transcript.jsonl"

# --- PostCompact --------------------------------------------------------------
summary=$'<analysis>\nSCRATCH thoughts\n</analysis>\n\n<summary>\n## Goal\nline with "quotes", $dollar and `ticks`\n</summary>'
post s1 "$summary"; rc=$?
dated=$(ls -t "$dir"/*_s1.md | head -1)
check "PostCompact: rc=0, latest.md written" '[ $rc -eq 0 ] && [ -f "$dir/latest.md" ]'
check "PostCompact: special chars survive verbatim" 'grep -qF "line with \"quotes\", \$dollar and \`ticks\`" "$dir/latest.md"'
check "PostCompact: <analysis> stripped from latest.md" '! grep -q SCRATCH "$dir/latest.md"'
check "PostCompact: <analysis> kept in dated file" 'grep -q SCRATCH "$dated"'
check "PostCompact: trigger recorded in header" 'grep -q "trigger: auto" "$dir/latest.md"'
sleep 1
jq -nc --arg c "$cwd" '{hook_event_name:"PostCompact",session_id:"s3",cwd:$c,weird_field:"x"}' | run >/dev/null
check "PostCompact no summary: marked EMPTY, keys listed" 'grep -q "EMPTY SUMMARY" "$dir/latest.md" && grep -q weird_field "$dir/latest.md"'

# --- SessionStart is session-aware --------------------------------------------
# s3 compacted last (latest.md is s3's); s1 must still be pointed at its own file.
out=$(ev SessionStart s1 | run)
check "SessionStart: emits valid JSON, hookEventName=SessionStart" '[ "$(jq -r .hookSpecificOutput.hookEventName <<<"$out" 2>/dev/null)" = SessionStart ]'
check "SessionStart: two sessions -> points at OWN checkpoint" 'ctx "$out" | grep -qF "$dated"'
check "SessionStart: points at own transcript" 'ctx "$out" | grep -qF "$dir/s1.transcript.jsonl"'
check "SessionStart: no CHECKPOINT.md -> not mentioned" '! ctx "$out" | grep -q "CHECKPOINT.md"'
echo "# manual" > "$dir/CHECKPOINT.md"
out=$(ev SessionStart s1 | run)
check "SessionStart: manual CHECKPOINT.md mentioned" 'ctx "$out" | grep -qF "$dir/CHECKPOINT.md"'
rm "$dir"/*.md; echo "# manual" > "$dir/CHECKPOINT.md"
out=$(ev SessionStart s9 | run)
check "SessionStart: only CHECKPOINT.md -> still not silent" 'ctx "$out" | grep -qF "CHECKPOINT.md"'

# --- cwd fallback -------------------------------------------------------------
( cd "$sandbox" && jq -nc '{hook_event_name:"PostCompact",session_id:"s4",compact_summary:"x"}' | HOME="$sandbox" "$SH" "$HOOK" >/dev/null )
pslug=$(printf '%s' "$(cd "$sandbox" && pwd)" | sed 's#[^A-Za-z0-9]#-#g')
check "missing cwd in payload: falls back to PWD" '[ -f "$sandbox/.claude/checkpoints/$pslug/latest.md" ]'

# --- repo subfolder keys by repo root -----------------------------------------
repo="$sandbox/repo"; mkdir -p "$repo/sub/deep"; git -C "$repo" init -q
rroot=$(git -C "$repo" rev-parse --show-toplevel)   # resolves symlinked temp dirs like the hook
rslug=$(printf '%s' "$rroot" | sed 's#[^A-Za-z0-9]#-#g')
jq -nc --arg c "$repo/sub/deep" '{hook_event_name:"PostCompact",session_id:"s5",cwd:$c,compact_summary:"x"}' | run >/dev/null
check "cwd in repo subfolder: checkpoint lands in repo-root folder" '[ -f "$sandbox/.claude/checkpoints/$rslug/latest.md" ]'
check "cwd in repo subfolder: no subfolder-slug folder" '! find "$sandbox/.claude/checkpoints" -maxdepth 1 -name "*-sub-deep" | grep -q .'

# --- compliance check ---------------------------------------------------------
cwd="/Volumes/Test Dir/compliance"; dir="$sandbox/.claude/checkpoints/$(printf '%s' "$cwd" | sed 's#[^A-Za-z0-9]#-#g')"
out=$(post s6 $'## Goal\nx\n## Resume here\n1. y')
check "summary missing sections: latest.md marked INCOMPLETE, names them" 'grep -q "^INCOMPLETE.*In progress, Not started, State of the world" "$dir/latest.md"'
check "summary missing sections: systemMessage warns user" 'jq -e ".systemMessage|test(\"missing\")" <<<"$out" >/dev/null'
out=$(post s6 $'In progress: None\nNot started: None\nState of the world: clean\nResume here: 1.')
check "complete summary: no INCOMPLETE, no warning" '! grep -q INCOMPLETE "$dir/latest.md" && [ -z "$out" ]'

# --- retention ----------------------------------------------------------------
full=$'In progress\nNot started\nState of the world\nResume here'
for i in $(seq -w 1 12); do touch -t 2026010100$i "$dir/2026-01-01_0000${i}_old$i.md"; done
: > "$dir/ancient.transcript.jsonl"; touch -t 202001010000 "$dir/ancient.transcript.jsonl"
: > "$dir/fresh.transcript.jsonl"
post s6 "$full" >/dev/null
check "retention: keeps newest 10 dated summaries" '[ $(find "$dir" -name "20*_*.md" | wc -l) -eq 10 ]'
check "retention: newest summary survives" '[ -n "$(find "$dir" -name "*_s6.md")" ]'
check "retention: transcript older than 60 days deleted" '[ ! -e "$dir/ancient.transcript.jsonl" ]'
check "retention: fresh transcript kept" '[ -e "$dir/fresh.transcript.jsonl" ]'
check "retention: latest.md and CHECKPOINT.md never pruned" 'echo m > "$dir/CHECKPOINT.md"; post s6 "$full" >/dev/null; [ -f "$dir/CHECKPOINT.md" ] && [ -f "$dir/latest.md" ]'
jq -nc --arg c "$cwd" --arg m "$full" '{hook_event_name:"PostCompact",session_id:"s7",cwd:$c,compact_summary:$m}' | HO_CHECKPOINT_KEEP=3 HOME="$sandbox" "$SH" "$HOOK"
check "retention: HO_CHECKPOINT_KEEP overrides the limit" '[ $(find "$dir" -name "20*_*.md" | wc -l) -eq 3 ]'

# --- startup pointer ----------------------------------------------------------
st() { jq -nc --arg c "$1" '{hook_event_name:"SessionStart",source:"startup",session_id:"new",cwd:$c}' | run; }
out=$(st "$cwd")
check "startup: points at newest checkpoint with age" 'ctx "$out" | grep -qE "Last work checkpoint .*(CHECKPOINT|latest)\.md \([0-9]+[hd] old\)"'
check "startup: does not tell model to load it" 'ctx "$out" | grep -q "only if"'
out=$(st "/Volumes/Test Dir/never-compacted")
check "startup without checkpoint: silent, no folder" '[ -z "$out" ] && [ ! -d "$sandbox/.claude/checkpoints/-Volumes-Test-Dir-never-compacted" ]'

# --- privacy ------------------------------------------------------------------
check "privacy: checkpoint folder is owner-only (700)" '[ "$(perm "$dir")" = 700 ]'
check "privacy: latest.md is owner-only (600)" '[ "$(perm "$dir/latest.md")" = 600 ]'

# --- install.sh / uninstall.sh ------------------------------------------------
ih="$sandbox/ihome"; C="$ih/.claude"; mkdir -p "$C"
S="$C/settings.json"; IH="$C/hooks/harnessoperator/checkpoint.sh"
echo '{"model":"keep","hooks":{"SessionStart":[{"matcher":".*","hooks":[{"type":"command","command":"other-tool"}]}]}}' > "$S"
printf '# My rules\nkeep me\n' > "$C/CLAUDE.md"
inst() { HOME="$1" "$SH" "$REPO/install.sh" >/dev/null 2>&1; }
inst "$ih"; inst "$ih"; cp "$C/CLAUDE.md" "$sandbox/md2"; inst "$ih"
count() { jq --arg c "$IH" "[.hooks.$1[]?.hooks[] | select(.command==\$c)] | length" "$S"; }
check "install: hook installed and executable" '[ -x "$IH" ]'
check "install: commands installed" '[ -f "$C/commands/checkpoint.md" ] && [ -f "$C/commands/summary.md" ]'
for e in PreCompact PostCompact SessionStart; do
  check "install x3: exactly one $e entry (idempotent)" '[ "$(count $e)" = 1 ]'
done
for src in compact startup; do
  check "install: SessionStart matcher covers $src" \
    "jq -e --arg c \"\$IH\" '.hooks.SessionStart[] | select(.matcher as \$m | \"$src\"|test(\"^(\"+\$m+\")\$\")) | .hooks[] | select(.command==\$c)' \"\$S\" >/dev/null"
done
check "install: other hooks and settings preserved" 'jq -e ".model==\"keep\" and ([.hooks.SessionStart[].hooks[].command] | index(\"other-tool\"))" "$S" >/dev/null'
check "install: settings.json backed up" 'ls "$C"/settings.json.bak-harnessoperator-* >/dev/null 2>&1'
check "install: own CLAUDE.md content kept" 'grep -q "keep me" "$C/CLAUDE.md"'
check "install x3: one compact-instructions block" '[ $(grep -c "harnessoperator:compact-instructions:begin" "$C/CLAUDE.md") -eq 1 ]'
check "install: block requires all four headings (matches hook)" 'grep -q "Always write all four headings" "$C/CLAUDE.md"'
check "install: re-install does not grow CLAUDE.md" 'cmp -s "$sandbox/md2" "$C/CLAUDE.md"'

ih2="$sandbox/ihome2"; mkdir -p "$ih2/.claude"; printf '## Compact instructions\nmine\n' > "$ih2/.claude/CLAUDE.md"
inst "$ih2"
check "install: hand-written Compact instructions left alone" '! grep -q harnessoperator "$ih2/.claude/CLAUDE.md" && grep -q mine "$ih2/.claude/CLAUDE.md"'
ih3="$sandbox/ihome3"; mkdir -p "$ih3/.claude"; echo '{broken' > "$ih3/.claude/settings.json"
HOME="$ih3" "$SH" "$REPO/install.sh" >/dev/null 2>&1; rc=$?
check "install: invalid settings.json -> refuses, unchanged" '[ $rc -ne 0 ] && [ "$(cat "$ih3/.claude/settings.json")" = "{broken" ]'

mkdir -p "$C/checkpoints/x"; echo keep > "$C/checkpoints/x/latest.md"
HOME="$ih" "$SH" "$REPO/uninstall.sh" >/dev/null 2>&1
check "uninstall: our hooks removed" '[ "$(count PreCompact)$(count PostCompact)$(count SessionStart)" = 000 ]'
check "uninstall: other hooks and settings kept" 'jq -e ".model==\"keep\" and ([.hooks.SessionStart[].hooks[].command] | index(\"other-tool\"))" "$S" >/dev/null'
check "uninstall: hook and commands removed" '[ ! -e "$IH" ] && [ ! -e "$C/commands/checkpoint.md" ] && [ ! -e "$C/commands/summary.md" ]'
check "uninstall: compact block removed, own content kept" '! grep -q harnessoperator "$C/CLAUDE.md" && grep -q "keep me" "$C/CLAUDE.md"'
check "uninstall: checkpoints kept" '[ -f "$C/checkpoints/x/latest.md" ]'

# --- prompts agree with the hook ----------------------------------------------
check "/summary has an 'all' overview mode" "grep -q 'argument is exactly \`all\`' \"$CMDS/summary.md\""
for f in checkpoint summary; do
  check "/$f uses the hook's slug command" "grep -qF \"sed 's#[^A-Za-z0-9]#-#g'\" \"$CMDS/$f.md\""
  check "/$f keys by repo root (show-toplevel)" "grep -qF -- '--show-toplevel' \"$CMDS/$f.md\""
  check "/$f finds unpushed branches (--not --remotes)" "grep -qF -- '--not --remotes' \"$CMDS/$f.md\""
done
check "/checkpoint writes \$d/CHECKPOINT.md under ~/.claude/checkpoints" "grep -qF '\$d/CHECKPOINT.md' \"$CMDS/checkpoint.md\" && grep -qF 'd=~/.claude/checkpoints/' \"$CMDS/checkpoint.md\""
check "/checkpoint carries forward the previous checkpoint" "grep -qi 'carry forward' \"$CMDS/checkpoint.md\""
check "/summary reads both CHECKPOINT.md and latest.md" "grep -q 'CHECKPOINT.md' \"$CMDS/summary.md\" && grep -q 'latest.md' \"$CMDS/summary.md\""
for s in "In progress" "Not started" "State of the world" "Resume here"; do
  check "hook's required section '$s' is named in compact instructions" "grep -qF '$s' \"$REPO/compact/compact-instructions.md\" && grep -qF '\"$s\"' \"$HOOK\""
done

echo; echo "passed $pass, failed $fail"
[ $fail -eq 0 ]
