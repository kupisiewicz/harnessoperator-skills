---
description: Write a durable work checkpoint (done / in progress / not started) to disk before compacting
argument-hint: "[optional focus, e.g. 'only the billing work']"
---

Write a checkpoint of the work in this session so a fresh context can resume with zero re-discovery. Cover ALL of it; if a focus is given here, put that first and in more detail: $ARGUMENTS

Steps:

1. **Locate.** Run this from the session's working directory (not a repo you `cd`'d into). It gives the folder and the timestamp:
   `d=~/.claude/checkpoints/$( (git rev-parse --show-toplevel 2>/dev/null || pwd) | sed 's#[^A-Za-z0-9]#-#g'); mkdir -p "$d"; echo "$d"; date '+%F %H:%M'`
2. **Carry forward.** If `$d/CHECKPOINT.md` or `$d/latest.md` exist, read them first. Keep every item that is still true, so older Done items don't vanish after a compact.
3. **Verify** every repo touched. Report what IS, not what was planned:
   `git status -sb; git branch -vv; git log --oneline -15 --all --decorate; git log --branches --not --remotes --oneline; git worktree list`
   The `--not --remotes` line is the one that shows unpushed branches without an upstream. Also check deploy and health state where relevant. Mark anything unchecked `UNVERIFIED`.
4. **Write** `$d/CHECKPOINT.md`, overwriting it. Keep `## History` at the bottom, with one line per checkpoint: `- <YYYY-MM-DD HH:MM> — <one-line state>`.
5. **Print** its path and a 5-line summary. Skip this when /summary called you, since it presents the result itself.

Rules:
- Exact paths, branch names, commit SHAs, PR URLs, versions and commands. No vague words ("mostly", "should work").
- Never print secret values.
- Never save it inside a repo.
- `<project>` in the title means the folder name of the session's working directory, or the main repo touched.

Structure:

# Checkpoint — <project> — <YYYY-MM-DD HH:MM>

## Goal
The user's original ask, in their words, plus any scope changes they made since.

## Done (verified)
Per item: what, where (files / branch / commit / PR / deployed version), how it was verified (test, curl, screenshot, browser walk).

## In progress
Per item: what exists so far, exact stopping point, the very next command or edit, known blockers.

## Not started
Everything asked for or agreed but untouched, in priority order.

## Decisions made
Choice + why + who decided (user vs me). Include options rejected so they aren't re-litigated.

## User feedback & corrections this session
Anything the user corrected or insisted on; candidates for memory.

## Gotchas found
Traps, failed approaches, misleading errors, environment quirks — what NOT to try again.

## State of the world
Repos/branches/worktrees (clean/dirty, pushed/unpushed), open PRs, running servers/ports, background jobs, scheduled tasks, deployed vs local versions, temp files worth keeping.

## Resume here
Numbered first 3 steps for the next session, and which files to read first.

## Open questions for the user

## History
