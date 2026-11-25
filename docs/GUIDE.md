# Harness Operator Skills: the guide

**Agents forget, guess and over-claim.
These skills make them remember, ask and prove.**

This is the long-form companion to the [README](../README.md): what every skill is for,
eight situations where they change the outcome, and why they are worth running if you
operate AI coding agents all day. Install and configuration details stay in the README.

8 commands · 2 hooks · 174 black-box tests · CI on Ubuntu and macOS · needs only bash and jq

---

## The problem: long sessions fail in a few repeatable ways

Skill alone doesn't keep a long agent session on track. What does is how the session
handles its own memory, scope and claims. These are the failures operators keep fixing
by hand, and the skill that takes each one over.

| What goes wrong | Skill | What changes |
|---|---|---|
| Context fills up, the session compacts, and the summary loses the exact stopping point and the branch nobody pushed. | compact · `/checkpoint` · `/summary` · `/compact-check` | Every compaction leaves a checkpoint on disk and keeps the raw transcript. The next context is told where both are. |
| The agent builds the wrong thing, or the right thing with the wrong priorities. | `/brief` | The task, your focus and "done means" are confirmed in one read before work starts. |
| A session opens in a folder of 400 repos and starts editing the wrong one. | project picking | It settles which project it's working on before the first edit. |
| "Tests pass", "deployed", "merged" get said without being checked. | evidence gate | A claim with no check this turn sends the agent back once to prove it. |
| You type the same correction again next week. | `/lesson` | The correction becomes one rule, in your words, filed in one place. |
| A choice settled three sessions ago comes back as a fresh question. | `/decision` | An append-only log, named at every session start. |
| You staff subagents by writing a paragraph each time. | `/swarm` | One line, with a fixed model mix and a reviewer. |
| Instructions that load at every start pile up, contradict each other and go stale. | `/context-audit` | What loads is measured, its faults are proven, and fixes are applied only on your approval. |

## Where they fit: one session, start to resume

| Stage | Skills | What happens |
|---|---|---|
| **Open** | startup pointer · project picking · decision count | The session is told where the last checkpoint is and how many decisions are in force. In a workspace folder, it settles the project first. |
| **Agree** | `/brief` | Task, focus and checkable "done means", confirmed before any code. |
| **Build** | `/swarm` · `/lesson` · `/decision` | Fan out across agents. Corrections become rules. Choices are logged. |
| **Freeze** | `/checkpoint` · `/compact-check` | A verified record, then a three-line answer: compact now, and is it safe? |
| **Survive** | compact hook | The summary is saved and checked, and the raw transcript is kept. |
| **Continue** | `/summary` | Done, in progress and not started, checked against live git state. |

The **evidence gate** runs at every stop of every turn. No claim of "passes", "live" or
"merged" gets through without a check run after the last code edit.

---

## Every skill: what it does and why it's different

### Remember: state lives in files, not in the context window

#### compact (automatic)

Hooks around every compaction, manual or automatic. **PreCompact** keeps the full raw
transcript as a hardlink. **PostCompact** saves the summary as a dated checkpoint plus
`latest.md`. **SessionStart** points the fresh context at *its own* checkpoint.

- Summaries must have In progress, Not started, State of the world and Resume here. A
  summary missing one is marked `INCOMPLETE`, with a warning.
- One folder per project, outside the repo, readable only by you.
- Always exits 0, so a failure can never block a compaction.

**What's different:** compaction usually loses things without saying so. Here nothing is
lost, because the transcript is kept and the next context is told where it is.

#### `/checkpoint [focus]`

Writes a structured, verified `CHECKPOINT.md`: goal, done (with how each item was
verified), in progress (with the exact next command), not started, decisions, gotchas,
state of the world, and where to resume.

- Runs `git status` and finds unpushed branches before it writes. Anything it didn't
  check is marked UNVERIFIED.
- Moves the previous checkpoint to a dated file first, so the history stays.
- Copies its decisions into the decision log.

**What's different:** it records what *is* true, not what was planned.

#### `/summary [all | focus]`

Done, in progress and not started, rebuilt from the latest checkpoint and checked against
the repo as it is now. `/summary all` is one table covering every project.

- Reports **drift**: what the checkpoint says against what git shows now.
- Writes a checkpoint first if none exists.

**What's different:** it replaces the long "summarise what's done, in progress and not
started" prompt with one word, and checks the answer.

#### `/compact-check`

Answers two questions in three lines: is the context big enough to be worth compacting,
and would compacting right now lose anything?

```
COMPACT: soon — context ≈142k of 200k (71%)
SAFE NOW: no — 2 agents running; api has 3 uncommitted files
DO FIRST: wait for the agents, /checkpoint, then /compact
```

**What's different:** it measures the context from the token usage the API reported,
instead of guessing. It also lists the uncommitted and unpushed work in every repo the
session touched. It changes nothing.

### Agree: settle what the work is before it starts

#### `/brief [task and/or focus]`

Reads just enough of the code to name real files and checks, then writes the task back as
a brief: task and focus quoted, goal, checkable **done means**, in and out of scope, don't
touch, assumptions, and only the questions that block.

