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
pslug=$(printf '%s' "$(cd "$sandbox" && pwd -P)" | sed 's#[^A-Za-z0-9]#-#g')
check "missing cwd in payload: falls back to PWD" '[ -f "$sandbox/.claude/checkpoints/$pslug/latest.md" ]'

# --- repo subfolder keys by repo root -----------------------------------------
repo="$sandbox/repo"; mkdir -p "$repo/sub/deep"; git -C "$repo" init -q
rroot=$(git -C "$repo" rev-parse --show-toplevel)   # resolves symlinked temp dirs like the hook
rslug=$(printf '%s' "$rroot" | sed 's#[^A-Za-z0-9]#-#g')
jq -nc --arg c "$repo/sub/deep" '{hook_event_name:"PostCompact",session_id:"s5",cwd:$c,compact_summary:"x"}' | run >/dev/null
check "cwd in repo subfolder: checkpoint lands in repo-root folder" '[ -f "$sandbox/.claude/checkpoints/$rslug/latest.md" ]'
check "cwd in repo subfolder: no subfolder-slug folder" '! find "$sandbox/.claude/checkpoints" -maxdepth 1 -name "*-sub-deep" | grep -q .'

# --- umbrella folder: checkpoints go to the project the session worked on ---------
# A non-repo folder holding several projects. The transcript touches beta most (one of
# them a repo), alpha once, and a loose file at the top that must never win.
umb=$(cd "$sandbox" && pwd)/umbrella; mkdir -p "$umb/alpha" "$umb/beta/src"; git -C "$umb/beta" init -q
: > "$umb/notes.md"
broot=$(git -C "$umb/beta" rev-parse --show-toplevel); bslug=$(printf '%s' "$broot" | sed 's#[^A-Za-z0-9]#-#g')
uslug=$(printf '%s' "$(cd "$umb" && pwd -P)" | sed 's#[^A-Za-z0-9]#-#g')
ut="$sandbox/umbrella.jsonl"
{ for f in notes.md notes.md notes.md notes.md; do jq -nc --arg p "$umb/$f" '{type:"assistant",cwd:"/elsewhere",message:{content:[{type:"tool_use",input:{file_path:$p}}]}}'; done
  jq -nc --arg p "$umb/alpha/a.js" '{type:"assistant",message:{content:[{type:"tool_use",input:{file_path:$p}}]}}'
  jq -nc --arg c "$umb/beta/src" '{type:"user",cwd:$c,message:{content:"hi"}}'
  jq -nc --arg p "$umb/beta/src/b.js" '{type:"assistant",message:{content:[{type:"tool_use",input:{file_path:$p}}]}}'
  echo 'not json'; } > "$ut"
uev() { jq -nc --arg e "$1" --arg s "$2" --arg c "$umb" --arg t "$3" --arg m "$full_u" '{hook_event_name:$e,source:"compact",session_id:$s,cwd:$c,transcript_path:$t,compact_summary:$m}'; }
full_u=$'In progress\nNot started\nState of the world\nResume here'
uev PreCompact u1 "$ut" | run; uev PostCompact u1 "$ut" | run >/dev/null
check "umbrella: transcript saved under busiest project (repo root)" '[ -f "$sandbox/.claude/checkpoints/$bslug/u1.transcript.jsonl" ]'
check "umbrella: summary saved beside it, not in umbrella folder" '[ -f "$sandbox/.claude/checkpoints/$bslug/latest.md" ] && [ ! -d "$sandbox/.claude/checkpoints/$uslug" ]'
out=$(uev SessionStart u1 "$ut" | run)
check "umbrella: compact SessionStart finds own checkpoint in project folder" 'ctx "$out" | grep -qF -- "$bslug/" && ctx "$out" | grep -qF "u1.transcript.jsonl"'
out=$(uev SessionStart u2 "$ut" | jq -c '.source="startup"' | run)
check "umbrella: startup lists project checkpoints inside it" 'ctx "$out" | grep -qF -- "$bslug/latest.md"'
# Hidden folders: .claude (config, no repo) is touched most but must not win; .wt is a
# worktree container, so the repo inside it wins over alpha.
mkdir -p "$umb/.claude/memory" "$umb/.wt/feat"; git -C "$umb/.wt/feat" init -q
froot=$(git -C "$umb/.wt/feat" rev-parse --show-toplevel); fslug=$(printf '%s' "$froot" | sed 's#[^A-Za-z0-9]#-#g')
ht="$sandbox/hidden.jsonl"
{ for f in .claude/memory/a.md .claude/memory/b.md .claude/x .claude/y .wt/feat/1 .wt/feat/2 alpha/1; do
    jq -nc --arg p "$umb/$f" '{type:"assistant",message:{content:[{type:"tool_use",input:{file_path:$p}}]}}'; done; } > "$ht"
