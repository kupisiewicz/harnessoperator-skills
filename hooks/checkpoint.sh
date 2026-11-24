#!/usr/bin/env bash
# harnessoperator-skills — automatic checkpoint around every Claude Code compaction
# (manual /compact and auto-compact).
#   PreCompact           -> keep the full raw transcript, so nothing the summary drops is lost.
#   PostCompact          -> save the compact summary (shaped by "Compact instructions" in
#                           ~/.claude/CLAUDE.md) as a dated checkpoint + latest.md, warn if it
#                           skipped required sections, prune old checkpoints.
#   SessionStart compact -> tell the fresh context where ITS checkpoint is.
#   SessionStart startup -> one-line pointer to this project's last checkpoint (in an
#                           umbrella folder: also the newest checkpoints of projects in it).
# Files live in ~/.claude/checkpoints/<project-slug>/, never in the repo, so they don't
# dirty git trees or get committed by accident. Must always exit 0: a failing hook must
# never block compaction. Needs bash and jq; git is optional.
# Tests: bash tests/test-checkpoint.sh

umask 077   # summaries and transcripts can quote secrets from the session: owner-only
KEEP_DATED=${HO_CHECKPOINT_KEEP:-10}         # dated summaries kept per project
TRANSCRIPT_DAYS=${HO_CHECKPOINT_DAYS:-60}    # saved transcripts older than this are deleted
REQUIRED_SECTIONS=("In progress" "Not started" "State of the world" "Resume here")

