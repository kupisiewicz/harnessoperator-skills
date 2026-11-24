---
description: Say whether to compact now and whether it is safe: context size measured from the transcript, plus work in flight and unsaved state
argument-hint: "[optional: a transcript path]"
---

Answer two questions about this session, in three lines: should the user compact, and is it safe right now. Read-only: change nothing, and never start a compaction yourself. Transcript, if given: $ARGUMENTS

## 1. Measure (script, read-only)

Run from the session's working directory (pass the transcript path if one was given above):

`bash ~/.claude/hooks/harnessoperator/compact-check.sh`

It prints the context size from the last model turn's token usage, the window and how it was determined, a `should compact` level, every repo this session touched with its uncommitted and unpushed counts, and the project's checkpoints with their age. Treat its numbers as facts and don't re-measure them. If it exits non-zero, say the size could not be measured, name `/context` as the way to see it, and still do steps 2 and 3.

## 2. Report what only you know

The script can't see work in flight. Check the conversation and report honestly, even when the answer is inconvenient:

1. **Running.** Background agents, tasks or shells that haven't reported back, and tool calls still awaiting results.
2. **Half done.** A multi-step edit, migration, rebase or deploy that has started and not finished.
3. **Waiting on the user.** A question you asked that has no answer yet.
4. **Only in context.** Decisions, failed approaches, the next step, or repos touched only through shell commands, that no checkpoint, commit or file records. A checkpoint older than the last meaningful work doesn't cover it.

## 3. Verdict

Use the script's level for COMPACT. One override: if the next task is unrelated to everything so far, say `yes` at any size.

SAFE NOW is:

- **no** when anything in 1–3 exists. Compacting mid-flight leaves results arriving in a context that no longer knows what they were for.
- **after /checkpoint** when 1–3 are clear but item 4 exists, or the script shows uncommitted or unpushed work and no checkpoint newer than it.
- **yes** otherwise.

The compact hook saves the raw transcript and the summary on every compaction, so nothing is unrecoverable. But the summary is a narrative the model writes unattended, and digging in a transcript is slow. `/checkpoint` is the verified record, so recommend it whenever state is uncaptured. Never recommend a commit or a push the user didn't ask for; name the dirty repo and let `/checkpoint` record it.

Print exactly this and nothing else:

```
COMPACT: <yes|soon|no> — context ≈<N>k of <W>k (<P>%)<, window assumed>.
SAFE NOW: <yes|after /checkpoint|no> — <up to three reasons, most blocking first; "nothing in flight, state captured" when clean>.
DO FIRST: <ordered steps, e.g. "wait for 2 agents, /checkpoint, then /compact"; "nothing" when none>.
```

Rules:
- Numbers come from the script, rounded to whole thousands. Add `, window assumed` only when the script says ASSUMED.
- Name things exactly: which agents, which repo, how many files. No vague words ("some", "probably").
- Never print secret values or quote the transcript.
