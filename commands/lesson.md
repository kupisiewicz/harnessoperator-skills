---
description: Turn a correction into one durable rule, with its why, filed in the right place (global CLAUDE.md, project CLAUDE.md or memory), after checking for duplicates and conflicts
argument-hint: "[the correction, e.g. 'never merge without asking' — empty = the last one here — or 'mine [days] [all]' to find corrections in past sessions]"
---

Turn a correction into a rule that every future session follows, written down once and in the right place. Correction: $ARGUMENTS

If it's empty, take the most recent thing the user corrected, insisted on or confirmed in this conversation. Quote their words. If nothing fits, ask in one line what the lesson is and stop.

## `/lesson mine [days] [all]`: find the corrections nobody filed

If the arguments start with `mine`, don't write a rule yet. Find the corrections in past sessions first:

`bash ~/.claude/hooks/harnessoperator/lesson-mine.sh [days] [all]`

It reads this project's session transcripts from the last 30 days by default, or every project's with `all`. It prints the typed messages that read like corrections, newest first. Each comes with the end of the reply it answered (`AFTER:`).

1. **Judge each candidate.** Keep a message only if it corrects how the model worked: it did something the user didn't want, or forgot a standing preference. Drop new tasks, one-off orders ("stop", "no need to deploy now"), answers to a question, and task briefs written by another session or agent. When unsure, drop it.
2. **Group them.** Corrections that say the same thing are one lesson, and a repeat is the strongest signal. For each group keep the user's clearest wording, the count, and the dates.
3. **Drop what's already a rule.** Run `lesson-search.sh` (step 2 below) with each group's keywords. If a rule already covers it, say so, quoting that rule's `file:line`. When the correction came after the rule was written, offer to strengthen the rule instead of adding a new one.
4. **Present a numbered list,** most repeated first. For each: the proposed rule in the user's words, ×count, the dates, one short quote, and the home it would go to. Say how many candidates you dropped, and why in one line.
5. **Wait.** File only the ones the user picks ("1, 3"), each one through steps 1–4 below. Never file a mined lesson without the user's pick: the user hasn't confirmed it yet.

Transcripts can quote secrets. Never print a secret value from them, and keep quotes to the few words the lesson needs.

## 1. State it

Write three parts, using the user's own words wherever possible:

- **Rule:** one sentence, a behaviour a model can follow. Write "Open the PR and stop; merging is the user's", not "be careful with PRs". If the correction has an exception the user stated, keep it. Never add one they didn't state.
- **Why:** the reason the user gave, or the incident that caused it (date, what went wrong). A rule without a why gets argued with or misapplied.
- **How to apply:** when it triggers and what to do instead, in 1–3 bullets.

Never strengthen the user's words. "Prefer X" stays a preference, not "always X". "In this repo" doesn't become "everywhere".

## 2. Choose where it lives

Pick one home. The first match wins:

1. **Can the harness enforce it?** For example "never edit file X" → a permission deny; "always run Y after editing Z" → a hook. Say so and offer that as well: enforcement beats a rule the model has to remember. Still write the rule; the rule explains the enforcement.
2. **Is it state that will change?** Versions, deploy status, who owns what, open PRs → **memory**, never CLAUDE.md.
3. **Is it only true for this project?** It names its repo, paths, services or conventions → **project CLAUDE.md** if the team should share it; **memory** if it's personal or this machine's.
4. **Is it how the user wants to work everywhere?** Communication, review, git habits, coding style → **global** `~/.claude/CLAUDE.md`.

Then find the existing lines on the topic. Run from the session's working directory, with 3–6 keywords and synonyms of the rule (e.g. `merge "open the PR" "pull request"`):

`bash ~/.claude/hooks/harnessoperator/lesson-search.sh <keyword> ...`

It prints the candidate homes with their paths, and every line in them that mentions the keywords. Read each hit in context, then decide:

- **Same rule already there:** don't add a second one. Strengthen the existing one: add the new incident to its **Why**, the date, and any missing **How to apply**.
- **Contradicting rule:** stop. Show both side by side with `file:line` and ask which one wins. Then change the loser too, so the two can't coexist.
- **Related rule:** write the new one, and link the two (`[[name]]` in memory, or one line of cross-reference in CLAUDE.md).

## 3. Write it

- **Memory:** one file per lesson, `<kebab-name>.md` in the memory folder the script printed. Use this frontmatter: `name`, a one-line `description` that says the rule itself (it's what recall matches on), and `metadata: type: feedback`. The body has the rule in bold, then **Why:** and **How to apply:**. Add one line to `MEMORY.md` under the section that fits: the rule in a few words, linked. No dates or versions in that line.
- **CLAUDE.md (global or project):** one bullet in the section the rule belongs to (create a section only if none fits). Put the reason in the same bullet, in a clause or a second sentence. Back up a global file first: `cp -p f f.bak-lesson-<YYYYMMDD-HHMM>`. Never edit inside a managed block (`<!-- harnessoperator:… -->` or anything an installer owns).
- **Project CLAUDE.md** is committed and shared. Write it, but leave it uncommitted and say so. Commit only if the user asks.

Write without asking when the home is memory or the global file and step 2 found no conflict: the user asked for the lesson. Ask first when the home is a project CLAUDE.md in a repo others use, or when the rule would replace or reverse an existing one.

## 4. Report

Two to four lines: the rule as written, each change as `path:line` (new, strengthened or replaced), and any enforcement offered. Never print secret values a rule or file happens to contain.