uev PreCompact h1 "$ht" | run
check "umbrella: hidden config folder skipped, repo inside worktree container wins" '[ -f "$sandbox/.claude/checkpoints/$fslug/h1.transcript.jsonl" ]'
printf '{"type":"user","message":"x"}\n' > "$sandbox/empty.jsonl"
uev PostCompact u3 "$sandbox/empty.jsonl" | run >/dev/null
check "umbrella: no project in transcript -> falls back to umbrella folder" '[ -f "$sandbox/.claude/checkpoints/$uslug/latest.md" ]'

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
check "install: commands installed" '[ -f "$C/commands/checkpoint.md" ] && [ -f "$C/commands/summary.md" ] && [ -f "$C/commands/swarm.md" ] && [ -f "$C/commands/context-audit.md" ] && [ -f "$C/commands/docompact.md" ]'
check "install: helper scripts beside the hook, executable" '[ -x "$(dirname "$IH")/context-inventory.sh" ] && [ -x "$(dirname "$IH")/compact-check.sh" ]'
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
check "uninstall: hook, helper and commands removed" '[ ! -e "$IH" ] && [ ! -e "$(dirname "$IH")" ] && [ ! -e "$C/commands/checkpoint.md" ] && [ ! -e "$C/commands/summary.md" ] && [ ! -e "$C/commands/swarm.md" ] && [ ! -e "$C/commands/context-audit.md" ] && [ ! -e "$C/commands/docompact.md" ]'
check "uninstall: compact block removed, own content kept" '! grep -q harnessoperator "$C/CLAUDE.md" && grep -q "keep me" "$C/CLAUDE.md"'
check "uninstall: checkpoints kept" '[ -f "$C/checkpoints/x/latest.md" ]'

# --- context inventory (/context-audit's script) ------------------------------------
INV="$REPO/scripts/context-inventory.sh"
check "context-inventory.sh: executable, bash -n" '[ -x "$INV" ] && bash -n "$INV"'
ca="$sandbox/ctx"; mkdir -p "$ca/mem"
printf 'Rules\nKeep `<br>` as an example.\nOops </strong></p> left over.\nKey file: /Users/nobody-ho-test/gone.env\n```\n/Users/nobody/in-a-fence\n```\nAPI LIVE 2020-01-02 on the box.\n' "$ca" > "$ca/CLAUDE.md"
printf 'short file, loaded in full\n' > "$ca/RULES.md"
printf -- '- [A](a.md) — ok\n- [B](b.md) — missing\n' > "$ca/mem/MEMORY.md"
# a.md is a topic file: it links one note by [[name]] and one by (file.md), so both are
# reachable one hop from the index; orphan.md is reachable from nowhere.
printf 'See [[hub-note]] and [sub](sub.md).\n' > "$ca/mem/a.md"
: > "$ca/mem/hub-note.md"; : > "$ca/mem/sub.md"; : > "$ca/mem/orphan.md"
cut=$(head -c 20 "$ca/CLAUDE.md")
jq -nc --arg p1 "$ca/CLAUDE.md" --arg c1 "$cut" --arg p2 "$ca/RULES.md" --rawfile c2 "$ca/RULES.md" --arg p3 "$ca/mem/MEMORY.md" --rawfile c3 "$ca/mem/MEMORY.md" '
  {timestamp:"2026-01-01T00:00:00Z", attachment:{type:"instructions", files:[
    {path:$p1, type:"User", content:$c1}, {path:$p2, type:"Project", content:$c2}, {path:$p3, type:"AutoMem", content:$c3}]}},
  {attachment:{type:"hook_additional_context", hookName:"SessionStart", content:["0123456789"]}},
  {attachment:{type:"skill_listing", skillCount:3, content:("- tiny\n- big: " + ("y" * 390) + "\n  second line of big\n- mid: abc")}},
  {attachment:{type:"mcp_instructions_delta", addedBlocks:["## srv-one\nbe nice"]}},
  {attachment:{type:"output_style_instructions", style:{name:"Terse", prompt:"short"}}}' > "$ca/t.jsonl"
