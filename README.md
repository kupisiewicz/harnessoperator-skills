# harnessoperator-skills

<p><strong>Your coding agent forgets, guesses and says "done" too early.<br>
These skills make it remember, agree and prove.</strong></p>

**What this is:** add-ons for [Claude Code](https://docs.claude.com/en/docs/claude-code)
that fix the ways long agent sessions go wrong. They include 10 slash commands and 3 hooks
that run on their own. You install them with one script. They need only `bash` and `jq`,
and nothing leaves your machine.

**Who it's for:** anyone who runs AI coding agents for hours a day, across many projects:
"harness operators".

**What changes:** work survives compaction and new sessions. The agent confirms the task
before it builds. It can't say "tests pass" or "deployed" without a check. And the setup
tells you when something in it is broken.

---

## The skills, in three groups

### 1. Remember: nothing is lost between sessions

When the context fills up, Claude Code replaces the conversation with a summary, and the
exact stopping point, the unpushed branch and the failed approach go with it. These skills
keep the state on disk instead.

| Skill | What it does | How it runs |
|---|---|---|
| **compact** | Turns every compaction into a resumable checkpoint file and keeps the raw transcript. It warns when the summary skipped something. | Automatic |
| **`/checkpoint`** | Writes a verified record: done, in progress, not started, decisions, gotchas, and where to resume. | You type it |
| **`/summary`** | Answers "where are we?" from the checkpoint, checked against live git. `/summary all` covers every project. | You type it |
| **`/compact-check`** | Answers in three lines: should I compact, and is it safe right now? | You type it |
| **`/decision`** | Logs a settled choice once, with the reason. Every new session is told it's in force. | You type it |
| **`/lesson`** | Turns a correction into one rule, filed once. `/lesson mine` finds the corrections you never filed. | You type it |

### 2. Prove: the agent builds what you asked and shows it works

| Skill | What it does | How it runs |
|---|---|---|
| **`/brief`** | Before any code, writes the task back as a short brief you confirm: your words, your focus, checkable "done means", scope, what not to touch. | You type it |
| **brief guard** | Blocks edits to anything the brief lists under "Don't touch". | Automatic |
| **evidence gate** | When the agent claims "tests pass", "deployed", "merged" or "fixed", it checks that this turn actually ran something that shows it. If not, it sends the agent back once. It also holds "done" to the brief's checks. | Automatic |

### 3. Run: operate the harness at scale and keep it healthy

| Skill | What it does | How it runs |
|---|---|---|
| **`/swarm N`** | Splits a task across N subagents with a fixed model mix and a reviewer who checks their output. | You type it |
| **`/context-audit`** | Measures everything loaded before your first message and finds contradictions, duplicates and stale rules. It fixes them only with your OK. | You type it |
| **`/doctor`** | Checks that every hook, setting and command is installed, wired and working, and names the fix for each problem. | You type it |
| **`/cure`** | Applies `/doctor`'s fixes. Safe ones run on their own; the rest need your OK. Then it checks again. | You type it |
| **project picking** | In a folder holding many repos, a new session settles which project it's in before its first edit. | Automatic |

**New here?** [docs/GUIDE.md](docs/GUIDE.md) explains every skill in depth and makes the
case for running them.

## How to use them: one working day

```
morning     /summary all              what's open in every project, and the next step
start task  /brief UI matters most    agree on the task; nothing is built until you say go
work        (automatic)               gate checks claims · guard protects files · compaction saved
milestone   /checkpoint               a verified "last known good"
you correct /lesson                   the correction becomes a rule, filed once
you decide  /decision                 settled, and every later session knows it
big job     /swarm 6 audit billing    six agents, the right models, one reviewer
weekly      /doctor  →  /cure         is everything still working? fix what isn't
```

## Use cases

| Situation | Without | With |
|---|---|---|
| A long refactor compacts twice | The summary forgets the unpushed branch and the failed approach. | `/summary` resumes from a verified checkpoint, checked against git. |
| Monday morning, twelve projects | You open each one to remember where it stood. | `/summary all` gives one table: what's open, what's next. |
| "All tests pass" | Said from memory; nobody ran them. | The gate sends the agent back to run them and quote the result. |
| A UI-first feature | The agent polishes the backend and rushes the screen. | `/brief UI is the most important part` sets the priority before any code. |
| A generated file | Edited by hand, then overwritten on the next build. | Listed under "Don't touch", so the guard blocks the edit. |
| The same correction, again | You type it every week. | `/lesson` files it once; `/lesson mine` finds the ones you forgot. |
| A choice made last week | Comes back as a fresh question. | `/decision` logs it; new sessions are told it's settled. |
| The hooks stopped firing | Silent. You notice weeks later. | `/doctor` names the problem; `/cure` fixes it and checks again. |

---

## Quick start

```bash
git clone https://github.com/harnessoperator/harnessoperator-skills.git
cd harnessoperator-skills
./install.sh
```

Then **start a new Claude Code session**, since hooks load at session start.

**Requirements:** `bash`, `jq` (`brew install jq` or `apt install jq`), and a Claude
Code version with `PreCompact`, `PostCompact`, `SessionStart`, `Stop` and `PreToolUse` hooks. `git` is
optional; it is used to find the repo root and to check branch state. macOS and Linux
are supported, and CI runs the test suite on both.

`install.sh` is safe to run again, for example to update after a `git pull`. It
merges into your existing settings instead of replacing them, never duplicates its
own entries, and backs up every file it changes first
(`<file>.bak-harnessoperator-<timestamp>`). Here is exactly what it does:

| Installs | To |
|---|---|
| `commands/checkpoint.md`, `commands/summary.md`, `commands/swarm.md`, `commands/context-audit.md`, `commands/compact-check.md`, `commands/lesson.md`, `commands/decision.md`, `commands/brief.md`, `commands/doctor.md`, `commands/cure.md` | `~/.claude/commands/` |
| `hooks/checkpoint.sh` | `~/.claude/hooks/harnessoperator/checkpoint.sh` |
| `hooks/evidence-gate.sh` | `~/.claude/hooks/harnessoperator/evidence-gate.sh` |
| `hooks/brief-guard.sh` | `~/.claude/hooks/harnessoperator/brief-guard.sh` |
| `scripts/context-inventory.sh` | `~/.claude/hooks/harnessoperator/context-inventory.sh` (run by `/context-audit`, not a hook) |
| `scripts/compact-check.sh` | `~/.claude/hooks/harnessoperator/compact-check.sh` (run by `/compact-check`, not a hook) |
| `scripts/lesson-search.sh` | `~/.claude/hooks/harnessoperator/lesson-search.sh` (run by `/lesson`, not a hook) |
| `scripts/lesson-mine.sh` | `~/.claude/hooks/harnessoperator/lesson-mine.sh` (run by `/lesson mine`, not a hook) |
| `scripts/decision-log.sh` | `~/.claude/hooks/harnessoperator/decision-log.sh` (run by `/decision`, `/checkpoint` and `/summary`, not a hook) |
| `scripts/doctor.sh`, `scripts/cure.sh` | `~/.claude/hooks/harnessoperator/` (run by `/doctor` and `/cure`, not hooks), plus a `source` file naming the checkout it was installed from |
| Hook entries: `PreCompact`, `PostCompact`, `SessionStart` (matcher `compact\|startup`), `Stop` (evidence gate), `PreToolUse` (brief guard, matcher `Edit\|Write\|MultiEdit\|NotebookEdit\|…ctx_patch`) | merged into `~/.claude/settings.json` |
| `compact/compact-instructions.md` | appended to `~/.claude/CLAUDE.md` between `harnessoperator` marker comments |

If your `CLAUDE.md` already has a `## Compact instructions` section that you wrote
yourself, the installer leaves it alone and tells you to merge by hand.

---

## Each skill in detail

### The daily loop

```
 work ──► /checkpoint at a milestone ──► keep working ──► context fills up
                                                              │
                                    compaction (automatic) ◄──┘
                                    • summary saved as a checkpoint
                                    • raw transcript kept
                                    • fresh context told where both are
                                                              │
 /summary ◄── "where are we?" ◄── keep working ◄──────────────┘

 next morning, new session ──► told "last checkpoint: … (14h old)" ──► /summary
 many projects? ──► /summary all
```

### When to use each one

**compact (automatic):** you don't call it. It runs on every manual `/compact` and
every auto-compact. You'll notice it in three places:

- After a compact, the session is told where its checkpoint and full transcript are,
  so it re-checks instead of guessing.
- If the summary skipped a required section, you get a warning, and the file is marked
  `INCOMPLETE`.
- Opening a new session in a project that has a checkpoint adds one cheap line to the
  context: `Last work checkpoint for this project: … (2d old)`. The file itself isn't
  loaded.

**`/checkpoint`:** run it when the state is worth freezing:

| Moment | Why |
|---|---|
| Before a manual `/compact` | The model still holds the full context, so this is the best checkpoint you'll get. |
| At the end of the day, or before switching projects | Tomorrow's session starts from verified facts, not from memory. |
| After a milestone: tests green, PR opened, deploy done | Records exactly what is true, with SHAs, branches and URLs. |
| Before something risky: a big refactor, a migration, a rebase | A clear "last known good" to come back to. |
| Before handing work to another person or agent | Gives a self-contained briefing. |

It verifies before it writes: it runs `git status`, lists branches with no remote, and
checks deploy state, and it marks anything it couldn't check `UNVERIFIED`. It carries
forward every item from the previous checkpoint that is still true, and adds a line
to `## History`. Add a focus to put one area first: `/checkpoint only the billing work`.

**`/summary`:** run it whenever you'd otherwise ask "what's the status?"

| Moment | Why |
|---|---|
| Coming back to a session after a break, or right after a compact | Rebuilds the picture: done, in progress, not started, and what to run next. |
| Starting a new session on old work | Reads the checkpoint, then checks it against live git state. |
| Before a stand-up or status update | A ready-made list with exact SHAs, PRs and versions. |
| `/summary all`, first thing in the morning | One table across every project: what's open and the next step for each. |

If no checkpoint exists, `/summary` writes one first. If the code has moved on since
the checkpoint (new commits, a branch pushed, a deploy changed), it reports the
**drift** and offers `/checkpoint`. It never rewrites the file without asking.

### `/swarm`: one line instead of a staffing paragraph

Instead of typing *"start 4 Sonnet subagents for lighter tasks, 2 Opus for heavier
ones, and a Fable to check their work"* every time, type `/swarm 6` or
`/swarm 10 audit the billing module`.

| N | Sonnet | Opus | Fable |
|---|---|---|---|
| 6 | 4 | 2 | 0 |
| 7 | 4 | 2 | 1 |
| 10 | 6 | 3 | 1 |
| 20 | 12 | 6 | 2 |

The rule: from N = 7 there is one Fable reviewer per 10 agents, rounded up. The rest
split ⅔ Sonnet and ⅓ Opus. The full table is in [`commands/swarm.md`](commands/swarm.md),
and a test keeps it in step with the formula.

- Opus gets design, tricky logic, security and root-cause work. Sonnet gets sweeps,
  mechanical edits, tests and docs.
- Workers launch in parallel, and agents whose work would edit the same files are
  merged or isolated in worktrees.
- The reviewers start only after every worker has reported. They get the workers'
  reports and changed paths, never the orchestrator's conclusions.
- If the task has fewer real pieces than N, it uses fewer agents and says why. It
  never invents busywork.

### `/context-audit`: what every session reads before you type

Everything that loads at session start costs tokens every time. That covers `CLAUDE.md`
files, the memory index, hook output, the skill list, MCP instructions and the output
style. A contradiction in any of them leaves the model guessing which rule you meant.

- **Measured, not guessed.** `context-inventory.sh` reads the newest session
  transcript, which records exactly what Claude Code loaded and how big each part was.
  It prints a table, largest first, plus the faults a script can prove:
  - a file that was cut off when it loaded
  - memory index links to missing files, and memory files that are not in the index or one link away from it
  - paths that no longer exist
  - leftover HTML
  - "LIVE" or "deployed" claims with an old date
- **Judged by the model.** It looks for contradictions (both sides quoted, with
  `file:line`), duplicates, rules in the wrong file, vague rules, and state that belongs
  in memory rather than in an index line. It verifies every stale-looking claim with a
  real check before calling it stale.
- **Tracked.** Each report is saved to `~/.claude/context-audits/<project>/` and
  compared with the previous one.
- **Changes nothing on its own.** Fixes are applied only after you approve them, with a
  backup, and never to installer-managed blocks or generated files.

### `/compact-check`: compact now, or not yet?

Two questions, one short answer: is the context big enough that compacting helps, and
would compacting right now lose anything?

```
COMPACT: soon — context ≈142k of 200k (71%), window assumed.
SAFE NOW: no — 2 background agents still running; api has 3 uncommitted files and no checkpoint.
DO FIRST: wait for the agents, /checkpoint, then /compact.
```

- **Measured, not guessed.** `compact-check.sh` reads the token usage the API reported
  for the last model turn (input + cache read + cache creation). Under 50% of the window
  is `no`, 50–74% is `soon`, 75% or more is `yes`.
- **The window is detected where it can be.** `HO_CONTEXT_WINDOW` wins, then a `[1m]`
  model id, then a context already past 200k (which proves a larger window). Otherwise it
  assumes 200k and the answer says `window assumed`.
- **Safety has two halves.** The script lists every repo the session touched with its
  uncommitted and unpushed counts, and the age of the project's checkpoints. The model
  adds what no file records: agents or shells still running, a half-done edit, a question
  you haven't answered.
- **What a compact already saves.** The hook keeps the raw transcript and the summary, so
  nothing is unrecoverable. `/compact-check` still sends you to `/checkpoint` first when
  state lives only in the context, because that is the verified record.
- **Read-only.** It never compacts, commits or edits anything.

### `/lesson`: a correction, written down once

When you correct the model ("never merge without asking", "comments explain why"),
type `/lesson`, or `/lesson <the correction>`, and it becomes a rule that future
sessions follow:

- **Stated in your words.** The rule as one behaviour, its **Why** (your reason or the
  incident), and **How to apply**. It never strengthens what you said: "prefer" stays a
  preference, and "in this repo" doesn't become "everywhere".
- **Filed in one home.**
  - State that will change goes to memory.
  - A project-only convention goes to that project's `CLAUDE.md` (shared) or memory
    (personal).
  - How you work everywhere goes to the global `~/.claude/CLAUDE.md`.
  - If a hook or a permission could enforce it, it says so too.
- **Checked against what's already there.** `lesson-search.sh` lists the homes and every
  existing line on the topic: the global file and its `@imports`, every `CLAUDE.md` from
  here up, rules folders, and the memory index, descriptions and feedback notes. If the
  rule already exists, it's strengthened instead of duplicated. If it conflicts with an
  existing rule, you choose which one wins, and the loser is changed too.
- **Asks only when it should.** Memory and the global file are written straight away,
  with a backup. A project `CLAUDE.md` that others share, or a rule that reverses an
  existing one, waits for your yes.
- **Mines the corrections you never filed.** `/lesson mine [days] [all]` reads past
  session transcripts (this project's, last 30 days by default) and lists the typed
  messages that read like corrections ("No, I told you…", "why did you…", "never…"),
  each with the end of the reply it answered. Answers to questions, bare orders like
  "stop", hook notes, agent messages and pasted text are left out. The model groups the
  repeats, drops anything an existing rule already covers, and shows a numbered list.
  It files only the ones you pick.

### `/decision`: settled once, not argued again

A checkpoint is replaced every time, and a compact summary is a narrative, so a choice
made three sessions ago tends to come back up as a fresh question. `/decision` keeps
them in `~/.claude/checkpoints/<project>/DECISIONS.md`:

```
## D3 — 2026-11-24 — Name the command /compact-check
- **Decided by:** user
- **Why:** /docompact reads like an order to compact; the command only advises
- **Rejected:** /docompact, /shouldcompact
- **Applies to:** harnessoperator-skills
- **Status:** active
```

- `/decision <the choice>` records one. With no text, `/decision` lists the ones in
  force.
- **Append-only.** Reversing a decision adds a new entry that supersedes the old one,
  whose Status line is the only thing that changes. It's recorded only if the user
  made the reversal.
- **Honest authorship.** "Decided by" says whether it was the user, the model with the
  user's approval, or the model alone.
- **Seen at every start.** A new session, and a session right after a compact, are told
  "N settled decisions for this project: <path>". `/summary` lists them, and
  `/checkpoint` adds its own "Decisions made" items to the log.

### `/brief`: agree on the task before the work

Most wasted work starts as a misread request, or a right request with the wrong
priorities. `/brief` reads just enough of the code to name real files and checks, then
writes the task back as a brief for you to confirm or correct before anything is built:

```
/brief                                  brief the request you just made
/brief UI is the most important part    the same, with your focus
/brief add CSV export; speed over polish  task and focus in one line
```

- **Your words, quoted.** The task and the focus are kept verbatim, and the brief never
  turns the model's preference into your requirement.
- **A focus changes priority, not scope.** It says where effort goes first and what is
  checked hardest. The rest is still done to the normal standard.
- **"Done means" is checkable:** a command, a URL, a test, a screenshot. It's what the
  task is checked against before it's called done. **Enforced:** when a turn that changed
  code calls the task done, the evidence gate checks that every command written in backticks
  under "Done means" ran after the last edit.
- **Out of scope, don't touch, assumptions** are written down, so nothing is silently
  added and every guess is yours to veto. **Don't touch is enforced:** the brief guard (a
  `PreToolUse` hook) refuses edits to any path or glob written in backticks there, such as
  `data/*.generated.js` or `config/`. Prose items stay advisory. Both checks bind only a
  session that has seen the brief, so an old one never blocks unrelated work.
- **It waits for "Go".** Running `/brief <focus>` again updates the current brief.
- **It survives compaction.** It's saved as `~/.claude/checkpoints/<project>/BRIEF.md`
  (earlier ones are archived). A compacted session is pointed back at it, and
  `/checkpoint` takes its Goal from it.

### The evidence gate: claims need a check from this turn

A rule in `CLAUDE.md` that says "verify before you claim" is only a request. This
`Stop` hook enforces it. When the model is about to end its turn, the hook reads the
final reply and the turn's tool calls from the transcript:

| The reply claims | It counts as evidence when this turn ran |
|---|---|
| tests pass, CI is green, `N passed` | a test command, `gh pr checks` or `gh run` |
| deployed, is live, in production | `curl`/`wget`/`ssh`/a deploy or health check, or a browser look. When the reply is about installing a local tool, an install script or a `cmp`/`diff` against the installed copy also counts |
| pushed, merged (next to a PR, branch or `#123`) | `git push`/`git log`/`git merge`, or `gh pr`/`gh api` |
| fixed, works now, verified | any command or browser check |
| builds, compiles | a build, compile or syntax-check command |

- **After the last code edit.** A check that ran before the code changed proved the
  old code. Writing notes, docs or memory (`*.md`, `*.txt`, `~/.claude/`) afterwards
  doesn't count as a change.
- **Claims, not mentions.** Code, quoted words, and sentences that negate or hedge
  ("not deployed", "UNVERIFIED", "once CI is green", "Nothing is merged") claim
  nothing.
- **Relays are left alone.** A turn that delegated to subagents, or one opened by an
  agent's report, passes on checks that ran in another transcript. Reviewing agents is
  a separate step.
- **One nudge, never a loop.** When a claim lacks evidence, the model is sent back once
  with the claim and what would prove it. It can run the check, mark the claim
  UNVERIFIED, or say which earlier turn proved it. The second stop always goes through
  (`stop_hook_active`). A turn that answers the gate's own feedback is never nudged
  again.
- **Calibrated on real sessions.** Replayed over 408 real turns, it blocks 4. All four
  are claims made from memory or from docs. Each false alarm found along the way,
  including the first one it raised in a live session ("now live" for skills that had
  just been installed), is now a regression test.

Turn it off for one session with `HO_EVIDENCE_GATE=off`.

### What a checkpoint looks like

```markdown
# Checkpoint — api — 2026-03-02 18:40

## Goal
"Add rate limiting to the public API", plus a later ask: per-key limits.

## Done (verified)
1. Token-bucket middleware — src/http/ratelimit.ts, branch feat/ratelimit @ 3f2c9e1,
   pushed. Verified: npm test, 41/41 passing.

## In progress
1. Per-key limits — the schema migration is written but not applied.
   Next: `npm run migrate`. Blocker: none.

## Not started
1. Dashboard for rate-limit hits.

## Decisions made
- In-process bucket instead of Redis, for now (user): a single instance until Q3.

## Gotchas found
- `npm test -- --watch` hangs in CI. Never use it in scripts.

## State of the world
- api: feat/ratelimit, clean, pushed; PR #212 open, CI green.

## Resume here
1. `npm run migrate` 2. `npm test` 3. Wire per-key limits into src/http/ratelimit.ts:48

## History
- 2026-03-02 18:40 — middleware done, per-key limits in progress.
```

---

## How it works

```
~/.claude/checkpoints/<project-slug>/
├── CHECKPOINT.md                     ← /checkpoint (structured, verified)
├── CHECKPOINT-2026-03-01_120000.md   ← each earlier /checkpoint, archived on rewrite
├── DECISIONS.md                      ← /decision log, append-only (never pruned)
├── BRIEF.md                          ← /brief (the task as confirmed; earlier ones BRIEF-<date>.md)
├── latest.md                         ← last compact summary, scratchpad removed
├── 2026-03-02_184012_<session>.md    ← every compact summary, full (last 10 kept)
└── <session>.transcript.jsonl        ← full pre-compact transcript (hardlink)
```

- **One folder per project.** The slug is the repo root, found with
  `git rev-parse --show-toplevel`, or the working directory outside a repo, with every
  non-alphanumeric character replaced by `-`. Sessions started in `repo/` and in
  `repo/src/` share a folder.
- **Umbrella folders split by project.** A session started in a non-repo folder that
  holds many projects (`~/code` with `api/`, `web/`, …) is filed under the project it
  touched most, judged from the transcript's file paths and working directories. A new
  session there is pointed at the three newest project checkpoints below it.
- **Project picking at session start.** When the folder holds two or more git repos,
  a new session is told it is a workspace, not a project. Before its first edit or
  command, it settles which project the task is in: from your message if it names one
  or its files, otherwise by asking you in one line, with the five most recently active
  repos offered. Then it works from inside that project, so the project's `CLAUDE.md`
  applies and its checkpoints land in its own folder.
- **Never inside your repo,** so checkpoints never dirty a working tree or get
  committed by accident.
- **PreCompact** hardlinks the live transcript: it uses no extra disk while the
  original exists, and survives Claude Code's own transcript cleanup. It falls back to
  a copy across filesystems.
- **PostCompact** saves the summary Claude Code passes to the hook
  (`compact_summary`). It checks the summary for the four required sections and writes
  `latest.md` without the model's `<analysis>` scratchpad. Then it prunes old files.
- **SessionStart** (`compact`) points the fresh context at *its own* session's
  checkpoint, not whichever session compacted last. **SessionStart** (`startup`) adds
  a one-line pointer and nothing else.
- **Compact instructions** in `CLAUDE.md` shape the summary itself, so it includes
  *In progress*, *Not started*, *State of the world* and *Resume here*.
- The hook **always exits 0**. A failure inside it can never block a compaction.

## Configuration

Set these in the `env` block of `~/.claude/settings.json`:

| Variable | Default | Meaning |
|---|---|---|
| `HO_CHECKPOINT_KEEP` | `10` | Dated compact summaries kept per project |
| `HO_CHECKPOINT_DAYS` | `60` | Saved transcripts older than this many days are deleted |
| `HO_CONTEXT_WINDOW` | detected, else `200000` | Context window in tokens that `/compact-check` measures against |
| `HO_EVIDENCE_GATE` | `on` | `off` disables the evidence gate |
| `HO_BRIEF_GUARD` | `on` | `off` lets edits through to the brief's "Don't touch" paths |

```json
{ "env": { "HO_CHECKPOINT_KEEP": "20", "HO_CHECKPOINT_DAYS": "30" } }
```

`CHECKPOINT.md`, its archived `CHECKPOINT-<date>.md` copies and `latest.md` are never pruned.

## Safety and privacy

- **Local only.** No network calls and no telemetry. The hook uses only `jq`, `git`
  and core shell tools.
- **Owner-only files.** Checkpoints and transcripts can quote anything from your
  session, secrets included, so the hook creates them with `umask 077` (folders
  `700`, files `600`).
- **Outside your repos,** in `~/.claude/checkpoints/`, so they can't be committed.
- **Bounded disk use,** through the retention limits above.
- **A safe installer:** it refuses to touch an invalid `settings.json`, backs up
  before every edit, never removes other tools' hooks, and leaves hand-written
  compact instructions alone.
- **Hardened input handling:** the session ID is reduced to `[A-Za-z0-9_-]` before
  it becomes part of a filename, so it can't escape the checkpoint folder.

Review [`hooks/checkpoint.sh`](hooks/checkpoint.sh) before installing. It's about 100
lines and it runs on every compaction. See [SECURITY.md](SECURITY.md) to report a
problem.

## Uninstall

```bash
./uninstall.sh
```

This removes the hook entries (other hooks are kept), the hook script, the compact
instructions block, and the two commands, as long as you haven't edited them. Your
checkpoints stay in `~/.claude/checkpoints/`; delete that folder to remove them too.

## Troubleshooting

| Symptom | Check |
|---|---|
| Anything seems off, or nothing happens | Run `/doctor`. It checks the install, wiring and settings, and `/cure` fixes what it finds. |
| Nothing appears in `~/.claude/checkpoints/` after a compact | Hooks load at session start, so start a new session after installing. Confirm the entries with `jq .hooks ~/.claude/settings.json`. |
| `latest.md` says `EMPTY SUMMARY` | Your Claude Code version passes no summary to `PostCompact`. The file lists the keys it did receive. Please open an issue with them. |
| `latest.md` says `INCOMPLETE` | The model skipped a required section. The full transcript is beside it, so grep there for the missing details. |
| `/summary` reports drift | The checkpoint is older than the code. Run `/checkpoint`. |
| Two different folders map to one slug | Paths that differ only in punctuation (`a.b`, `a-b`) share a slug. This is a known limitation. |

## Development

```bash
bash tests/test-checkpoint.sh
```

219 black-box tests run the real hook, helper scripts, installer and uninstaller against a temporary
`HOME`, so your own `~/.claude` is never touched. They cover hardlinks, retention,
session-aware pointers, path handling, permissions, installer idempotency and
uninstall. CI runs them on Ubuntu and macOS, and runs ShellCheck. See
[CONTRIBUTING.md](CONTRIBUTING.md) to add a skill.

## Roadmap

More skills for harness operators are coming. Ideas and pull requests are welcome:
open an issue describing the problem you keep solving by hand.

## License

[MIT](LICENSE)
