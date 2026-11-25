# Changelog

## Unreleased

- **The brief is enforced, not just written.** A new `PreToolUse` hook, `hooks/brief-guard.sh`, refuses Edit, Write, MultiEdit, NotebookEdit and lean-ctx patches to any path or glob written in backticks under the brief's "Don't touch", and tells the model to ask before changing the brief. When a turn that changed code calls the task done, the evidence gate now checks that every command in backticks under "Done means" ran after the last edit, and names the items that didn't. Both bind only a session whose transcript names the brief, so a brief left from an old task never blocks unrelated work. Prose items stay advisory, and shell writes are not checked. `HO_BRIEF_GUARD=off` disables the guard.

- **`/lesson mine`**: a correction copied into forked or resumed sessions is listed once, not once per copy. The copies keep their timestamp and session id, which is what the dedupe matches on. On the first real run, one message showed up 17 times; across 615 transcripts the hits went from 113 to 71.

- **`/lesson mine [days] [all]`**: finds the corrections nobody filed. `scripts/lesson-mine.sh` reads this project's session transcripts (or every project's with `all`, last 30 days by default) and lists the typed messages that read like corrections, newest first, each with the end of the reply it answered. Hook notes, tool output, agent and scheduled-task messages, sidechains, forwarded tasks, pasted text, bare "stop" and a "no" answering a question are left out. These filters were tuned on real transcripts. The model groups repeats, drops what an existing rule covers, and files only the lessons the user picks.

- **Evidence gate**: "fixed" before a noun ("a fixed version", "fixed width", "a fixed mix") means pinned or constant, not repaired, and is no longer read as a claim that a fix works. "The bug is fixed" still needs a check. This was the gate's third false alarm in live use, and it is now a regression test.

- **Project picking at session start**: a new session in a non-repo folder that holds two or more git repos is told it is in a workspace, not a project. Before the first edit or command, it settles which project the task is in: from the user's message, or by asking in one line with the five most recently active repos offered. It then works from inside that project, so the project's `CLAUDE.md` applies and its checkpoints are filed there. A plain non-repo project, with fewer than two repos below it, is not affected.

- **Evidence gate**: edits to temp files (the session scratchpad, `/tmp`, `/var/folders`) no longer make an earlier check stale. They sit outside the project, so they can't change what the check proved. Found when a helper script written after the test run triggered a false alarm. Covered by a regression test.

- **`/brief [task and/or focus]`**: before work starts, writes the task back as a brief the user confirms: the task and focus in their words, the goal, checkable "Done means", in and out of scope, what not to touch, assumptions and blocking questions. A focus such as `/brief UI is the most important part` changes priority, not scope. It is saved as `BRIEF.md` beside the checkpoints, with earlier briefs archived. A compacted session is pointed back at it, and `/checkpoint` takes its Goal from it.

- **Fix: after a compact, a session could be pointed at another session's checkpoint.** Claude Code can fire SessionStart before PostCompact has written the summary. In an umbrella folder the hook then fell back to the umbrella's `latest.md`, which belonged to whichever session compacted last. It now finds the session's folder from the transcript PreCompact saved, claims `latest.md` only when its `session:` line matches, and says where the summary will land. Found live; now a regression test.

- **`/decision`**: a per-project, append-only `DECISIONS.md` beside the checkpoints. Each entry records what was decided, by whom, why, what was rejected, its scope and its status; a later entry supersedes an earlier one without rewriting it. `scripts/decision-log.sh` handles the path, the next ID and the active list. `/checkpoint` adds its "Decisions made" items, `/summary` lists the active ones, and every new or freshly compacted session is told how many decisions are in force and where.

- **Evidence gate**: "live" for a local tool means installed. When the reply talks about installing, an install script or a `cmp`/`diff` against the installed copy now counts as evidence. A claim that a URL is live still needs a request. A turn that answers the gate's own feedback is never nudged again. Both came from the gate's first live false alarm, and both are regression tests.