echo 'not json' >> "$ca/t.jsonl"
inv=$(HOME="$sandbox" "$SH" "$INV" "$ca/t.jsonl" 2>&1); rc=$?
check "inventory: rc=0 on a transcript with junk lines" '[ $rc -eq 0 ]'
check "inventory: every source in the table" 'for s in "$ca/CLAUDE.md" "$ca/RULES.md" "skill listing (3 skills)" "MCP instructions: srv-one" "output style: Terse" "| hook | SessionStart"; do grep -qF -- "$s" <<<"$inv" || exit 1; done'
check "inventory: biggest item first" '[ "$(grep -m1 -E "^\| [0-9]+ \|" <<<"$inv" | cut -d"|" -f4 | tr -d " ")" = skills ]'
check "inventory: 7 rows, total is their sum" '[ "$(grep -cE "^\| [0-9]+ \|" <<<"$inv")" = 7 ] && [ "$(grep -F "total measured" <<<"$inv" | cut -d"|" -f3 | tr -d " *")" = "$(grep -E "^\| [0-9]+ \|" <<<"$inv" | cut -d"|" -f3 | awk "{s+=\$1} END{print s}")" ]'
check "inventory: prefix-only copy reported TRUNCATED" 'grep -qF "TRUNCATED: $ca/CLAUDE.md" <<<"$inv"'
check "inventory: full copy (minus final newline) is ok" 'grep -qF "ok: $ca/RULES.md" <<<"$inv"'
check "inventory: memory link to missing file found" 'grep -A1 "links to missing files: 1" <<<"$inv" | grep -qF b.md'
check "inventory: unreachable memory file found" 'grep -A1 "unreachable (not in the index, not one link away): 1" <<<"$inv" | grep -qF orphan.md'
check "inventory: notes one link away counted fine, not listed" 'grep -qF "linked from a topic file it links (fine): 2" <<<"$inv" && ! grep -qE "^  - (hub-note|sub)\.md" <<<"$inv"'
check "inventory: dead path in prose found" 'grep -qF "/Users/nobody-ho-test/gone.env" <<<"$inv"'
check "inventory: path inside a code fence ignored" '! grep -qF "in-a-fence" <<<"$inv"'
check "inventory: stray HTML found, <br> in backticks ignored" 'grep -qF "</strong></p>" <<<"$inv" && ! grep -F "CLAUDE.md:" <<<"$inv" | grep -qF "<br>"'
check "inventory: old dated LIVE claim found" 'grep -qF "LIVE 2020-01-02" <<<"$inv"'
check "inventory: skill entries ranked, multi-line entry counted whole" 'grep -A4 "Skill listing — largest" <<<"$inv" | grep -qF "3 entries" && [ "$(grep -m1 -E "^- (big|mid|tiny) —" <<<"$inv")" = "- big — 418 chars (≈105 tokens)" ]'
( cd "$sandbox" && HOME="$sandbox/nohome" "$SH" "$INV" >/dev/null 2>&1 ); rc=$?
check "inventory: no transcript -> clear error, rc!=0" '[ $rc -ne 0 ]'
check "/context-audit runs the installed script and gates edits on approval" "grep -qF 'hooks/harnessoperator/context-inventory.sh' \"$CMDS/context-audit.md\" && grep -qi 'only after the user' \"$CMDS/context-audit.md\""

