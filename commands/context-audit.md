---
description: Audit what loads into every session (CLAUDE.md, memory, hooks, skills, MCP) for size, contradictions, staleness and duplicates; propose fixes, apply only on approval
argument-hint: "[optional: a transcript path, or a focus such as 'memory only']"
---

Audit the standing context of this project: everything the model reads before the user types. Every flaw found here is paid for in every future session, so be thorough and exact. Focus or transcript, if given: $ARGUMENTS

## 1. Measure (script, read-only)

Run from the session's working directory (pass a transcript path if one was given above):

`bash ~/.claude/hooks/harnessoperator/context-inventory.sh`

It reads the newest session transcript of this project, which records exactly what Claude Code loaded at start. It prints a table of what was loaded with sizes, any cut-off file, memory index faults, dead paths, stray HTML and old dated claims. Treat its numbers as facts and don't re-measure them. The system prompt and tool schemas aren't in it: they're fixed by the harness and can't be edited.

## 2. Read everything that loaded

Read every instruction file the table lists, in full: user and project `CLAUDE.md`, imported files, rules, and the memory index. Read the hook texts in the transcript, at the lines the table names. Don't load the 100+ memory files behind the index; open one only when an index line needs checking.

## 3. Judge — the part only you can do

Find each of these. Cite every finding as `file:line` with a quote under 15 words.

1. **Contradictions.** Two rules that can't both be obeyed, across all loaded sources, including hooks and the output style. Name both sides, and which one the model will probably follow (a later, more specific or louder rule usually wins). Ask the user which one they mean; never guess.
2. **Duplicates.** The same rule in two or more places, or reworded. Propose one home and delete the others.
3. **Misplaced rules.**
   - A project-only rule in the global file costs every other project.
   - A universal rule in a project file is missed elsewhere.
   - State, such as versions, "LIVE" or deploy status, belongs in a memory file, not in an always-loaded index line.
   - Long reference text belongs behind a pointer the model reads on demand.
4. **Stale state.** Verify every dated claim and dead path the script flagged, plus any other "LIVE", version or "currently" claim, using the cheapest real check: `test -e`, `git log`, `gh`, `curl -sI`. Report it as stale only when the check fails. Otherwise say it is current, or say why you could not check.
5. **Vague or unactionable rules.** "Be careful", "write good code", "always do your best" give the model nothing to act on. Rewrite each one as a concrete behaviour, or drop it.
6. **Weight.** Use the table. The largest items that are *editable* (skill and plugin lists, MCP servers, memory index, CLAUDE.md sections) are the candidates for trimming. For each, estimate the tokens saved per session and what would be lost.
7. **Noise.** Broken markup, leftover template text, unfinished sentences, raw HTML.

Don't flag what is working: a long file that is all signal is fine.

## 4. Report

Write the report to `~/.claude/context-audits/<slug>/<YYYY-MM-DD_HHMM>.md`. `<slug>` is the project path with every non-alphanumeric character replaced by `-`, the same rule as checkpoints. If an earlier audit exists in that folder, compare totals and say what improved and what regressed.

```
# Context audit — <project> — <YYYY-MM-DD HH:MM>
Loaded: ≈<N> tokens before the first message (<transcript>)

## Fix first (ranked by effect on every session)
1. <finding> — <file:line> — <proposed edit> — saves ≈<n> tokens / removes <risk>

## Contradictions
## Duplicates
## Misplaced
## Stale (verified)
## Vague
## Weight (editable, largest first)
## Noise
## Checked and fine
```

Then show the user the **Fix first** list and the contradictions in chat: short, with the report's path.

## 5. Fix — only after the user says which

- Change nothing until the user approves specific items. "Fix all" counts as approval.
- Back up every file outside a git repo before editing it: `cp -p f f.bak-context-audit-<stamp>`.
- Never edit a managed block, such as `<!-- harnessoperator:… -->` markers or anything an installer owns. Fix it at its source instead.
- Never edit a generated file. Fix the file it is built from.
- When you merge duplicates, keep the strongest wording and the **Why**.
- Moving a rule out of an always-loaded file must leave a one-line pointer wherever the model needs to find it.
- Never print secret values found in any file.
- After fixing, run the script again and report the new total next to the old one.
