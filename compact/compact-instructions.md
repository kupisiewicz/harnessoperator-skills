## Compact instructions

Every compaction (manual or auto) must produce a resumable checkpoint, not a
narrative. A PostCompact hook saves it to `~/.claude/checkpoints/<slug>/latest.md`,
which `/summary` reads. Keep the standard numbered summary sections and extend
them; don't replace them. Use exact paths, branches, SHAs, PR URLs, versions and
commands. Mark anything not verified as UNVERIFIED, and never state a file path
as existing unless you saw it.

- **Pending Tasks** → split into **In progress** (each item: exact stopping
  point, very next command or edit, blocker) and **Not started** (priority
  order). Always write all four headings (In progress, Not started, State of
  the world, Resume here), with "None" under any that are empty: the hook flags
  a summary that is missing one as INCOMPLETE.
- **Current Work** → end it with **State of the world** (each repo: branch,
  clean/dirty, pushed/unpushed; open PRs; servers and ports; background jobs;
  deployed vs local version) and **Resume here** (3 numbered steps, plus the
  files to read first).
- Add **Decisions** (choice, why, who decided, rejected options) and
  **Gotchas** (failed approaches and traps, so they aren't retried).
- Don't paste whole files into it. Name the path and the key lines; the raw
  transcript is kept beside the checkpoint.
