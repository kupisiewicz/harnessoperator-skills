---
description: Show a detailed summary of all work (done / in progress / not started) from the latest checkpoint; writes one first if none exists
argument-hint: "[all | optional focus, e.g. 'only the billing work']"
---

Show me a detailed summary of all the work done here: what is done, what is in progress and what is not started yet. $ARGUMENTS

**If the argument is exactly `all`:** do not run the steps below. Give an overview of every project instead:
1. `ls -lt ~/.claude/checkpoints/*/CHECKPOINT.md ~/.claude/checkpoints/*/latest.md 2>/dev/null`
   For each project folder, take whichever of its two files is newer.
2. Read each chosen file, but only its In progress, Not started and Resume here sections, plus any `INCOMPLETE` line.
3. Present one table, newest first: `| project | checkpoint (age) | in progress | next step |`. The project is the folder name with the shared home-directory prefix dropped (for example `-Users-alice-code-api` becomes `api`). Keep each cell to one short line, and write "—" when there is nothing.
4. Below the table, list the projects with open work, each with its file path. Skip the git re-checks, since this is an overview. Then stop.

Otherwise:

Steps:

1. **Locate.** From the session's working directory:
   `d=~/.claude/checkpoints/$( (git rev-parse --show-toplevel 2>/dev/null || pwd) | sed 's#[^A-Za-z0-9]#-#g'); ls -lt "$d"/CHECKPOINT.md "$d"/latest.md 2>/dev/null`

2. **No checkpoint (neither file exists):** read `~/.claude/commands/checkpoint.md` and follow it exactly, but skip its step 5 (the print). Then go to step 4 using the file it wrote.

3. **A checkpoint exists:** read both files if both exist.
   - Use `CHECKPOINT.md` as the backbone, since it is structured and verified.
   - Take from `latest.md` anything newer.
   - If `latest.md`'s `session:` line is not this session, treat it as another session's work and say so.
   - If this conversation already holds the compact summary (it begins "This session is being continued…"), skip reading `latest.md`; it is the same text.
   - Add any work in this conversation that happened after the newest timestamp.
   - **Re-check live state** in every repo the checkpoint names:
     `git status -sb; git branch -vv; git log --oneline -10 --all --decorate; git log --branches --not --remotes --oneline`
     Also run health or URL checks where the checkpoint claims a deploy.
   - Any Done or In-progress item, or any branch or deploy state, that differs from the checkpoint is **drift**. If there is drift, say so in one line and offer `/checkpoint`. Do not rewrite the file yourself.

4. **Present** in chat, not as a file, with this layout:

```
## Summary — <project> — checkpoint <YYYY-MM-DD HH:MM> (<source file path(s)>)

### Goal
One or two lines.

### ✅ Done
- <what> — <where: file/branch/SHA/PR/version> — <how verified>

### 🔄 In progress
- <what> — stopped at <exact point> — next: <exact command/edit> — blocker: <if any>

### ⏳ Not started
1. <priority order>

### ⚠️ Drift since checkpoint
- <what the checkpoint says vs what is true now> (or "None")

### Decisions & gotchas to remember
- short bullets

### ▶ Resume here
1. 2. 3.

### ❓ Open questions
```

Rules: exact paths, SHAs, URLs and versions. Write UNVERIFIED next to anything not re-checked. Never print secret values. Leave out empty sections, except Drift. End with the path(s) of the checkpoint file(s) used.