# --- compact check (/docompact's script) ---------------------------------------------
CC="$REPO/scripts/compact-check.sh"
check "compact-check.sh: executable, bash -n" '[ -x "$CC" ] && bash -n "$CC"'
cc="$sandbox/cc"; mkdir -p "$cc"; git init -q "$cc/repo"; : > "$cc/repo/edited.txt"
ccroot=$(git -C "$cc/repo" rev-parse --show-toplevel)   # symlink-free, as the script keys it
ccdir="$sandbox/.claude/checkpoints/$(printf '%s' "$ccroot" | sed 's#[^A-Za-z0-9]#-#g')"
mkdir -p "$ccdir"; echo cp > "$ccdir/CHECKPOINT.md"
# usage <input> <cache_read> <cache_creation> [sidechain]: one assistant entry.
usage() { jq -nc --argjson i "$1" --argjson r "$2" --argjson c "$3" --argjson s "${4:-false}" --arg f "$cc/repo/edited.txt" '
  {type:"assistant", isSidechain:$s, message:{model:"claude-test-1", usage:{input_tokens:$i, cache_read_input_tokens:$r, cache_creation_input_tokens:$c, output_tokens:999999},
   content:[{type:"tool_use", name:"Edit", input:{file_path:$f}}]}}'; }
{ usage 5 90000 5000; echo 'not json'; echo 42; printf '{"type":"user","message":"hello"}\n'
  usage 2 140000 1998; usage 1 3000 0 true; } > "$cc/t.jsonl"
ccrun() { ( cd "$sandbox" && HOME="$sandbox" "$SH" "$CC" "$@" 2>&1 ); }
out=$(ccrun "$cc/t.jsonl"); rc=$?
check "compact-check: rc=0 on a transcript with junk lines" '[ $rc -eq 0 ]'
check "compact-check: size = last main-thread usage (input + cache read + cache creation), output and sidechain ignored" 'grep -qF "context: 142000 of 200000 tokens (71%)" <<<"$out"'
check "compact-check: 200k window is stated as an assumption" 'grep -qE "^window: 200000 — ASSUMED" <<<"$out"'
check "compact-check: 71% -> soon" 'grep -qE "^should compact: soon" <<<"$out"'
check "compact-check: touched repo listed with uncommitted count and no remote" 'grep -qF -- "- $ccroot — branch " <<<"$out" && grep -F -- "- $ccroot" <<<"$out" | grep -qF "1 uncommitted files, no remote"'
check "compact-check: checkpoint of a touched repo found, with age" 'grep -qE "CHECKPOINT\.md \([0-9]+[smhd] old\)" <<<"$out"'
check "compact-check: never prints message content" '! grep -qF hello <<<"$out"'
out=$(HO_CONTEXT_WINDOW=1000000 ccrun "$cc/t.jsonl")
check "compact-check: HO_CONTEXT_WINDOW overrides the window (14% -> no)" 'grep -qF "of 1000000 tokens (14%)" <<<"$out" && grep -qE "^should compact: no" <<<"$out" && grep -qF "set by HO_CONTEXT_WINDOW" <<<"$out"'
usage 10 250000 0 > "$cc/big.jsonl"
out=$(ccrun "$cc/big.jsonl")
check "compact-check: past 200k -> 1M window inferred" 'grep -qF "250010 of 1000000 tokens (25%)" <<<"$out" && grep -qF "inferred" <<<"$out"'
usage 0 160000 0 > "$cc/full.jsonl"
check "compact-check: 80% -> yes" 'ccrun "$cc/full.jsonl" | grep -qE "^should compact: yes"'
printf '{"type":"user","message":"hello"}\nnot json\n' > "$cc/nousage.jsonl"
out=$(ccrun "$cc/nousage.jsonl"); rc=$?
check "compact-check: transcript without usage -> clear message, rc=2" '[ $rc -eq 2 ] && grep -q "cannot be measured" <<<"$out"'
out=$(ccrun "$cc/missing.jsonl"); rc=$?
check "compact-check: missing transcript -> clear message, rc=1" '[ $rc -eq 1 ] && grep -q "No session transcript" <<<"$out"'
# Two sessions in one project folder: the session id must win over "newest file".
pj="$sandbox/.claude/projects/-some-project"; mkdir -p "$pj"
cp "$cc/t.jsonl" "$pj/mine.jsonl"; sleep 1; cp "$cc/big.jsonl" "$pj/neighbour.jsonl"
out=$(CLAUDE_CODE_SESSION_ID=mine ccrun)
check "compact-check: picks this session's transcript by CLAUDE_CODE_SESSION_ID, not the newest" 'grep -qF "mine.jsonl" <<<"$out" && grep -qF "142000 of" <<<"$out"'
check "/docompact runs the installed script, stays read-only and fixes the verdict shape" "grep -qF 'hooks/harnessoperator/compact-check.sh' \"$CMDS/docompact.md\" && grep -qi 'never start a compaction' \"$CMDS/docompact.md\" && grep -q '^COMPACT: ' \"$CMDS/docompact.md\" && grep -q '^SAFE NOW: ' \"$CMDS/docompact.md\""

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
# /swarm: every row of the mix table must match the formula printed above it.
swarm_ok=1; swarm_rows=0
while IFS='|' read -r _ n s o f _; do
  n=$((n)); s=$((s)); o=$((o)); f=$((f)); swarm_rows=$((swarm_rows+1))
  if [ "$n" -lt 7 ]; then ef=0; else ef=$(( (n+9)/10 )); fi
  w=$((n-ef)); es=$(( (4*w+3)/6 ))   # round(2w/3) in integer maths
  if [ "$s/$o/$f" != "$es/$((w-es))/$ef" ]; then
    swarm_ok=0; echo "  /swarm N=$n: table $s/$o/$f, formula $es/$((w-es))/$ef"
  fi
done < <(grep -E '^\| [0-9]+ \|' "$CMDS/swarm.md")
check "/swarm mix table matches its formula ($swarm_rows rows)" '[ $swarm_ok = 1 ] && [ $swarm_rows -ge 10 ]'
check "/swarm passes \$ARGUMENTS and pins the reviewer model" "grep -qF '\$ARGUMENTS' \"$CMDS/swarm.md\" && grep -qF 'model: \"fable\"' \"$CMDS/swarm.md\""

for s in "In progress" "Not started" "State of the world" "Resume here"; do
  check "hook's required section '$s' is named in compact instructions" "grep -qF '$s' \"$REPO/compact/compact-instructions.md\" && grep -qF '\"$s\"' \"$HOOK\""
done

echo; echo "passed $pass, failed $fail"
[ $fail -eq 0 ]