```
/brief UI is the most important part
```

- A focus decides what gets done first and checked hardest. Everything else is still done
  properly.
- Waits for "Go". Saved beside the checkpoints, so a compacted session is pointed back at
  it.

**What's different:** a misunderstanding costs one message, not an afternoon. "Done"
means something you can check.

#### project picking (automatic)

A session opened in a folder holding two or more git repos is told it's in a workspace,
not a project. Before the first edit or command it settles which project the task is for.
It takes the project from your message, or asks in one line and offers the five most
recently active repos.

- It then works from inside that project, so the project's `CLAUDE.md` applies.
- Its checkpoints land in that project's own folder.

**What's different:** without it, a session in a big workspace folder starts on whichever
project it guesses.

### Prove: a rule asks, a hook makes it happen

#### evidence gate (every stop)

A `Stop` hook. When the final reply claims tests pass, something is deployed, merged,
pushed, fixed or builds, it checks that this turn ran something that shows it, after the
last code edit.

- Code, quoted words, negated or hedged sentences, and turns that relay subagents' work
  claim nothing.
- One nudge, never a loop. The agent proves the claim, marks it UNVERIFIED, or names the
  earlier turn that proved it.
- Replayed over 408 real turns, it blocked 4, all of them claims made from memory.

**What's different:** "verify before you claim" stops being a hope written in CLAUDE.md
and becomes a check that runs every time.

### Learn: say it once, it stays said

#### `/lesson [correction]`

Turns a correction into one rule, with its **why** and **how to apply it**. It is filed
once: in global `CLAUDE.md`, the project's `CLAUDE.md`, or memory, depending on how far the
rule reaches and how long it holds.

- Searches every existing rule first. A duplicate is strengthened instead of added again,
  and a conflict goes to you.
- Never strengthens your words: "prefer" stays a preference.

**What's different:** rules don't pile up as near-copies that slowly contradict each
other.

#### `/decision [choice]`

A per-project, append-only `DECISIONS.md`. Each entry records what was decided, who
decided it, why, what was rejected, and what it applies to.

```
## D1 — Name the command /compact-check
- Decided by: user
- Rejected: /docompact, /shouldcompact
```

**What's different:** every new session is told "N settled decisions" before it reopens
one. "Decided by" must be true, so the model can't pass off its own preference as yours.

### Scale and tune: more agents, and a cleaner start for each one

#### `/swarm N [task]`

Splits a task across N subagents with a fixed mix: ⅔ Sonnet for sweeps, mechanical edits,
tests and docs, and ⅓ Opus for design, tricky logic and security. From N = 7 there is one
Fable reviewer per 10 agents.

- Agents that would edit the same files are merged or put in separate worktrees.
- Reviewers see the workers' output, never the orchestrator's conclusions.
- When the task has fewer real pieces than N, it uses fewer agents rather than inventing
  work.

**What's different:** one line replaces the staffing paragraph, and every swarm includes
a review that isn't anchored to the orchestrator's view.

#### `/context-audit`

Audits everything that loads before your first message: CLAUDE.md files, the memory
index, hook output, skill listings, MCP instructions.

- A script measures sizes and proves faults: files cut off on load, links to missing
  memory notes, dead paths, stale "LIVE" claims.
- The model then judges contradictions, rules in the wrong file and vague rules. A
  duplicate is reported only after a content diff, never because two names are alike.

**What's different:** these files are read at the start of every session. Cleaning them
up improves every later session, not just one.

---

## Eight use cases where they make the biggest difference

Each case is a common situation, what usually happens, and what changes with the skills.

### 1. The refactor that compacts twice
*compact · `/compact-check` · `/checkpoint` · `/summary`*

A three-hour migration across forty files. The context fills up halfway through, and
again near the end.

- **Without:** the second summary says "migration mostly done". The branch with the last
  six files was never pushed, and an approach that already failed gets tried again.
- **With:** `/compact-check` says *not safe yet: 3 uncommitted files*. After
  `/checkpoint` and the compact, the new context is pointed at its checkpoint and the full
  transcript. `/summary` reports the unpushed branch as drift.
- **Gain:** the stopping point, the failed approaches and the unpushed branch all make it
  through the compact.

### 2. Monday morning across twelve projects
*`/summary all` · startup pointer · project picking*

An operator runs agents on a dozen repos from one workspace folder. Last week's sessions
are long gone.

- **Without:** open each repo, scroll through old sessions, and ask each agent to rebuild
  what happened from git log.
- **With:** `/summary all` gives one table: project, checkpoint age, what's in progress,
  next step. A new session in the folder names the newest checkpoints, settles the
  project, and works inside it.
- **Gain:** a portfolio stand-up in one command. Every session starts in the right repo,
  with that repo's rules.

### 3. "All tests pass" that nobody ran
*evidence gate*

The agent edits a file after its last test run, then reports "fixed, all tests pass".

- **Without:** you believe it, merge, and CI fails. The tests passed against the code as
  it was before the last edit.
