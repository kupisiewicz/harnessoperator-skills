---
description: Turn a request into a short task brief (goal, focus, done means, scope, don't touch) and confirm it before any work starts
argument-hint: "[task and/or focus, e.g. 'UI is the most important part']"
---

Before any work starts, turn the task into a brief the user can confirm or correct in one read, so a misunderstanding costs one message instead of an afternoon. Arguments: $ARGUMENTS

## 1. Find the task and the focus

The arguments can hold the task, a focus, or both.
- **Focus** is what the user says matters most, how to weigh things, or how to work, for example "UI is the most important part" or "speed over polish". Quote it word for word.
- **Task** is the thing to build or fix. Take it from the arguments if they hold one. Otherwise use the user's latest request in this conversation that isn't done yet.
- **No task anywhere:** ask for it in one line and stop.
- **The task already has a brief** (`BRIEF.md` below, from this conversation) and the arguments are only a focus: update that brief's Focus section, and anything the focus changes. Don't start over.

## 2. Look before you write

Read just enough of the code or area the task touches to name real files, commands and checks. Use your normal search tools. Stop as soon as you can fill every section with facts instead of guesses. Read the project's `CLAUDE.md` and its decision log (`bash ~/.claude/hooks/harnessoperator/decision-log.sh list`) so the brief doesn't contradict a settled choice.

## 3. Write the brief

Locate the folder the same way `/checkpoint` does, including its umbrella rule, then archive any earlier brief and write the new one:

`d=~/.claude/checkpoints/$( (git rev-parse --show-toplevel 2>/dev/null || pwd -P) | sed 's#[^A-Za-z0-9]#-#g'); mkdir -p "$d"; [ -f "$d/BRIEF.md" ] && mv "$d/BRIEF.md" "$d/BRIEF-$(date -r "$d/BRIEF.md" +%F_%H%M%S).md"; echo "$d/BRIEF.md"`

```
# Brief — <project> — <YYYY-MM-DD HH:MM>

## Task
"<the user's words, quoted>"

## Focus
"<the user's focus, quoted>", or "None given".
What it changes: where the effort goes first, what gets checked hardest, and what may stay plain.

## Goal
One sentence: the outcome, as the user would see it.

## Done means
- [ ] <a check anyone can run or see: a command, a URL, a screenshot, a test name>

## In scope
## Out of scope
What will NOT be done, so it isn't silently added or silently expected.

## Don't touch
Files, services, data and environments that stay as they are (production, generated files, other people's work).
Write each path or glob in backticks (`data/*.generated.js`, `config/`): a hook refuses edits to those. Prose items are advisory.

## Assumptions
Choices made without asking. Each one is the user's to veto.

## Open questions
Only questions whose answer changes the work. Otherwise "None".
```

Rules:
- Use the user's words. Never strengthen them, and never turn your own preference into their requirement.
- A focus changes priority, not scope. Work outside the focus is still done to the normal standard unless the user says otherwise.
- Every "Done means" item must be checkable. "Works well" isn't a check; "`npm test` passes, and the form shows an error on an empty email" is. Put each command in backticks: when a turn that changed code calls the task done, the evidence gate checks that each one ran after the last edit.
- Exact paths, commands and URLs. Keep the whole brief under about 40 lines.
- Never put secret values in it. The folder is outside the repo, so the brief is never committed.

## 4. Confirm

Show the brief in chat, followed by its path. If there are open questions, ask them. Otherwise ask one line: "Go?" Start work only after the user's yes or correction. A correction updates the brief first.

During the work, the brief is the contract. Check "Done means" before saying the task is done. If the scope has to change, say so and update the brief instead of drifting. `/checkpoint` takes its Goal from it.
