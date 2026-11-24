#!/usr/bin/env bash
# harnessoperator-skills — context inventory: the measurable half of /context-audit.
# Prints what Claude Code put into a session's context before the first message, and the
# mechanical faults in it, so the model can spend its judgement on meaning (contradictions,
# duplicates, misplaced rules) instead of counting bytes.
#
# Source of truth is a session transcript, not a guess at Claude Code's loading rules: the
# transcript records the instruction files it loaded (with their content), every hook's
# injected text, the skill listing, the agent listing, MCP server instructions and the
# output style. Usage:
#   context-inventory.sh [transcript.jsonl]
# Without an argument it takes the newest transcript of the project in $PWD. Read-only.
# Needs bash and jq. Tests: bash tests/test-checkpoint.sh

STALE_DAYS=${HO_AUDIT_STALE_DAYS:-30}   # a dated "LIVE"/"deployed" claim older than this is flagged

slugify() { printf '%s' "$1" | sed 's#[^A-Za-z0-9]#-#g'; }
tok() { echo $(( ($1 + 3) / 4 )); }     # rough tokens from characters, same rule for every row

transcript=$1
if [ -z "$transcript" ]; then
  # Claude Code keys its project folder by the launch directory; try the repo root too.
  for p in "$PWD" "$(git rev-parse --show-toplevel 2>/dev/null)"; do
    [ -n "$p" ] || continue
    transcript=$(ls -t "$HOME/.claude/projects/$(slugify "$p")"/*.jsonl 2>/dev/null | head -1)
    [ -n "$transcript" ] && break
  done
fi
[ -f "$transcript" ] || { echo "No session transcript found for $PWD. Pass one: context-inventory.sh <file.jsonl>" >&2; exit 1; }

# Only the session's opening matters: the first of each attachment is what was loaded at start.
start=$(head -c 3000000 "$transcript" | jq -Rc 'fromjson? | select(.attachment) | .attachment' 2>/dev/null)
first() { printf '%s\n' "$start" | jq -c --arg t "$1" 'select(.type == $t)' | head -1; }

echo "# Context inventory"
echo "transcript: $transcript"
echo "session start: $(head -c 3000000 "$transcript" | jq -Rr 'fromjson? | .timestamp // empty' 2>/dev/null | head -1)"
echo

# --- 1. what was loaded -------------------------------------------------------------
echo "## Loaded before the first message (≈tokens = chars/4)"
echo
echo "| ≈tokens | chars | kind | source |"
echo "|---:|---:|---|---|"
rows=$(
  first instructions | jq -r '.files[]? | [(.content // "" | length), (.type // "file"), (.path // "?")] | @tsv'
  # Hook content is a string or an array of strings, depending on the hook kind.
  printf '%s\n' "$start" | jq -r 'select(.type == "hook_success" or .type == "hook_additional_context")
      | (.content // "" | if type == "array" then join("\n") else tostring end) as $c | select($c != "")
      | [($c | length), "hook", ((.hookName // .hookEvent // "hook") + (if .command then " — " + (.command | .[0:70]) else "" end))] | @tsv'
  first skill_listing | jq -r '[(.content // "" | length), "skills", "skill listing (\(.skillCount // "?") skills)"] | @tsv'
  first agent_listing_delta | jq -r '[(.addedLines // [] | tostring | length), "agents", "agent listing"] | @tsv'
  first deferred_tools_delta | jq -r '[(.addedLines // [] | tostring | length), "tools", "deferred tool names (\(.addedNames // [] | length))"] | @tsv'
  # Each MCP block is a string headed "## <server>".
  first mcp_instructions_delta | jq -r '.addedBlocks[]? | tostring | [length, "mcp", "MCP instructions: " + (split("\n")[0] | ltrimstr("## "))] | @tsv'
  first output_style_instructions | jq -r '.style as $s | [($s | if type == "object" then (.prompt // "" | length) else tostring | length end),
      "style", "output style: " + ($s | if type == "object" then .name // "?" else tostring end)] | @tsv'
)
total=0
while IFS=$'\t' read -r chars kind src; do
  [ -n "$chars" ] || continue
  total=$((total + chars))
  printf '| %s | %s | %s | %s |\n' "$(tok "$chars")" "$chars" "$kind" "$src"
done <<<"$(printf '%s\n' "$rows" | sort -t$'\t' -k1,1nr)"
echo "| **$(tok $total)** | **$total** | | **total measured** (system prompt and tool schemas not included) |"
echo

# --- 1b. skill listing by entry --------------------------------------------------------
# The listing carries every installed skill's description, used or not. The few long
# descriptions are usually most of its weight, and those are what can be shortened.
listing=$(first skill_listing | jq -r '.content // empty')
if [ -n "$listing" ]; then
  echo "## Skill listing — largest entries"
  echo
  ranked=$(printf '%s\n' "$listing" | awk '
    /^- / { if (name != "") print len "\t" name; name = $2; sub(/:$/, "", name); len = length($0); next }
    { len += length($0) + 1 }
    END { if (name != "") print len "\t" name }' | sort -rn)
  printf '%s\n' "$ranked" | awk -F'\t' '{t += $1} $1 > 300 {b += $1; c++} END {
    printf "%d entries, %d chars; %d entries over 300 chars hold %d of them\n\n", NR, t, c, b }'
  printf '%s\n' "$ranked" | head -10 | while IFS=$'\t' read -r n s; do echo "- $s — $n chars (≈$(tok "$n") tokens)"; done
  echo
fi

# --- 2. loaded files vs disk ----------------------------------------------------------
# A file loaded shorter than it is on disk was cut by a loader limit: the rest is invisible.
echo "## Loaded files vs disk"
echo
# Only a loaded copy that is a strict prefix of the file proves a cut. Any other mismatch
# means the file was edited since, or the loader normalised it (it drops HTML comments).
instr=$(first instructions)
printf '%s\n' "$instr" | jq -r '.files[]?.path // empty' |
while IFS= read -r path; do
  [ -f "$path" ] || { echo "- MISSING NOW: $path (it was loaded, the file is gone)"; continue; }
  lines=$(wc -l < "$path" | tr -d ' ')
  state=$(printf '%s\n' "$instr" | jq -r --arg p "$path" --rawfile disk "$path" '
    def trim: sub("\\s+$"; "");   # the loader drops the final newline
    ([.files[] | select(.path == $p) | .content // ""][0] | trim) as $c | ($disk | trim) as $disk
    | if $c == $disk then "same"
      elif ($disk | startswith($c)) and ($disk | length) > ($c | length) then "cut \($c | length) \($disk | length)"
      else "differs" end')
  case "$state" in
    (cut*) set -- $state; echo "- TRUNCATED: $path — $2 of $3 chars loaded ($lines lines); the tail never reaches the model" ;;
    (differs) echo "- ok: $path — $lines lines (disk differs: edited since this session, or comments stripped on load)" ;;
    (*) echo "- ok: $path — $lines lines" ;;
  esac
done
echo

loaded_files=$(first instructions | jq -r '.files[]?.path // empty' | while IFS= read -r p; do [ -f "$p" ] && echo "$p"; done)

# Strip fenced blocks and `inline code` so examples are never reported as faults.
prose() { awk '/^[[:space:]]*```/{f=!f; print ""; next} {print f ? "" : $0}' "$1" | sed 's/`[^`]*`//g'; }

# --- 3. memory index -----------------------------------------------------------------
echo "## Memory index"
echo
mem=$(first instructions | jq -r '.files[]? | select(.type == "AutoMem") | .path' | head -1)
if [ -n "$mem" ] && [ -f "$mem" ]; then
  mdir=$(dirname "$mem")
  linked=$(grep -oE '\]\([^)#]+\.md\)' "$mem" | sed -E 's/^\]\(//; s/\)$//' | sort -u)
  missing=$(printf '%s\n' "$linked" | while IFS= read -r l; do [ -n "$l" ] && [ ! -f "$mdir/$l" ] && echo "$l"; done)
  orphans=$(ls "$mdir" | grep '\.md$' | grep -vx MEMORY.md | while IFS= read -r f; do printf '%s\n' "$linked" | grep -qxF "$f" || echo "$f"; done)
  echo "- index: $mem — $(wc -l < "$mem" | tr -d ' ') lines, $(printf '%s\n' "$linked" | grep -c .) linked files, $(ls "$mdir" | grep -c '\.md$') files in folder"
  echo "- links to missing files: $(printf '%s\n' "$missing" | grep -c .)"
  printf '%s\n' "$missing" | grep . | sed 's/^/  - /'
  echo "- files not linked from the index (never recalled by the index): $(printf '%s\n' "$orphans" | grep -c .)"
  printf '%s\n' "$orphans" | grep . | head -40 | sed 's/^/  - /'
else
  echo "- no auto-memory index was loaded"
fi
echo

# --- 4. dead path references -----------------------------------------------------------
# Absolute or ~/ paths named in loaded prose that no longer exist mislead every session.
# /etc, /var and /srv are left out: in these files they nearly always name a server's path.
echo "## Paths named in loaded files that do not exist on this machine"
echo
for f in $loaded_files; do
  prose "$f" | grep -noE '(^|[[:space:](\[])(~/|/(Users|Volumes|home|opt|private)/)[A-Za-z0-9._@/+-]+' |
    sed -E 's/:[[:space:](\[]/:/' | while IFS=: read -r n p; do
      p=${p%[.,;:)]}; case "$p" in (*'<'*|*'*'*) continue ;; esac
      full=$p; case "$p" in ("~/"*) full="$HOME/${p#\~/}" ;; esac
      [ -e "$full" ] || echo "- $f:$n — $p"
    done
done | sort -u
echo

# --- 5. markup debris ------------------------------------------------------------------
echo "## Stray HTML in loaded prose"
echo
for f in $loaded_files; do
  prose "$f" | grep -nE '</?(p|strong|em|b|i|div|span|a|img|h[1-6]|ul|ol|li|table|tr|td|br)( [^>]*)?/?>' |
    cut -c1-160 | sed "s#^#- $f:#"
done
echo

# --- 6. dated claims -------------------------------------------------------------------
# "LIVE", "deployed", "current" next to an old date is state, and state goes stale.
echo "## Dated state claims older than $STALE_DAYS days (verify or drop)"
echo
cutoff=$(date -v-"${STALE_DAYS}"d +%F 2>/dev/null || date -d "-$STALE_DAYS days" +%F)
for f in $loaded_files; do
  prose "$f" | grep -nE '20[0-9]{2}-[01][0-9]-[0-3][0-9]' | grep -iE 'live|deployed|current|latest|running|now|today' |
    while IFS= read -r line; do
      d=$(printf '%s' "$line" | grep -oE '20[0-9]{2}-[01][0-9]-[0-3][0-9]' | sort | tail -1)
      [ "$d" \< "$cutoff" ] && printf -- '- %s:%s\n' "$f" "$(printf '%s' "$line" | cut -c1-160)"
    done
done
exit 0
