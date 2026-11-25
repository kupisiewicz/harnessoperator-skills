#!/usr/bin/env bash
# harnessoperator-skills — lesson mining: the mechanical half of `/lesson mine`.
# /lesson only helps when the user remembers to type it. The corrections are already on
# disk, in the session transcripts: "no, …", "I told you…", "never …". This script finds
# the typed user messages that read like corrections, pairs each with the reply it
# answered, and prints them newest first. The model then groups them into rules and
# files each one the way /lesson does.
#
# Usage: lesson-mine.sh [days] [all]   (default: 30 days, this project's transcripts)
#   all = every project's transcripts, not just the ones started from here.
# Read-only. Needs bash and jq.
# Tests: bash tests/test-checkpoint.sh

days=30; scope=here
for a in "$@"; do
  case "$a" in
    (all) scope=all ;;
    (*[!0-9]*|'') echo "Usage: lesson-mine.sh [days] [all]" >&2; exit 1 ;;
    (*) days=$a ;;
  esac
done
MAX=${HO_LESSON_MINE_MAX:-60}
projects="$HOME/.claude/projects"
slugify() { printf '%s' "$1" | sed 's#[^A-Za-z0-9]#-#g'; }

# Claude Code files a transcript under the launch directory, spelled as launched, so try
# the logical path, then the physical one, then the repo root.
if [ "$scope" = all ]; then
  dirs=$(ls -d "$projects"/*/ 2>/dev/null)
else
  for p in "$PWD" "$(pwd -P)" "$(git rev-parse --show-toplevel 2>/dev/null)"; do
    [ -n "$p" ] && [ -d "$projects/$(slugify "$p")" ] && { dirs="$projects/$(slugify "$p")"; break; }
  done
fi
[ -n "$dirs" ] || { echo "No transcripts for $PWD under $projects. Try: lesson-mine.sh $days all"; exit 0; }

# Top-level files only: subagent transcripts hold the orchestrator's words, not the user's.
files=$(printf '%s\n' "$dirs" | while IFS= read -r d; do
  find "${d%/}" -maxdepth 1 -name '*.jsonl' -mtime -"$days" 2>/dev/null; done)
[ -n "$files" ] || { echo "No transcripts newer than $days days."; exit 0; }

# Only messages the user typed: not tool results, harness notes (isMeta: hook feedback,
# command caveats), compact summaries or injected tags. Strong signals say outright that
# the model got it wrong; weak ones only hint. A candidate needs a score of 2.
# Tuned on real transcripts, these were noise and are left out: a bare "Stop" (an order,
# not a correction); "No" answering a reply that ended in a question; and long messages,
# pasted text or tasks forwarded from another session (briefs, not corrections), and
# entries whose origin is not a human (agent and scheduled-task notifications).
# shortcut: a task another session sends a new one is recorded as human, so a short brief
# with "never merge" in it still comes through; /lesson mine tells the model to drop those.
program='
def text: if type == "string" then . else (map(select(.type? == "text") | .text) | join(" ")) end;
def flat: gsub("[\r\n\t]+"; " ⏎ ");
[inputs | fromjson? | select(.isSidechain != true)] as $e
| [ foreach $e[] as $x ({last: ""};
      if $x.type == "assistant" then
        (($x.message.content // []) | text) as $t
        | if ($t | length) > 0 then .last = $t else . end | .out = null
      elif $x.type == "user" and ($x.isMeta != true) and ($x.isCompactSummary != true)
           and (($x.origin.kind // "human") == "human") then
        (($x.message.content // "") | if type == "array" and (map(.type? == "tool_result") | any) then "" else text end) as $u
        | .out = (if ($u | test("^\\s*(<|Caveat:|Stop hook feedback|This session is being continued)"; "i")) then null
                  else {u: $u, a: .last, ts: ($x.timestamp // ""), s: ($x.sessionId // "")} end)
      else .out = null end;
      .out) | select(. != null and (.u | length) > 1 and (.u | length) <= 1200) ]
| .[]
| select(.u | test("^\\s*Task \\(from the session|<pasted_content") | not)
| (.u | ascii_downcase) as $l
| (.a | test("\\?\\s*$")) as $asked
| ( ( [ "^\\s*(nope|wrong|don.?t)\\b", "\\bstop [a-z]+ing\\b",
        "\\bi (told|said|asked) you\\b", "\\bi already (said|told|asked)\\b", "\\bhow many times\\b",
        "\\bnot what i (asked|meant|said|wanted)\\b", "\\bwhy did you\\b", "\\byou (forgot|ignored|missed|keep)\\b",
        "\\bleave (it|them|that|those) alone\\b", "\\bdon.?t (ever|do that|do this)\\b", "\\b(never|always) [a-z]",
        "\\bthat.?s not (right|it|true|what)\\b", "\\bagain[.!?]" ]
      | map(select(. as $r | $l | test($r))) | length) * 2
    + ( [ "\\b(don.?t|do not|instead|should(n.?t)?|must|not like that|rather)\\b" ]
      | map(select(. as $r | $l | test($r))) | length)
    + (if ($asked | not) and ($l | test("^\\s*no\\b")) then 2 else 0 end) ) as $score
| select($score >= 2)
| [ .ts[0:16], .s[0:8], ($score | tostring), (.u | flat | .[0:300]), (.a | flat | .[-160:]) ] | @tsv
'

# A forked or resumed session copies the earlier messages into its own transcript, keeping
# their timestamp and session id, so one correction can appear in many files. Keep one per
# timestamp + session + text. Seen live: one message 17 times.
out=$(printf '%s\n' "$files" | while IFS= read -r f; do jq -Rnr "$program" "$f" 2>/dev/null; done |
  sort -r | awk -F'\t' '!seen[$1 FS $2 FS $4]++')
n=$(printf '%s' "$out" | grep -c .)
nf=$(printf '%s\n' "$files" | grep -c .)
echo "Scanned $nf transcripts from the last $days days ($scope). $n messages read like corrections; newest first, at most $MAX."
[ "$n" -gt 0 ] || exit 0
echo
printf '%s\n' "$out" | head -n "$MAX" | awk -F'\t' '{
  printf "%s · %s · score %s\n  USER: %s\n", $1, $2, $3, $4
  if ($5 != "") printf "  AFTER: …%s\n", $5
  print ""
}'
