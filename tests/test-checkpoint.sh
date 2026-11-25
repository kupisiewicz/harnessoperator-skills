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
check "compact SessionStart: no brief, no brief line" '! ctx "$out" | grep -qF "BRIEF.md"'
printf '# Brief\n' > "$sandbox/.claude/checkpoints/$bslug/BRIEF.md"; out=$(uev SessionStart u1 "$ut" | run)
check "compact SessionStart: names the project's /brief file with its age" 'ctx "$out" | grep -qF -- "$bslug/BRIEF.md (0h old)"'
rm "$sandbox/.claude/checkpoints/$bslug/BRIEF.md"
# Real order seen live: SessionStart compact fires before PostCompact. The umbrella
# folder holds a stranger's latest.md, which must never be named as this session's.
mkdir -p "$sandbox/.claude/checkpoints/$uslug"
printf '# Checkpoint\nsession: stranger · trigger: manual\n' > "$sandbox/.claude/checkpoints/$uslug/latest.md"
uev PreCompact u3 "$ut" | run; out=$(uev SessionStart u3 "$ut" | run)
check "umbrella: SessionStart before PostCompact names own folder + transcript" 'ctx "$out" | grep -qF -- "$bslug/u3.transcript.jsonl" && ctx "$out" | grep -qF "not written yet"'
check "umbrella: never claims another session's latest.md" '! ctx "$out" | grep -qF -- "$uslug/latest.md"'
rm -r "$sandbox/.claude/checkpoints/$uslug"
out=$(uev SessionStart u2 "$ut" | jq -c '.source="startup"' | run)
check "umbrella: startup lists project checkpoints inside it" 'ctx "$out" | grep -qF -- "$bslug/latest.md"'
check "umbrella: one repo below is not a workspace, no project pick" '! ctx "$out" | grep -qF "settle which project"'
mkdir -p "$umb/gamma"; git -C "$umb/gamma" init -q
out=$(uev SessionStart u2 "$ut" | jq -c '.source="startup"' | run)
check "umbrella: two repos -> asks to settle the project, names them" 'ctx "$out" | grep -qF "holds 2 git repos" && ctx "$out" | grep -qF "settle which project" && ctx "$out" | grep -q "recently active: .*beta" && ctx "$out" | grep -q "recently active: .*gamma"'
check "umbrella: hidden folders are never offered as projects" '! ctx "$out" | grep -q "recently active: .*\.wt"'
rm -rf "$umb/gamma"
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
check "install: commands installed" '[ -f "$C/commands/checkpoint.md" ] && [ -f "$C/commands/summary.md" ] && [ -f "$C/commands/swarm.md" ] && [ -f "$C/commands/context-audit.md" ] && [ -f "$C/commands/compact-check.md" ] && [ -f "$C/commands/lesson.md" ] && [ -f "$C/commands/decision.md" ] && [ -f "$C/commands/brief.md" ] && [ -f "$C/commands/doctor.md" ] && [ -f "$C/commands/cure.md" ]'
check "install: helper scripts beside the hook, executable" '[ -x "$(dirname "$IH")/context-inventory.sh" ] && [ -x "$(dirname "$IH")/compact-check.sh" ] && [ -x "$(dirname "$IH")/lesson-search.sh" ] && [ -x "$(dirname "$IH")/decision-log.sh" ] && [ -x "$(dirname "$IH")/lesson-mine.sh" ]'
for e in PreCompact PostCompact SessionStart; do
  check "install x3: exactly one $e entry (idempotent)" '[ "$(count $e)" = 1 ]'
done
IG="$(dirname "$IH")/evidence-gate.sh"
gcount() { jq --arg c "$IG" "[.hooks.$1[]?.hooks[] | select(.command==\$c)] | length" "$S"; }
check "install x3: evidence gate executable, exactly one Stop entry" '[ -x "$IG" ] && [ "$(gcount Stop)" = 1 ] && [ "$(gcount SessionStart)" = 0 ]'
IBG="$(dirname "$IH")/brief-guard.sh"
check "install x3: brief guard executable, one PreToolUse entry matching Edit and Write" \
  '[ -x "$IBG" ] && [ "$(jq --arg c "$IBG" "[.hooks.PreToolUse[]?.hooks[] | select(.command==\$c)] | length" "$S")" = 1 ] && jq -r --arg c "$IBG" ".hooks.PreToolUse[] | select(any(.hooks[]; .command==\$c)) | .matcher" "$S" | grep -q "^Edit|Write|"'
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
check "uninstall: our hooks removed" '[ "$(count PreCompact)$(count PostCompact)$(count SessionStart)$(gcount Stop)" = 0000 ] && [ ! -e "$IG" ] && [ ! -e "$IBG" ] && [ "$(jq "[.hooks.PreToolUse[]?] | length" "$S")" = 0 ]'
check "uninstall: other hooks and settings kept" 'jq -e ".model==\"keep\" and ([.hooks.SessionStart[].hooks[].command] | index(\"other-tool\"))" "$S" >/dev/null'
check "uninstall: hook, helper and commands removed" '[ ! -e "$IH" ] && [ ! -e "$(dirname "$IH")" ] && [ ! -e "$C/commands/checkpoint.md" ] && [ ! -e "$C/commands/summary.md" ] && [ ! -e "$C/commands/swarm.md" ] && [ ! -e "$C/commands/context-audit.md" ] && [ ! -e "$C/commands/compact-check.md" ] && [ ! -e "$C/commands/lesson.md" ] && [ ! -e "$C/commands/decision.md" ] && [ ! -e "$C/commands/brief.md" ] && [ ! -e "$C/commands/cure.md" ]'
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

