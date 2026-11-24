# Changelog

## Unreleased

- **Umbrella folders**: a session started outside any repo, in a folder holding several projects, no longer shares one checkpoint folder with every other such session. The compact hook files it under the sub-project its transcript touched most. `/checkpoint` and `/summary` use the same rule, and a new session there lists the newest project checkpoints. Non-repo folders are now keyed by their symlink-free path.
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
