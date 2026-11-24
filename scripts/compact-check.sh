#!/usr/bin/env bash
# harnessoperator-skills — compact check: the measurable half of /compact-check.
# Prints how full the session's context is and what state would ride through a compaction
# only as a summary: repos with uncommitted or unpushed work, and how old the project's
# checkpoints are. Work in flight (running agents, half-done edits) is not in any file, so
# the model reports that part itself.
#
# The size is a measurement, not an estimate: every assistant entry in the transcript
# carries the API's own token usage, and the last one's input + cache read + cache creation
# is what the model was last sent. Usage:
#   compact-check.sh [transcript.jsonl]
# Without an argument it takes this session's transcript (CLAUDE_CODE_SESSION_ID), else
# the newest one of the project in $PWD. Read-only; never prints message content.
# Exit: 0 measured, 1 no transcript, 2 transcript has no usage to measure.
# Needs bash and jq; git is optional. Tests: bash tests/test-checkpoint.sh

TAIL_BYTES=20000000   # the same window of recent activity the compact hook judges from

slugify() { printf '%s' "$1" | sed 's#[^A-Za-z0-9]#-#g'; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }   # GNU first: BSD stat has no -c
age() {   # "40s" / "12m" / "3h" / "2d" since the file was last written
  local s=$(( $(date +%s) - $(mtime "$1") ))
  if [ $s -lt 60 ]; then echo "${s}s"; elif [ $s -lt 3600 ]; then echo "$((s / 60))m"
  elif [ $s -lt 86400 ]; then echo "$((s / 3600))h"; else echo "$((s / 86400))d"; fi
}

transcript=$1
if [ -z "$transcript" ]; then
  # Several sessions can run in one folder, so "newest file" may be a neighbour's. The
  # session id, when the harness exports it, names this session's file exactly.
  id=${CLAUDE_CODE_SESSION_ID//[^A-Za-z0-9_-]/}
  [ -n "$id" ] && transcript=$(ls "$HOME/.claude/projects"/*/"$id".jsonl 2>/dev/null | head -1)
fi
if [ -z "$transcript" ]; then
  # Claude Code keys its project folder by the launch directory; try the repo root too.
  for p in "$PWD" "$(git rev-parse --show-toplevel 2>/dev/null)"; do
    [ -n "$p" ] || continue
    transcript=$(ls -t "$HOME/.claude/projects/$(slugify "$p")"/*.jsonl 2>/dev/null | head -1)
    [ -n "$transcript" ] && break
  done
fi
[ -f "$transcript" ] || { echo "No session transcript found for $PWD. Pass one: compact-check.sh <file.jsonl>" >&2; exit 1; }

# Subagent turns (isSidechain) have their own, smaller context, and synthetic error
# entries carry zero usage: neither says how full the main conversation is.
last=$(tail -c "$TAIL_BYTES" "$transcript" | jq -Rr 'fromjson? | objects
    | select(.type == "assistant" and .isSidechain != true) | .message | objects | select(.usage | type == "object")
    | [(.model // "unknown"), ((.usage.input_tokens // 0) + (.usage.cache_read_input_tokens // 0) + (.usage.cache_creation_input_tokens // 0))]
    | select(.[1] > 0) | @tsv' 2>/dev/null | tail -1)
[ -n "$last" ] || { echo "No assistant usage in $transcript: context size cannot be measured (new session, or not a Claude Code transcript)." >&2; exit 2; }
model=${last%%	*}; used=${last##*	}

# The transcript does not record the window, so it is detected where possible and stated
# as an assumption where not.
case "$HO_CONTEXT_WINDOW" in (''|*[!0-9]*|0) window= ;; (*) window=$HO_CONTEXT_WINDOW; why="set by HO_CONTEXT_WINDOW" ;; esac
if [ -z "$window" ]; then
  case "$model" in (*'[1m]'*) window=1000000; why="from the model id" ;; esac
fi
if [ -z "$window" ] && [ "$used" -gt 200000 ]; then
  window=1000000; why="inferred: the context is already past 200k"
fi
[ -n "$window" ] || { window=200000; why="ASSUMED: set HO_CONTEXT_WINDOW if this session has a larger window"; }
pct=$(( used * 100 / window ))

if [ $pct -ge 75 ]; then should="yes (75% or more: compact before auto-compact picks the moment)"
elif [ $pct -ge 50 ]; then should="soon (50-74%: at the next natural break)"
else should="no (under 50%: compacting would cost more detail than it frees)"; fi

echo "# Compact check"
echo "transcript: $transcript (written $(age "$transcript") ago)"
echo "model: $model"
echo "context: $used of $window tokens ($pct%) — measured at the last model turn; anything read since adds to it"
echo "window: $window — $why"
echo "should compact: $should"
echo

# --- repos touched ---------------------------------------------------------------------
# Same evidence the compact hook uses: entry cwds and the file paths of tool calls. A repo
# reached only through a shell command (git -C, cd inside a one-liner) is not visible here.
paths=$(tail -c "$TAIL_BYTES" "$transcript" | jq -Rr 'fromjson? | objects | (.cwd // empty | strings),
    (.message | objects | .content | arrays | .[] | objects | select(.type == "tool_use") | .input | objects
     | (.file_path // .path // .notebook_path // empty) | strings)' 2>/dev/null)
repos=$(printf '%s\n' "$paths" | while IFS= read -r p; do
    [ -d "$p" ] || p=$(dirname "$p"); [ -d "$p" ] && echo "$p"
  done | sort -u | while IFS= read -r d; do git -C "$d" rev-parse --show-toplevel 2>/dev/null; done | sort -u)

echo "## Repos touched (uncommitted and unpushed work survives a compact on disk, but only the summary remembers why)"
echo
if [ -z "$repos" ]; then echo "- none found in the transcript"; fi
printf '%s\n' "$repos" | while IFS= read -r r; do
  [ -n "$r" ] || continue
  branch=$(git -C "$r" symbolic-ref --short HEAD 2>/dev/null || echo detached)
  dirty=$(git -C "$r" status --porcelain 2>/dev/null | grep -c .)
  if [ -z "$(git -C "$r" remote 2>/dev/null)" ]; then unpushed="no remote"
  else unpushed="$(git -C "$r" log --branches --not --remotes --oneline 2>/dev/null | grep -c .) unpushed commits"; fi
  echo "- $r — branch $branch, $dirty uncommitted files, $unpushed"
done
echo

# --- checkpoints -----------------------------------------------------------------------
# /checkpoint and the compact hook key their folder by repo root (or the symlink-free
# working directory), so look under this session's root and under every repo it touched.
echo "## Checkpoints (CHECKPOINT.md = /checkpoint, latest.md = last compact summary)"
echo
found=$({ git rev-parse --show-toplevel 2>/dev/null || pwd -P; printf '%s\n' "$repos"; } | sort -u | while IFS= read -r r; do
    [ -n "$r" ] || continue
    for f in CHECKPOINT.md latest.md; do
      f="$HOME/.claude/checkpoints/$(slugify "$r")/$f"
      [ -f "$f" ] && echo "- $f ($(age "$f") old)"
    done
  done)
if [ -n "$found" ]; then printf '%s\n' "$found"; else echo "- none for this folder or the repos touched"; fi
exit 0