# --- compact check (/compact-check's script) ---------------------------------------------
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
check "/compact-check runs the installed script, stays read-only and fixes the verdict shape" "grep -qF 'hooks/harnessoperator/compact-check.sh' \"$CMDS/compact-check.md\" && grep -qi 'never start a compaction' \"$CMDS/compact-check.md\" && grep -q '^COMPACT: ' \"$CMDS/compact-check.md\" && grep -q '^SAFE NOW: ' \"$CMDS/compact-check.md\""

# --- lesson search (/lesson's script) ------------------------------------------------
LS="$REPO/scripts/lesson-search.sh"
check "lesson-search.sh: executable, bash -n" '[ -x "$LS" ] && bash -n "$LS"'
lh="$sandbox/lhome"; lp="$sandbox/lproj"; mkdir -p "$lh/.claude" "$lp/sub"; git -C "$lp" init -q
lmem="$lh/.claude/projects/$(printf '%s' "$lp" | sed 's#[^A-Za-z0-9]#-#g')/memory"; mkdir -p "$lmem"
printf '# Global\n- Open the PR and stop.\n@~/.claude/extra.md\nUse `@not-an-import.md` as text.\n' > "$lh/.claude/CLAUDE.md"
printf 'Imported: never force-push main.\n' > "$lh/.claude/extra.md"
printf '# Project\n- Run the tests before a PR.\n' > "$lp/CLAUDE.md"
printf -- '- [Merge rule](merge-rule.md) — open the PR, never merge\n' > "$lmem/MEMORY.md"
printf -- '---\nname: merge-rule\ndescription: open the PR, never merge it\nmetadata:\n  type: feedback\n---\n\n**Never merge.** The PR stays open.\n' > "$lmem/merge-rule.md"
printf -- '---\nname: history\ndescription: what shipped in March\nmetadata:\n  type: project\n---\n\nPR #4 merged; the PR is closed.\n' > "$lmem/history.md"
lout=$(cd "$lp/sub" && HOME="$lh" "$SH" "$LS" PR force-push 2>&1); rc=$?
check "lesson-search: rc=0, lists all three homes" '[ $rc -eq 0 ] && grep -qF "global (every project): $lh/.claude/CLAUDE.md" <<<"$lout" && grep -qF "this repo (committed" <<<"$lout" && grep -qF "auto memory (this machine only): $lmem/" <<<"$lout"'
check "lesson-search: finds the rule in the global file and the project file" 'grep -qF "$lh/.claude/CLAUDE.md:2:- Open the PR" <<<"$lout" && grep -qF "$lp/CLAUDE.md:2:- Run the tests before a PR" <<<"$lout"'
check "lesson-search: follows an @import, not one inside a code span" 'grep -qF "extra.md:1:Imported: never force-push" <<<"$lout" && ! grep -qF "not-an-import" <<<"$lout"'
check "lesson-search: memory index and feedback notes searched in full" 'grep -qF "MEMORY.md:1:" <<<"$lout" && grep -qF "merge-rule.md:8:**Never merge.**" <<<"$lout"'
check "lesson-search: project notes match only by description, not history" 'grep -c "history.md" <<<"$lout" | grep -qx 0'
lout=$(cd "$lp" && HOME="$lh" "$SH" "$LS" zebra 2>&1)
check "lesson-search: no match says so" 'grep -qF "none: nothing written down mentions these words yet" <<<"$lout"'
( cd "$lp" && HOME="$lh" "$SH" "$LS" >/dev/null 2>&1 ); rc=$?
check "lesson-search: no keyword -> usage, rc!=0" '[ $rc -ne 0 ]'
check "/lesson runs the installed script, never strengthens the user's words, asks on conflict" "grep -qF 'hooks/harnessoperator/lesson-search.sh' \"$CMDS/lesson.md\" && grep -qi 'never strengthen' \"$CMDS/lesson.md\" && grep -qi 'contradicting rule' \"$CMDS/lesson.md\""