- **With:** the gate sees the claim, sees no test run after the last edit, and sends the
  agent back once. It re-runs the tests and quotes the result line, or marks the claim
  UNVERIFIED.
- **Gain:** claims you can act on. Every false alarm seen in real use has become a
  regression test.

### 4. A UI-first feature
*`/brief`*

"Add a booking flow", where what matters most is how it looks and feels.

- **Without:** the agent spends its effort on the API, writes a perfect schema, and ships
  a form that just about works. You find out at the demo.
- **With:** `/brief UI is the most important part`. The brief says the UI comes first and
  gets checked hardest, lists done-means as screenshots at phone and desktop widths, and
  puts the API rework out of scope. You confirm it in one read.
- **Gain:** the effort goes where you care most, and "done" is checked against what you
  agreed.

### 5. A correction that sticks
*`/lesson`*

For the third time: "open the PR, never merge until I say so".

- **Without:** you add yet another line to CLAUDE.md. It now holds three versions of the
  rule, worded a little differently, and one of them conflicts with an older exception.
- **With:** `/lesson` finds the existing lines, strengthens one instead of adding another,
  keeps your exact wording and reason, and shows you the conflict with the old exception
  so you can choose.
- **Gain:** one clear rule instead of three near-copies. Later sessions follow it without
  being told again.

### 6. A decision that stays decided
*`/decision` · `/checkpoint`*

You picked a name, a library or an architecture last week, after weighing the options.

- **Without:** a fresh session "helpfully" suggests the option you already rejected, and
  you argue it again.
- **With:** the session starts with "4 settled decisions for this project". The log shows
  who decided, why, and what was rejected. Reversing a decision takes a new entry from
  you, and the history stays.
- **Gain:** settled questions stay settled, and you can always see why.

### 7. A ten-agent audit with a reviewer
*`/swarm`*

Audit a large module for bugs, dead code and missing tests before a release.

- **Without:** you write a paragraph assigning models. Every agent is Opus, so the cost
  goes up, or none is, so the hard parts get skimmed. Nobody checks the findings.
- **With:** `/swarm 10 audit the billing module`: 6 Sonnet, 3 Opus and 1 Fable reviewer.
  The hard parts go to Opus. The reviewer reads the workers' output cold, after all of
  them report.
- **Gain:** the right model for each piece, and a review that isn't anchored to the
  orchestrator's view.

### 8. Sessions that feel slower and more confused
*`/context-audit` · `/lesson`*

Months of rules, memory notes and plugins. Every session starts heavier, and sometimes the
agent follows the wrong rule.

- **Without:** nobody knows what loads at start or how big it is. A file cut off on load
  drops its last rules without warning, and a "LIVE since…" claim was true two months ago.
- **With:** `/context-audit` measures what loads, proves the faults, quotes both sides of
  each contradiction with file:line, and fixes only what you approve, with a backup. The
  next audit is compared with this one.
- **Gain:** a lighter, consistent start for every session, so the fix pays off in every
  later session.

---

## Why operators should run these skills

**The model is good. Most of what goes wrong is in the harness.** Most failures in long
agent sessions don't come from the model writing bad code. They come from state lost at
compaction, a task that was never pinned down, claims nobody checked, and instructions
that drifted. That is the operator's job, and these skills take the repetitive parts of it
over, with files, hooks and checks instead of reminders.

- **Files, not memory.** Checkpoints, briefs and decisions live on disk, per project,
  outside the repo. A compact, a crash or a new session can't take them away.
- **Enforced, not requested.** A line in CLAUDE.md is a request the model can forget.
  Hooks run every time: around every compaction, at every session start, at every stop.
- **Measured, not guessed.** Context size comes from the token usage the API reported.
  Load sizes come from the session transcript. Drift comes from live git. Anything not
  checked is marked UNVERIFIED.
- **Your words, not the model's.** Briefs, lessons and decisions quote you. They never
  strengthen what you said, and they never record the model's preference as yours.
- **Cheap on context.** A session start adds one-line pointers: where the checkpoint is,
  how many decisions, which project. Files are read only when needed, so the skills don't
  add the bloat they exist to fight.
- **Safe by default.** Hooks always exit 0 and never block a compaction. Files are readable
  only by you. Nothing is written into your repo. Audits and lessons change shared files
  only after your yes, with a backup.
- **Tuned on real sessions.** The evidence gate was replayed over 408 real turns before it
  shipped. Each false alarm it raised in live use became a regression test.
- **No dependencies.** bash, jq and git. It runs on macOS's stock bash 3.2 and on Linux,
  with 174 black-box tests on both in CI. Installing twice changes nothing, and uninstall
  removes it all.

## Install

```bash
git clone https://github.com/kupisiewicz/harnessoperator-skills
cd harnessoperator-skills && bash install.sh
```

The installer copies the commands to `~/.claude/commands/` and the hooks and helpers to
`~/.claude/hooks/harnessoperator/`, and wires the hooks into `settings.json`. Your other
hooks are kept. `bash uninstall.sh` reverses it. Turn the gate off for one session with
`HO_EVIDENCE_GATE=off`. Full details: [README](../README.md).
