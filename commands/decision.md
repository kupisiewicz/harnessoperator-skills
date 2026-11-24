---
description: Record a settled choice in the project's decision log (DECISIONS.md), or list the decisions in force, so later sessions don't re-argue them
argument-hint: "[the decision, e.g. 'name it /compact-check, not /docompact' — empty = list active decisions]"
---

Keep this project's settled choices in one append-only log, so no later session reopens one without knowing it was decided, by whom and why. Decision: $ARGUMENTS

Run every command from the session's working directory. In an umbrella folder (not a git repo, holding several projects), run them inside the project the decision is about, the same rule `/checkpoint` uses.

## With no decision given: list

`bash ~/.claude/hooks/harnessoperator/decision-log.sh list`

Show the active decisions as printed, plus the file path. Stop there.

## With a decision: record it

1. **Read the log first.** Run `list`, then read the full entries of any active decision on the same topic: `path` prints the file.
   - **Same decision already there:** don't add it again. Say which entry it is.
   - **It reverses or narrows an active one:** say so, quoting that entry's ID and title. Record it only if the user made this decision themselves (their words in this conversation, quoted). Then it supersedes the old one, as in step 3.
2. **Write the entry.** Get the ID with `next` and the folder with `path`. Append it to the end of the file. Start a missing file with the two header lines below.
3. **Superseding:** in the old entry, change only its Status line to `superseded by D<new> (<YYYY-MM-DD>)`, and give the new entry a `Supersedes: D<old>` line. Never delete or reword an old entry: the history is the point.

```
# Decisions — <project>
Settled choices, newest last. Read before reopening one; change one only with a new entry that supersedes it.

## D<n> — <YYYY-MM-DD> — <the decision, as a short imperative title>
- **Decided by:** user | me with user's approval | me (state which, honestly)
- **Why:** <the reason, in the decider's words where possible>
- **Rejected:** <options considered and why not, or "none considered">
- **Applies to:** <scope: this repo, one file, one service…>
- **Status:** active
```

Rules:
- Record decisions, not tasks or facts. "Use bun, not npm, in this repo" is a decision. "Bun is installed" is a fact, and belongs in memory or CLAUDE.md.
- Never strengthen the decider's words, and never record your own preference as the user's: "Decided by" must be true.
- Keep each field to one or two lines. Long reasoning belongs in a checkpoint or a PR, with a link here.
- Never put secret values in an entry.

Report in one line: the ID, the title, and the file path, plus "supersedes D<old>" when it does.