# --- lesson mining (/lesson mine's script) -------------------------------------------
LM="$REPO/scripts/lesson-mine.sh"
check "lesson-mine.sh: executable, bash -n" '[ -x "$LM" ] && bash -n "$LM"'
ltd="$lh/.claude/projects/$(printf '%s' "$lp" | sed 's#[^A-Za-z0-9]#-#g')"; mkdir -p "$ltd"
la() { jq -nc --arg t "$1" '{type:"assistant",sessionId:"sess1234x",message:{content:[{type:"text",text:$t}]}}'; }
lu() { jq -nc --arg t "$1" --arg ts "$2" '{type:"user",sessionId:"sess1234x",timestamp:$ts,message:{content:$t}}'; }
{ la "I installed it with npm."; lu "No, I told you to use bun in this repo." "2026-11-20T10:00:00Z"
  la "Shall I deploy it now?"; lu "No need" "2026-11-20T10:05:00Z"
  lu "Stop" "2026-11-20T10:06:00Z"
  jq -nc '{type:"user",isMeta:true,message:{content:"Stop hook feedback: never claim that"}}'
  jq -nc '{type:"user",message:{content:[{type:"tool_result",content:"you forgot again! never"}]}}'
  jq -nc '{type:"user",origin:{kind:"task-notification"},message:{content:"agent says: never do X, I told you"}}'
  lu "Task (from the session that started this one): never merge, I told you" "2026-11-20T10:07:00Z"
  jq -nc '{type:"user",isSidechain:true,message:{content:"No, I told you already"}}'
  echo 'not json'; } > "$ltd/s1.jsonl"
cp "$ltd/s1.jsonl" "$ltd/s1-fork.jsonl"   # a forked session carries the same messages
lu "Why did you delete it? I told you to keep it." "2020-01-01T00:00:00Z" > "$ltd/s0.jsonl"; touch -t 202001010000 "$ltd/s0.jsonl"
mout=$(cd "$lp" && HOME="$lh" "$SH" "$LM" 2>&1); rc=$?
check "lesson-mine: finds the typed correction, with the reply it answered" '[ $rc -eq 0 ] && grep -qF "USER: No, I told you to use bun" <<<"$mout" && grep -qF "AFTER: …I installed it with npm." <<<"$mout" && grep -qF "sess1234" <<<"$mout"'
check "lesson-mine: exactly one candidate, even with a forked copy (no answers, orders, hook notes, tool output, agents, forwarded tasks, sidechains)" 'grep -c "USER:" <<<"$mout" | grep -qx 1 && grep -qF "1 messages read like corrections" <<<"$mout"'
check "lesson-mine: transcripts older than the window are skipped" '! grep -qF "Why did you delete" <<<"$mout" && grep -qF "Scanned 2 transcripts from the last 30 days" <<<"$mout"'
mout=$(cd "$lp" && HOME="$lh" "$SH" "$LM" 100000 2>&1)
check "lesson-mine: a wider window finds the older one, newest first" 'grep -qF "Why did you delete" <<<"$mout" && [ "$(grep -m1 "USER:" <<<"$mout" | grep -c bun)" = 1 ]'
( cd "$lp" && HOME="$lh" "$SH" "$LM" lots >/dev/null 2>&1 ); rc=$?
check "lesson-mine: bad argument -> usage, rc!=0" '[ $rc -ne 0 ]'
mout=$(cd "$sandbox" && HOME="$lh" "$SH" "$LM" 2>&1); rc=$?
check "lesson-mine: no transcripts here -> says so, suggests all, rc=0" '[ $rc -eq 0 ] && grep -qF "lesson-mine.sh 30 all" <<<"$mout"'
check "/lesson mine runs the installed script and files nothing without the user's pick" "grep -qF 'hooks/harnessoperator/lesson-mine.sh' \"$CMDS/lesson.md\" && grep -qi 'never file a mined lesson without the user' \"$CMDS/lesson.md\""