- **`/lesson`**: turns a correction into one rule with its why and how to apply it, in the user's own words and never strengthened, filed once in global `CLAUDE.md`, project `CLAUDE.md` or memory. `scripts/lesson-search.sh` lists the possible homes and every existing line on the topic (the global file and its `@imports`, `CLAUDE.md` files up the tree, rules folders, and the memory index, descriptions and feedback notes), so a duplicate is strengthened instead of added and a conflict goes to the user.

- **Evidence gate** (`hooks/evidence-gate.sh`, a `Stop` hook): when the final reply claims tests pass, something is deployed or live, merged or pushed, fixed, or builds, it checks that the turn ran something that shows it, after the last code edit. If not, it sends the model back once to prove the claim or mark it UNVERIFIED. It ignores code, quoted words, negated or hedged sentences, and turns that relayed subagents' work. Replayed over 406 real turns, it blocked 3, all of them claims made from memory. `HO_EVIDENCE_GATE=off` disables it.

- **`/context-audit` inventory**: a memory note that is not in the index but is linked from a topic file the index links now counts as reachable and isn't flagged. Only notes that are neither get reported as unreachable. This lets a large memory keep its always-loaded index small.
- **`/compact-check`**: answers "should I compact, and is it safe right now?" in three lines. `scripts/compact-check.sh` measures the context from the last model turn's token usage in the session transcript, against a window that is detected (`HO_CONTEXT_WINDOW`, a `[1m]` model id, or a context already past 200k) or stated as assumed. It also lists repos touched with uncommitted and unpushed work, and checkpoint age. The model adds work in flight. Read-only.
- **`/context-audit`**: audits everything loaded before the first message. `scripts/context-inventory.sh` measures it from the session transcript: sizes, files cut off on load, memory index faults, dead paths, stray HTML and stale dated claims. The model then judges contradictions, duplicates, misplaced and vague rules. Reports go to `~/.claude/context-audits/<project>/`, and fixes are applied only on approval.
- **Umbrella folders**: a session started outside any repo, in a folder holding several projects, no longer shares one checkpoint folder with every other such session. The compact hook files it under the sub-project its transcript touched most. `/checkpoint` and `/summary` use the same rule, and a new session there lists the newest project checkpoints. Non-repo folders are now keyed by their symlink-free path. Hidden folders are skipped as projects (`.claude` is config), but a repo one level inside one (a `.wt/<branch>` worktree container) still counts.
- **`/checkpoint`** no longer overwrites history: the previous `CHECKPOINT.md` is moved to `CHECKPOINT-<YYYY-MM-DD_HHMMSS>.md` (its write time) before the new one is written.
- **`/swarm N [task]`**: splits a task across N subagents. The mix is ⅔ Sonnet and ⅓ Opus, plus from N = 7 one Fable reviewer per 10 agents, which checks the workers' output after all of them report. A test keeps its mix table in step with the formula.

## 0.1.0 — 2026-11-17

First public release.

- **compact**
  - Every compaction saves a resumable checkpoint to `~/.claude/checkpoints/<project>/`: a dated summary plus `latest.md`, and the raw transcript as a hardlink.
  - Compact instructions in `CLAUDE.md` require the In progress, Not started, State of the world and Resume here sections. Summaries that miss one are flagged `INCOMPLETE`, with a warning.
  - After a compact, the session is pointed at its own checkpoint and transcript.
  - A new session gets a one-line pointer to the project's last checkpoint.
  - Retention: 10 dated summaries per project and 60 days of transcripts. Both can be changed.
- **`/checkpoint`**: a verified, structured `CHECKPOINT.md` that carries items forward and keeps a history.
- **`/summary`**: done, in progress and not started, checked against live git state, with drift detection. `/summary all` gives a table across every project.
- Idempotent `install.sh` and `uninstall.sh`, with backups.
- 78 black-box tests; CI on Ubuntu and macOS.
