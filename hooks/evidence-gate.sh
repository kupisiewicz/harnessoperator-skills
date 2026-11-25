#!/usr/bin/env bash
# harnessoperator-skills — evidence gate: a Stop hook that sends the model back once when
# its final reply claims something this turn never checked.
#
# "Tests pass", "deployed", "merged", "fixed" are the claims a reader acts on, and the ones
# a model most often makes from memory instead of from a command it ran. A rule in
# CLAUDE.md asking for proof is a request; this hook is enforcement. It compares each
# claim in the final reply with the tool calls made since the user's last message, and if
# a claim has no matching evidence it blocks the stop with a reason that says which claim
# and what would prove it. It nudges once per stop (stop_hook_active), never loops, and
# a reply that says UNVERIFIED or "not deployed" makes no claim.
#
# Disable for a session with HO_EVIDENCE_GATE=off. Must always exit 0. Needs bash and jq.
# Tests: bash tests/test-checkpoint.sh

[ "${HO_EVIDENCE_GATE:-on}" = off ] && exit 0
input=$(cat)
field() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
[ "$(field .stop_hook_active)" = true ] && exit 0   # already nudged for this stop
transcript=$(field .transcript_path)
[ -f "$transcript" ] || exit 0

# The turn = everything after the user's last typed message (a string, or text without
# tool results). Final reply = assistant text after the turn's last tool call. Evidence =
# the turn's tool calls, in order, with any shell command spelled out. A turn opened by
# an agent's report, or by this gate's own feedback (the answer to its one nudge), is a
# relay. Comments stay out of the jq program: older jq rejects them.
turn=$(tail -c 5000000 "$transcript" | jq -Rc 'fromjson? | objects | select(.isSidechain != true)' 2>/dev/null | jq -sc '
  def typed_user: .type == "user" and (.message.content | (type == "string")
      or (type == "array" and any(.[]; .type? == "text") and all(.[]; .type? != "tool_result")));
  (map(typed_user) | rindex(true)) as $u
  | if $u == null then empty else . end
  | (.[$u].message.content | tostring | test("<task-notification>|Subagent hand-back|^Stop hook feedback:|Evidence gate: your final reply")) as $relay
  | .[$u + 1:]
  | [.[] | select(.type == "assistant") | .message.content[]? | objects] as $blocks
  | ($blocks | map(.type == "tool_use") | rindex(true)) as $t
  | { relay: ($relay or any($blocks[]; .type == "tool_use" and (.name | test("^(Agent|Task|TaskOutput|SendMessage)$")))),
      reply: ([$blocks[(if $t == null then 0 else $t + 1 end):][] | select(.type == "text") | .text] | join("\n")),
      tools: [$blocks[] | select(.type == "tool_use") | {name, cmd: (.input.command // .input.url // "" | tostring),
              path: (.input.file_path // .input.path // .input.notebook_path // "" | tostring)}] }' 2>/dev/null)
[ -n "$turn" ] || exit 0
# A turn that delegated (subagents, or a turn opened by an agent's report) relays checks
# that ran in another transcript. Re-verifying agents is a review step, not this gate's
# job: it catches claims made from memory.
[ "$(jq -r '.relay' <<<"$turn")" = true ] && exit 0
reply=$(jq -r '.reply' <<<"$turn")
[ -n "$reply" ] || exit 0

# Code and quotations are mentioned, not claimed ("a claim like "deployed""), and a
# sentence that negates or hedges claims nothing.
prose=$(printf '%s\n' "$reply" | awk '/^[[:space:]]*```/{f=!f; next} !f' | sed -E 's/`[^`]*`//g; s/"[^"]*"//g; s/“[^”]*”//g' |
  tr '\n' ' ' | sed -E 's/([.!?;]) +/\1\n/g; s/ — /\n/g' |
  grep -viE "n't|\b(not|nothing|none|neither|nor|never|no longer|unverified|untested|unchecked|haven't|hasn't|without|unless|until|if|once|after|would|should|could|will|pending|yet|next|todo|plan)\b")

# Evidence per kind of claim: the last edit must come before the check, or the check
# proved an older version of the code. Notes, docs and Claude's own memory are not code:
# writing them up after the check is the normal order, so they don't reset it. Nor do
# temp files (a scratchpad helper script that runs the commit, a /tmp note): they sit
# outside the project, so they can't change what the check proved.
# shortcut: a project kept under /tmp is ignored too; upgrade if anyone works there.
tools=$(jq -r '.tools[] | [.name, (.cmd | gsub("[\n\t]"; " ")), .path] | @tsv' <<<"$turn")
last_edit=$(printf '%s\n' "$tools" | awk -F'\t' '($1 ~ /^(Edit|Write|MultiEdit|NotebookEdit)$|ctx_patch/) &&
  $3 !~ /\/\.claude\/|\.(md|txt)$|^(\/private)?\/(tmp|var\/folders)\/|\/scratchpad\// {n = NR} END {print n + 0}')
after_edit=$(printf '%s\n' "$tools" | awk -F'\t' -v e="$last_edit" 'NR > e')
ran() { printf '%s\n' "$after_edit" | grep -qiE "$1"; }

missing=""
need() {   # kind, claim regex, evidence regex, what would prove it, [sentence must also match]
  local hit
  hit=$(printf '%s\n' "$prose" | grep -iE "${5:-.}" | grep -oiE "$2" | head -1)
  [ -n "$hit" ] && ! ran "$3" && missing="$missing
- \"$hit\": $1 claimed, but nothing run after the last edit shows it. $4"
}
test_cmd='\b(test|tests|pytest|jest|vitest|mocha|rspec|phpunit|go test|cargo test|bun test|npm (run )?test|make check|ctest|tox)\b|gh (pr checks|run (view|watch))'
need "a test result" '\b(all )?tests? (now )?(pass(es|ed)?|green|succeed(ed)?)\b|\bpassed [0-9]+\b|[0-9]+ (tests )?pass(ed)?\b|\bci (is )?(green|pass(es|ed)?)\b' \
  "$test_cmd" "Run the tests and quote the result line."
# Tools, hooks and commands have no server: "live" for them means installed on this
# machine. When the reply talks about installing, checking the installed copy (an install
# script, cmp or diff against it) is the evidence. A URL claim still needs a request.
live_evidence='\b(curl|wget|http|ssh|deploy|kubectl|docker|gh run|health)\b|navigate|screenshot|browser|get_page_text|read_page'
printf '%s\n' "$prose" | grep -qiE '\binstall(ed|s)?\b' &&
  live_evidence="$live_evidence"'|\b(install(\.sh)?|cmp|diff)\b'
need "a deploy or live state" '\b(deployed|is live|are live|now live|went live|in production|shipped to prod(uction)?|rolled out)\b' \
  "$live_evidence" "Check the live URL or health endpoint, or the deploy run, and quote it."
# "Merged" and "pushed" are git claims only next to a git word: data gets merged too.
need "a push or merge" '\b(pushed|merged|pr (is )?(opened|created|merged))\b' \
  '\bgit (push|log|merge)\b|\bgh (pr|api)\b' "Show it with git log, gh pr view, or the push output." \
  '\b(pr|prs|pull request|branch|main|master|origin|remote|commit|github|#[0-9]+)\b'
# Bare "confirmed" and "resolved" are left out: they mostly describe data, not a fix.
# "Fixed" before a noun means pinned or constant ("a fixed version", "fixed width"), not
# repaired, so those uses are dropped for this check only. The prefix assignment scopes
# the trimmed prose to this one call.
fix_prose=$(printf '%s\n' "$prose" | sed -E \
  -e 's/(^|[^A-Za-z])([Aa]n?|[Tt]he) [Ff]ixed([^A-Za-z]|$)/\1\3/g' \
  -e 's/[Ff]ixed[- ](price|cost|rate|size|width|height|length|number|count|set|list|mix|order|point|position|version|release|schedule|interval|amount|format|layout|header|footer|term|fee|budget|seed|window)//g')
prose="$fix_prose" need "a fix that works" '\b(fixed|works now|now works|is working|verified)\b' \
  "^(Bash|mcp__[^	]*(shell|run|exec|browser|navigate|screenshot|read_page|javascript|computer))" \
  "Run something after the last edit that exercises the fix (test, request, page) and quote it."
need "a successful build" '\b(builds? (cleanly|fine|successfully)|compiles?( cleanly)?|build (passes|succeeded|is green))\b' \
  '\b(build|make|tsc|compile|cargo|go build|gradle|mvn|xcodebuild|vite|webpack|esbuild|bun build|php -l|bash -n)\b' \
  "Run the build and quote its last line."

# The task brief (/brief) says what done means. When a turn that changed project code
# ends by calling the task done, every "Done means" item that names a command in
# backticks must have run after the last edit. The brief is found the way the brief guard
# finds it (the checkpoint folder of the last edited file's project), and binds only a
# session whose transcript names it.
# shortcut: items without a command ("the form shows an error") can't be matched to a
# tool call and are left to the model; upgrade if screenshots get a convention.
if [ "$last_edit" -gt 0 ] && printf '%s\n' "$prose" |
   grep -qiE '^[[:space:]]*(ok|done)\b|\b(task|work|it|everything|all) (is )?(now )?(done|complete|finished)\b|\bdone means\b|\b(implemented|completed)\b'; then
  last_path=$(printf '%s\n' "$tools" | sed -n "${last_edit}p" | cut -f3)
  e=$(dirname "$last_path"); while [ ! -d "$e" ] && [ "$e" != / ]; do e=$(dirname "$e"); done
  root=$(git -C "$e" rev-parse --show-toplevel 2>/dev/null) || root=$(cd "$e" 2>/dev/null && pwd -P)
  brief="$HOME/.claude/checkpoints/$(printf '%s' "$root" | sed 's#[^A-Za-z0-9]#-#g')/BRIEF.md"
  if [ -n "$root" ] && [ -f "$brief" ] && grep -qF -- "$brief" "$transcript"; then
    runner='^(\./.*|bash|sh|zsh|npm|npx|bun|bunx|node|deno|yarn|pnpm|make|pytest|python3?|php|go|cargo|curl|wget|gh|git|swift|xcodebuild|tox|rspec|jest|vitest|mvn|gradle|docker|ruby|composer|playwright)$'
    set -f   # backticked commands hold globs (tests/*.sh): split them, never expand
    while IFS= read -r item; do
      for c in $(printf '%s\n' "$item" | grep -oE '`[^`]+`' | tr -d '`' | tr ' ' '\037'); do
        # A command's key is its program and its first argument that isn't a flag, after
        # any VAR=value prefix: "SH=/bin/bash bash tests/x.sh -v" -> bash + tests/x.sh.
        # shellcheck disable=SC2046 # split on purpose; globbing is off (set -f)
        set -- $(printf '%s' "$c" | tr '\037' ' ')
        while [ $# -gt 0 ] && case "$1" in (*=*) true ;; (*) false ;; esac; do shift; done
        [ $# -gt 0 ] && printf '%s' "$1" | grep -qE "$runner" || continue
        w=$1; shift; arg=""
        for a in "$@"; do case "$a" in (-*) ;; (*) arg=$a; break ;; esac; done
        printf '%s\n' "$after_edit" | cut -f2 | grep -F -- "$w" | grep -qF -- "${arg:-$w}" && continue
        missing="$missing
- Brief \"Done means\": $(printf '%s' "$item" | sed -E 's/^[[:space:]]*- \[.\] *//') — \`$(printf '%s' "$c" | tr '\037' ' ')\` was not run after the last edit. Run it and quote the result, or say which item is still open."
      done
    done <<<"$(awk '/^## /{on = ($0 ~ /^## Done means/); next} on && /^[[:space:]]*- /' "$brief")"
    set +f
  fi
fi

[ -z "$missing" ] && exit 0
reason="Evidence gate: your final reply makes claims this turn never checked:$missing
Run the checks now and report what they show, or reword each claim as UNVERIFIED. If the proof is from an earlier turn, say which turn and what it showed. You get this message once per stop."
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