# --- decision log (/decision's script + the SessionStart pointer) -------------------------
DL="$REPO/scripts/decision-log.sh"
check "decision-log.sh: executable, bash -n" '[ -x "$DL" ] && bash -n "$DL"'
dp="$sandbox/dproj"; mkdir -p "$dp/sub"; git -C "$dp" init -q
dslug=$(git -C "$dp" rev-parse --show-toplevel | sed 's#[^A-Za-z0-9]#-#g'); dfile="$sandbox/.claude/checkpoints/$dslug/DECISIONS.md"
dl() { (cd "$dp/sub" && HOME="$sandbox" "$SH" "$DL" "$@"); }
check "decision-log: empty log -> next is D1, list says none yet" '[ "$(dl next)" = D1 ] && dl list | grep -q "No decisions logged yet"'
check "decision-log: path is keyed by repo root, beside checkpoints, folder 700" '[ "$(dl path)" = "$dfile" ] && [ "$(perm "$(dirname "$dfile")")" = 700 ]'
printf '# Decisions — p\nintro\n\n## D1 — 2026-11-01 — Use npm\n- **Why:** x\n- **Status:** superseded by D3 (2026-11-20)\n\n## D2 — 2026-11-02 — Keep zero deps\n- **Status:** active\n\n## D3 — 2026-11-20 — Use bun, not npm\n- **Supersedes:** D1\n- **Status:** active\n\n## D10 — 2026-11-21 — Ten\n- **Status:** Active\n' > "$dfile"
dlist=$(dl list)
check "decision-log: list shows only active entries, superseded left out" 'grep -qF -- "- D2 — 2026-11-02 — Keep zero deps" <<<"$dlist" && grep -qF -- "- D3 — 2026-11-20 — Use bun, not npm" <<<"$dlist" && ! grep -qF "Use npm" <<<"$dlist"'
check "decision-log: list counts active and superseded" 'grep -qF "3 active, 1 superseded" <<<"$dlist"'
check "decision-log: next is numeric, not alphabetic (D10 -> D11)" '[ "$(dl next)" = D11 ]'
check "decision-log: unknown subcommand -> usage, rc!=0" '! dl bogus >/dev/null 2>&1'
out=$(jq -nc --arg c "$dp" '{hook_event_name:"SessionStart",source:"startup",session_id:"d1",cwd:$c}' | run)
check "SessionStart startup: names the active decision count and file" 'ctx "$out" | grep -qF "3 settled decisions for this project: $dfile"'
dp2="$sandbox/dproj2"; mkdir -p "$dp2"; git -C "$dp2" init -q
out=$(jq -nc --arg c "$dp2" '{hook_event_name:"SessionStart",source:"startup",session_id:"d2",cwd:$c}' | run)
check "SessionStart startup: no checkpoint and no decisions -> silent" '[ -z "$out" ]'
check "/decision: append-only, supersede by Status line, honest Decided by" "grep -qF 'hooks/harnessoperator/decision-log.sh' \"$CMDS/decision.md\" && grep -qi 'never delete or reword an old entry' \"$CMDS/decision.md\" && grep -qF 'Decided by' \"$CMDS/decision.md\""
check "/checkpoint logs its decisions into DECISIONS.md" "grep -qF 'DECISIONS.md' \"$CMDS/checkpoint.md\""

# --- evidence gate (Stop hook) ----------------------------------------------------------
GATE="$REPO/hooks/evidence-gate.sh"
check "evidence-gate.sh: executable, bash -n" '[ -x "$GATE" ] && bash -n "$GATE"'
eg="$sandbox/gate"; mkdir -p "$eg"
# Transcript builders: a typed user message, a tool call, its result, a reply.
u()  { jq -nc --arg t "$1" '{type:"user",message:{content:$t}}'; }
tc() { jq -nc --arg n "$1" --arg c "$2" '{type:"assistant",message:{content:[{type:"tool_use",name:$n,input:{command:$c,file_path:"/x"}}]}}';
       jq -nc '{type:"user",message:{content:[{type:"tool_result",content:"ok"}]}}'; }