input=$(cat)
field() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
event=$(field .hook_event_name)
session=$(field .session_id); session=${session//[^A-Za-z0-9_-]/}   # becomes part of a filename
session=${session:-unknown}
cwd=$(field .cwd); cwd=${cwd:-$PWD}
base="$HOME/.claude/checkpoints"
slugify() { printf '%s' "$1" | sed 's#[^A-Za-z0-9]#-#g'; }
stamp=$(date +%Y-%m-%d_%H%M%S)

# Used when a session runs from an umbrella folder that holds many projects, so each
# project still gets its own checkpoints instead of all of them sharing the umbrella's.
# pick_project <paths> <folder> <repos-only>: the most-touched child of <folder> among
# the newline-separated <paths>, printed as its project root. A git repo (or worktree)
# is keyed by its root. A plain folder counts too, unless it is hidden: .claude is config
# and .wt-style folders are worktree containers, so inside those only a repo one level
# down qualifies.
pick_project() {
  local name d r
  printf '%s\n' "$1" | while IFS= read -r p; do
      case "$p" in ("$2"/?*) p=${p#"$2"/}; echo "${p%%/*}" ;; esac
    done | sort | uniq -c | sort -rn | while read -r _ name; do
      d="$2/$name"; [ -d "$d" ] || continue   # skip files like notes.md
      if r=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null); then echo "$r"; break; fi
      case "$name" in
        (.*) [ -z "$3" ] && r=$(pick_project "$1" "$d" 1) && [ -n "$r" ] && { echo "$r"; break; } ;;
        (*)  [ -z "$3" ] && { (cd "$d" && pwd -P); break; } ;;
      esac
    done
}
# Judged from the last 20 MB of the transcript: entry cwds + file paths of tool calls.
busiest_project() {
  [ -f "$1" ] || return 1
  local paths r
  paths=$(tail -c 20000000 "$1" | jq -Rr 'fromjson? | (.cwd // empty),
      (.message.content[]? | select(.type? == "tool_use") | .input
       | (.file_path // .path // .notebook_path // empty) | strings)' 2>/dev/null)
  r=$(pick_project "$paths" "$cwd" "")
  [ -n "$r" ] && echo "$r"
}

# Inside a repo, key by its root so a session started in repo/sub shares repo's folder.
if root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
  umbrella=
else
  # Symlink-free like git's roots, so /summary and the startup pointer find the same folder.
  root=$(cd "$cwd" 2>/dev/null && pwd -P) || root=$cwd; umbrella=1
  # Pre- and PostCompact read the same transcript, so both pick the same project.
  case "$event" in PreCompact|PostCompact)
    project=$(busiest_project "$(field .transcript_path)") && root=$project ;;
  esac
fi
dir="$base/$(slugify "$root")"

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }   # GNU first: BSD stat has no -c
age() {   # "3h" / "2d" since the file was last written
  local s=$(( $(date +%s) - $(mtime "$1") ))
  [ $s -lt 86400 ] && echo "$((s / 3600))h" || echo "$((s / 86400))d"
}

case "$event" in
  PreCompact)
    mkdir -p "$dir"
    transcript=$(field .transcript_path)
    [ -f "$transcript" ] || exit 0
    # One file per session, hardlinked: costs no disk while the live transcript exists,
    # and survives Claude Code's own transcript cleanup. cp only across filesystems.
    target="$dir/${session}.transcript.jsonl"
    ln -f "$transcript" "$target" 2>/dev/null || cp "$transcript" "$target"
    ;;
  PostCompact)
    mkdir -p "$dir"
    summary=$(field '.compact_summary // .summary')
    [ -z "$summary" ] && summary="EMPTY SUMMARY — PostCompact payload had no summary field. Keys: $(jq -c 'keys' <<<"$input" 2>/dev/null)"
    # Compaction runs unattended, so check here that it obeyed Compact instructions.
    missing=()
    for s in "${REQUIRED_SECTIONS[@]}"; do grep -qi -- "$s" <<<"$summary" || missing+=("$s"); done
    file="$dir/${stamp}_${session}.md"
    {
      echo "# Checkpoint — $cwd — $stamp"
      echo "session: $session · trigger: $(field .trigger)"
      [ ${#missing[@]} -gt 0 ] && echo "INCOMPLETE — summary is missing: $(IFS=,; echo "${missing[*]}" | sed 's/,/, /g'). Grep the transcript for these."
      echo
      echo "$summary"
    } > "$file"
    # latest.md is what /summary reads: drop the model's <analysis> scratchpad
    # (~20% of the size, no resume value). The dated file keeps it.
    sed '/^<analysis>/,/^<\/analysis>/d' "$file" > "$dir/latest.md"
    # Retention. A hardlinked transcript becomes a real copy once Claude Code deletes
    # the original, so old ones would grow without bound.
    ls -t "$dir"/20*_*.md 2>/dev/null | tail -n +$((KEEP_DATED + 1)) | tr '\n' '\0' | xargs -0 rm -f
    find "$dir" -maxdepth 1 -name '*.transcript.jsonl' -mtime +"$TRANSCRIPT_DAYS" -delete 2>/dev/null
    [ ${#missing[@]} -gt 0 ] && jq -n --arg m "Checkpoint saved, but the compact summary is missing: ${missing[*]}. See $dir/latest.md" '{systemMessage:$m}'
    ;;
  SessionStart)
    manual=$( [ -f "$dir/CHECKPOINT.md" ] && echo "$dir/CHECKPOINT.md")
    if [ "$(field .source)" = startup ]; then
      # A brand-new session: just say a checkpoint exists, don't load it (cheap).
      newest=$(ls -t "$dir/CHECKPOINT.md" "$dir/latest.md" 2>/dev/null | head -1)
      ctx=${newest:+"Last work checkpoint for this project: $newest ($(age "$newest") old)."}
      if [ -n "$umbrella" ]; then
        # An umbrella folder's work is checkpointed per project below it: name the newest
        # three. Project folders are keyed by symlink-free paths (git resolves them), so
        # match on the physical cwd. shortcut: the prefix also catches a sibling like
        # "<cwd>-old", harmless.
        p=$(slugify "$(cd "$cwd" 2>/dev/null && pwd -P || echo "$cwd")")
        recent=$(ls -t "$base/$p"-*/CHECKPOINT.md "$base/$p"-*/latest.md 2>/dev/null \
          | while IFS= read -r f; do d=$(dirname "$f"); case " $seen " in (*" $d "*) continue ;; esac
              seen="$seen $d"; echo "$f ($(age "$f") old)"; done | head -3 | paste -sd ';' - | sed 's/;/; /g')
        [ -n "$recent" ] && ctx="${ctx:+$ctx }Newest checkpoints of projects inside this folder: $recent."
      fi
      [ -z "$ctx" ] && exit 0
      ctx="$ctx Read one only if the user resumes earlier work or runs /summary."
    else
      # This session's own newest checkpoint, not whichever session compacted last. Search
      # every project folder: an umbrella session's summaries live under the project it
      # worked on, and session ids are unique, so this cannot pick up a stranger's file.
      own=$(ls -t "$base"/*/*_"$session".md 2>/dev/null | head -1)
      [ -n "$own" ] && dir=$(dirname "$own") && manual=$( [ -f "$dir/CHECKPOINT.md" ] && echo "$dir/CHECKPOINT.md")
      own=${own:-$( [ -f "$dir/latest.md" ] && echo "$dir/latest.md")}
      [ -z "$own$manual" ] && exit 0
      raw="$dir/${session}.transcript.jsonl"; [ -f "$raw" ] || raw=none
      ctx="Context was just compacted. Checkpoint for this session: ${own:-none}."
      [ -n "$manual" ] && ctx="$ctx A manual /checkpoint file also exists: $manual. Read both; it may be newer or more structured."
      ctx="$ctx Full pre-compact transcript: $raw. Before continuing: re-verify live state (git status, branches, PRs, servers) against the checkpoint; if a detail is missing from the summary, grep the transcript instead of guessing."
    fi
    jq -n --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
    ;;
esac
exit 0
