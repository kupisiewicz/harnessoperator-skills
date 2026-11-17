# Changelog

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