say(){ jq -nc --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'; }
gate() {   # transcript file -> hook output (empty = allowed to stop)
  jq -nc --arg t "$1" --argjson a "${2:-false}" '{hook_event_name:"Stop",session_id:"g",transcript_path:$t,stop_hook_active:$a}' |
    HOME="$sandbox" "$SH" "$GATE"
}
blocks() { [ "$(jq -r .decision <<<"$1" 2>/dev/null)" = block ]; }

{ u "run it"; tc Edit ""; say "Done. All tests pass."; } > "$eg/t1.jsonl"
out=$(gate "$eg/t1.jsonl"); rc=$?
check "gate: 'tests pass' with no test run -> block, rc=0" 'blocks "$out" && [ $rc -eq 0 ] && jq -r .reason <<<"$out" | grep -qF "tests pass"'
{ u "run it"; tc Edit ""; tc Bash "bash tests/test-checkpoint.sh"; say "All tests pass (104)."; } > "$eg/t2.jsonl"
check "gate: test run after the edit -> allowed" '[ -z "$(gate "$eg/t2.jsonl")" ]'
{ u "run it"; tc Bash "bash tests/run.sh"; tc Edit ""; say "Tests pass."; } > "$eg/t3.jsonl"
check "gate: test run BEFORE the last edit does not count" 'blocks "$(gate "$eg/t3.jsonl")"'
{ u "old"; tc Bash "npm test"; say "ok"; u "now"; tc Edit ""; say "Tests pass."; } > "$eg/t4.jsonl"
check "gate: evidence from an earlier turn does not count" 'blocks "$(gate "$eg/t4.jsonl")"'
{ u "ship"; say "The API is not deployed yet. Tests: UNVERIFIED, I didn'\''t run them."; } > "$eg/t5.jsonl"
check "gate: negated or UNVERIFIED claims are not claims" '[ -z "$(gate "$eg/t5.jsonl")" ]'
{ u "x"; say $'Run this:\n```\nnpm test  # all tests pass\n```\nThen `deployed` appears.'; } > "$eg/t6.jsonl"
check "gate: claims inside code are ignored" '[ -z "$(gate "$eg/t6.jsonl")" ]'
{ u "ship"; tc Bash "curl -sI https://example.test/health"; say "It is deployed and live."; } > "$eg/t7.jsonl"
check "gate: deploy claim with a curl -> allowed" '[ -z "$(gate "$eg/t7.jsonl")" ]'
{ u "merge"; tc Bash "gh pr merge 3 --squash"; say "Merged."; } > "$eg/t8.jsonl"
check "gate: merge claim with gh pr merge -> allowed" '[ -z "$(gate "$eg/t8.jsonl")" ]'
{ u "fix"; tc Edit ""; say "Fixed."; } > "$eg/t9.jsonl"
check "gate: 'fixed' with only an edit -> block" 'blocks "$(gate "$eg/t9.jsonl")"'
check "gate: second stop in a row (stop_hook_active) -> never loops" '[ -z "$(gate "$eg/t1.jsonl" true)" ]'
check "gate: HO_EVIDENCE_GATE=off -> silent" '[ -z "$(jq -nc --arg t "$eg/t1.jsonl" "{transcript_path:\$t}" | HO_EVIDENCE_GATE=off "$SH" "$GATE")" ]'
check "gate: only the reply after the last tool call is judged" '{ u "x"; say "Tests pass, I think."; tc Bash "ls"; say "Listed the folder."; } > "$eg/t10.jsonl"; [ -z "$(gate "$eg/t10.jsonl")" ]'
# Regressions from replaying 406 real turns: each of these was a false alarm once.
{ u "x"; say 'A hook that checks claims like "deployed" or “tests pass”.'; } > "$eg/r1.jsonl"
check "gate: words in quotation marks are mentioned, not claimed" '[ -z "$(gate "$eg/r1.jsonl")" ]'
{ u "x"; tc Bash "curl -sI https://example.test"; jq -nc '"{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Edit\",\"input\":{\"file_path\":\"/h/.claude/projects/p/memory/x.md\"}}]}}" | fromjson'; say "It is live."; } > "$eg/r2.jsonl"
check "gate: writing memory or docs after the check does not reset it" '[ -z "$(gate "$eg/r2.jsonl")" ]'
{ u "x"; say "The agents corrections are merged into the spreadsheet."; } > "$eg/r3.jsonl"
check "gate: data being merged is not a git claim" '[ -z "$(gate "$eg/r3.jsonl")" ]'
{ u "x"; say "PR #12 is merged."; } > "$eg/r4.jsonl"
check "gate: a PR merge claim with no git evidence still blocks" 'blocks "$(gate "$eg/r4.jsonl")"'
{ u "x"; tc Agent ""; say "PR #12 is merged and all tests pass."; } > "$eg/r5.jsonl"
check "gate: a turn that delegated to agents relays their checks" '[ -z "$(gate "$eg/r5.jsonl")" ]'
{ u "<task-notification>agent done</task-notification>"; say "Tests pass, per the agent."; } > "$eg/r6.jsonl"
check "gate: a turn opened by an agent report is a relay" '[ -z "$(gate "$eg/r6.jsonl")" ]'
{ u "x"; say "Nothing is merged or deployed."; } > "$eg/r7.jsonl"
check "gate: 'Nothing is merged or deployed' claims nothing" '[ -z "$(gate "$eg/r7.jsonl")" ]'
# The first live false alarm (2026-11-24): skills merged and installed, then called "live".
{ u "merge"; tc Bash "gh pr merge 11 --squash"; tc Bash "cmp scripts/x.sh ~/.claude/hooks/x.sh && echo INSTALLED-MATCHES";
  say "The /lesson installed on this Mac is the same as main. All three skills are now live."; } > "$eg/r8.jsonl"
check "gate: 'live' for a local install, with the installed copy checked -> allowed" '[ -z "$(gate "$eg/r8.jsonl")" ]'
{ u "x"; tc Bash "cmp a b"; say "The site is now live."; } > "$eg/r9.jsonl"
check "gate: a site called live with only a file compare -> still blocks" 'blocks "$(gate "$eg/r9.jsonl")"'
{ u "x"; tc Bash "ls"; say "It is installed and now live."; } > "$eg/r10.jsonl"
check "gate: 'installed and live' with no install or compare run -> still blocks" 'blocks "$(gate "$eg/r10.jsonl")"'
{ u "Stop hook feedback: Evidence gate: your final reply makes claims"; say "PR #11 is merged; proof was in the previous turn."; } > "$eg/r11.jsonl"
check "gate: the turn answering its own nudge is never nudged again" '[ -z "$(gate "$eg/r11.jsonl")" ]'
# The second live false alarm: a helper script written to the scratchpad after the test run.
w() { jq -nc --arg p "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:"Write",input:{file_path:$p}}]}}'; }
{ u "x"; tc Bash "bash tests/run.sh"; w /private/tmp/claude-501/p/s/scratchpad/ship.sh; w /tmp/note.sh; say "All 169 tests pass."; } > "$eg/r12.jsonl"
check "gate: scratchpad and /tmp edits after the test run do not reset it" '[ -z "$(gate "$eg/r12.jsonl")" ]'
{ u "x"; tc Bash "bash tests/run.sh"; w /repo/tmp/fix.sh; say "All 169 tests pass."; } > "$eg/r13.jsonl"
check "gate: a project file in a folder named tmp still resets it" 'blocks "$(gate "$eg/r13.jsonl")"'
# The third live false alarm: "a fixed version" means pinned, not repaired.
{ u "x"; tc Edit ""; say "Tag it, so others can install a fixed version. The fixed-width table and a fixed mix stay."; } > "$eg/r14.jsonl"
check "gate: 'fixed' before a noun (a fixed version) is not a fix claim" '[ -z "$(gate "$eg/r14.jsonl")" ]'
{ u "x"; tc Edit ""; say "Pinned a fixed version, and the login bug is fixed."; } > "$eg/r15.jsonl"
check "gate: a real 'is fixed' beside a fixed version still blocks" 'blocks "$(gate "$eg/r15.jsonl")"'
echo 'not json' | HOME="$sandbox" "$SH" "$GATE" >/dev/null 2>&1; rc=$?
check "gate: garbage stdin / missing transcript -> rc=0, silent" '[ $rc -eq 0 ] && [ -z "$(gate /nonexistent.jsonl)" ]'

# --- the brief is enforced: Don't touch (brief guard) and Done means (gate) -------------
BG="$REPO/hooks/brief-guard.sh"
check "brief-guard.sh: executable, bash -n" '[ -x "$BG" ] && bash -n "$BG"'
# Inside the repo, not the temp sandbox: the gate ignores edits under /tmp and /var/folders.
bp="$REPO/.brief-test.$$"; trap 'rm -rf "$sandbox" "$bp"' EXIT; mkdir -p "$bp/data/presets" "$bp/src"; git -C "$bp" init -q
bproot=$(cd "$bp" && pwd -P); bd="$sandbox/.claude/checkpoints/$(printf '%s' "$bproot" | sed 's#[^A-Za-z0-9]#-#g')"
mkdir -p "$bd"; BRIEF="$bd/BRIEF.md"
cat > "$BRIEF" <<'EOF'
# Brief — briefproj — 2026-11-25 14:00
## Done means
- [ ] `SH=/bin/bash bash tests/run.sh -v` passes
- [ ] the form shows an error on an empty email
## Don't touch
- `data/presets.generated.js` (generated)
- `config/` and anything matching `src/*.min.js`
- production data
## Assumptions
- `src/app.js` is the entry point
EOF
bt="$sandbox/brief-t.jsonl"; printf '{"type":"user","message":{"content":"wrote %s"}}\n' "$BRIEF" > "$bt"
gp() {   # file path [transcript] -> a PreToolUse payload for an Edit
  jq -nc --arg f "$1" --arg t "${2:-$bt}" --arg c "$bp" '{hook_event_name:"PreToolUse",tool_name:"Edit",cwd:$c,transcript_path:$t,tool_input:{file_path:$f}}'
}
guard() { gp "$@" | HOME="$sandbox" "$SH" "$BG"; }   # -> hook output (empty = allowed)
denies() { [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$1" 2>/dev/null)" = deny ]; }
out=$(guard "$bp/data/presets.generated.js"); rc=$?
check "brief guard: a Don't touch file -> deny, rc=0, names it" 'denies "$out" && [ $rc -eq 0 ] && jq -r .hookSpecificOutput.permissionDecisionReason <<<"$out" | grep -qF "data/presets.generated.js"'
check "brief guard: a Don't touch folder covers files inside, even new ones" 'denies "$(guard "$bp/config/deep/new.json")"'
check "brief guard: a glob matches (src/*.min.js)" 'denies "$(guard "$bp/src/app.min.js")"'
check "brief guard: other files, and paths outside the section, are allowed" '[ -z "$(guard "$bp/src/app.js")" ] && [ -z "$(guard "$bp/data/presets/a.json")" ]'
check "brief guard: a relative file_path is read from cwd" 'denies "$(guard "data/presets.generated.js")"'
printf '{"type":"user","message":{"content":"unrelated"}}\n' > "$sandbox/other-t.jsonl"
check "brief guard: a session that never saw the brief is not bound by it" '[ -z "$(guard "$bp/data/presets.generated.js" "$sandbox/other-t.jsonl")" ]'
out=$(gp "$bp/config/x" | HO_BRIEF_GUARD=off HOME="$sandbox" "$SH" "$BG")
check "brief guard: HO_BRIEF_GUARD=off -> silent" '[ -z "$out" ]'
out=$(echo junk | HOME="$sandbox" "$SH" "$BG"); rc=$?
check "brief guard: garbage stdin -> silent, rc=0" '[ -z "$out" ] && [ $rc -eq 0 ]'
check "brief guard: no brief for the project -> silent" '[ -z "$(jq -nc "{tool_input:{file_path:\"/nowhere/x\"}}" | HOME="$sandbox" "$SH" "$BG")" ]'
# The gate: a turn that edits project code and calls the task done must run the brief's
# commands after the edit. Items without a command are not checked.
be() { jq -nc --arg p "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:"Edit",input:{file_path:$p}}]}}'; }
{ cat "$bt"; be "$bp/src/app.js"; say "Done. The form now rejects an empty email."; } > "$eg/b1.jsonl"
out=$(gate "$eg/b1.jsonl")
check "gate: task called done, brief command not run -> block naming the item" 'blocks "$out" && jq -r .reason <<<"$out" | grep -qF "SH=/bin/bash bash tests/run.sh -v" && ! jq -r .reason <<<"$out" | grep -qF "empty email"'
{ cat "$bt"; be "$bp/src/app.js"; tc Bash "bash tests/run.sh 2>&1 | tail -1"; say "Done."; } > "$eg/b2.jsonl"
check "gate: the brief command ran after the edit -> allowed" '[ -z "$(gate "$eg/b2.jsonl")" ]'
{ cat "$bt"; tc Bash "bash tests/run.sh"; be "$bp/src/app.js"; say "Done."; } > "$eg/b3.jsonl"
check "gate: the brief command ran BEFORE the last edit -> block" 'blocks "$(gate "$eg/b3.jsonl")"'
{ u "go"; be "$bp/src/app.js"; say "Done."; } > "$eg/b4.jsonl"
check "gate: a session that never saw the brief is not held to it" '[ -z "$(gate "$eg/b4.jsonl")" ]'
{ cat "$bt"; be "$bp/src/app.js"; say "Changed the handler; next I wire the form."; } > "$eg/b5.jsonl"
check "gate: a turn that does not call the task done is not held to the brief" '[ -z "$(gate "$eg/b5.jsonl")" ]'

# --- /doctor finds, /cure fixes -------------------------------------------------------
# A real install in its own home; each case breaks one thing, doctor must name it with the
# right fix, and that fix must make the next doctor run say OK.
dh="$sandbox/dochome"; DC="$dh/.claude"; DS="$DC/settings.json"; DH="$DC/hooks/harnessoperator"
mkdir -p "$DC"; echo '{"model":"keep"}' > "$DS"; inst "$dh"
doc()  { (cd "$dh" && HOME="$dh" "$SH" "$DH/doctor.sh"); }
cure() { HOME="$dh" "$SH" "$DH/cure.sh" "$@"; }
check "install: records its checkout for /doctor and /cure" '[ "$(cat "$DH/source")" = "$REPO" ] && [ -x "$DH/doctor.sh" ] && [ -x "$DH/cure.sh" ]'
out=$(doc); rc=$?
check "doctor: a fresh install is healthy (0 fail, 0 warn), rc=0" '[ $rc -eq 0 ] && printf "%s\n" "$out" | tail -1 | grep -q "doctor: 0 fail, 0 warn"'
chmod -x "$DH/evidence-gate.sh"; out=$(doc)
check "doctor: a hook that isn't executable -> FAIL with a safe chmod fix" 'printf "%s\n" "$out" | grep -q "^FAIL hook:evidence-gate.sh" && printf "%s\n" "$out" | grep -qF "fix (safe): bash ~/.claude/hooks/harnessoperator/cure.sh chmod $DH/evidence-gate.sh"'
cure chmod "$DH/evidence-gate.sh" >/dev/null
check "cure chmod: fixes it, doctor is healthy again" '[ -x "$DH/evidence-gate.sh" ] && doc | tail -1 | grep -q "0 fail, 0 warn"'
check "cure chmod: refuses a file outside the hooks folder" '! cure chmod "$DS" 2>/dev/null && [ ! -x "$DS" ]'
jq 'del(.hooks.Stop)' "$DS" > "$DS.t" && mv "$DS.t" "$DS"; out=$(doc)
check "doctor: an unwired hook -> FAIL wiring:Stop with the safe reinstall fix" 'printf "%s\n" "$out" | grep -q "^FAIL wiring:Stop" && printf "%s\n" "$out" | grep -qF "fix (safe): bash ~/.claude/hooks/harnessoperator/cure.sh reinstall"'
cure reinstall >/dev/null 2>&1
check "cure reinstall: rewires it, keeps other settings" 'doc | tail -1 | grep -q "0 fail, 0 warn" && [ "$(jq -r .model "$DS")" = keep ]'
jq '.env = {HO_EVIDENCE_GATE: "off", KEEP: "1"} | .hooks.Stop += [{hooks: [{type: "command", command: "bash /nowhere/gone.sh"}]}]' "$DS" > "$DS.t" && mv "$DS.t" "$DS"
out=$(doc)
check "doctor: gate switched off in settings -> WARN with an ask fix" 'printf "%s\n" "$out" | grep -q "^WARN off:HO_EVIDENCE_GATE" && printf "%s\n" "$out" | grep -qF "fix (ask): bash ~/.claude/hooks/harnessoperator/cure.sh unset-env HO_EVIDENCE_GATE"'
check "doctor: a hook whose script is gone -> WARN dead-hook with an ask fix" 'printf "%s\n" "$out" | grep -q "^WARN dead-hook.*/nowhere/gone.sh" && printf "%s\n" "$out" | grep -qF "remove-hook '"'"'bash /nowhere/gone.sh'"'"'"'
cure unset-env HO_EVIDENCE_GATE >/dev/null; cure remove-hook "bash /nowhere/gone.sh" >/dev/null
check "cure unset-env + remove-hook: only those removed, settings backed up" \
  'doc | tail -1 | grep -q "0 fail, 0 warn" && [ "$(jq -r .env.KEEP "$DS")" = 1 ] && [ "$(jq "[.hooks.Stop[].hooks[]] | length" "$DS")" = 1 ] && ls "$DS".bak-harnessoperator-* >/dev/null 2>&1'
check "cure unset-env: refuses a variable that isn't HO_*" '! cure unset-env PATH 2>/dev/null'
cp "$DS" "$sandbox/ds-good"; printf '{broken' > "$DS"; out=$(doc)
check "doctor: unparseable settings.json -> FAIL with an ask restore fix" 'printf "%s\n" "$out" | grep -q "^FAIL settings" && printf "%s\n" "$out" | grep -qF "cure.sh restore-settings"'
cure restore-settings >/dev/null
check "cure restore-settings: newest valid backup back, broken file kept" 'jq empty "$DS" 2>/dev/null && ls "$DS".broken-* >/dev/null 2>&1 && doc | tail -1 | grep -q "0 fail"'
dproj="$DC/checkpoints/$(printf '%s' "$(cd "$dh" && pwd -P)" | sed 's#[^A-Za-z0-9]#-#g')"; mkdir -p "$dproj"
printf '# Brief\n' > "$dproj/BRIEF.md"; touch -t 202601010000 "$dproj/BRIEF.md"; out=$(doc)
check "doctor: a brief weeks old -> WARN with an ask archive fix" 'printf "%s\n" "$out" | grep -q "^WARN brief" && printf "%s\n" "$out" | grep -qF "archive-brief $dproj"'
cure archive-brief "$dproj" >/dev/null
check "cure archive-brief: moved aside as BRIEF-<date>.md" '[ ! -f "$dproj/BRIEF.md" ] && ls "$dproj"/BRIEF-2026-01-01_*.md >/dev/null 2>&1'
rm "$DH/source"; out=$(doc)
check "doctor: no recorded checkout -> WARN, and its fixes turn manual" 'printf "%s\n" "$out" | grep -q "^WARN source" && ! printf "%s\n" "$out" | grep -q "fix (safe): .*reinstall"'
check "cure: an unknown fix is refused, rc=1" '! cure frobnicate 2>/dev/null'
check "/doctor is read-only and points to /cure" "grep -qF 'hooks/harnessoperator/doctor.sh' \"$CMDS/doctor.md\" && grep -qi 'read-only' \"$CMDS/doctor.md\" && grep -qF '/cure' \"$CMDS/doctor.md\""
check "/cure fixes only through cure.sh, asks for ask fixes, re-checks" "grep -qF 'cure.sh' \"$CMDS/cure.md\" && grep -qi 'never through a hand edit' \"$CMDS/cure.md\" && grep -qi 'second doctor run' \"$CMDS/cure.md\""

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
