# harnessoperator-skills

<p><strong>Your agent forgets when it compacts.<br>
These skills make it remember.</strong></p>

Skills, hooks and instructions for people who run AI coding harnesses all day, or
build their own. Part of the **Harness Operator** project. This first release targets
[Claude Code](https://docs.claude.com/en/docs/claude-code) and solves one problem
well: **long sessions lose track of their work.**

| Skill | What it does | How it runs |
|---|---|---|
| **compact** | Turns every compaction into a resumable checkpoint, saves it to disk, keeps the raw transcript, and warns when the summary skipped something. | Automatic, on every `/compact` and auto-compact |
| **`/checkpoint`** | Writes a verified, structured `CHECKPOINT.md`: done, in progress, not started, decisions, gotchas, and where to resume. | You type it |
| **`/summary`** | Shows what's done, in progress and not started, from the latest checkpoint, checked against live git state. `/summary all` covers every project. | You type it |

---

## Why

When a Claude Code session fills its context, it **compacts**: the conversation is
replaced by a summary the model writes for itself. That summary is a narrative. It
often loses the exact stopping point, the branch that was never pushed, the approach
that already failed. And it lives only in the session that wrote it.

So you end up typing the same thing again and again:

> *"Prepare me a detailed summary of all the work done here, what is in progress and
> what is not started yet."*

These skills make that one word, and they make compaction itself produce something
you can resume from, in this session or in a brand-new one.

## Quick start

```bash
git clone https://github.com/kupisiewicz/harnessoperator-skills.git
cd harnessoperator-skills
./install.sh
```

Then **start a new Claude Code session**, since hooks load at session start.

**Requirements:** `bash`, `jq` (`brew install jq` or `apt install jq`), and a Claude
Code version with `PreCompact`, `PostCompact` and `SessionStart` hooks. `git` is
optional; it is used to find the repo root and to check branch state. macOS and Linux
are supported, and CI runs the test suite on both.

`install.sh` is safe to run again, for example to update after a `git pull`. It
merges into your existing settings instead of replacing them, never duplicates its
own entries, and backs up every file it changes first
(`<file>.bak-harnessoperator-<timestamp>`). Here is exactly what it does:

| Installs | To |
|---|---|
| `commands/checkpoint.md`, `commands/summary.md` | `~/.claude/commands/` |
| `hooks/checkpoint.sh` | `~/.claude/hooks/harnessoperator/checkpoint.sh` |
| Hook entries: `PreCompact`, `PostCompact`, `SessionStart` (matcher `compact\|startup`) | merged into `~/.claude/settings.json` |
| `compact/compact-instructions.md` | appended to `~/.claude/CLAUDE.md` between `harnessoperator` marker comments |

If your `CLAUDE.md` already has a `## Compact instructions` section that you wrote
yourself, the installer leaves it alone and tells you to merge by hand.

---

## How to use them

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
├── latest.md                         ← last compact summary, scratchpad removed
├── 2026-03-02_184012_<session>.md    ← every compact summary, full (last 10 kept)
└── <session>.transcript.jsonl        ← full pre-compact transcript (hardlink)
```

- **One folder per project.** The slug is the repo root, found with
  `git rev-parse --show-toplevel`, or the working directory outside a repo, with every
  non-alphanumeric character replaced by `-`. Sessions started in `repo/` and in
  `repo/src/` share a folder.
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

```json
{ "env": { "HO_CHECKPOINT_KEEP": "20", "HO_CHECKPOINT_DAYS": "30" } }
```

`CHECKPOINT.md` and `latest.md` are never pruned.

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
| Nothing appears in `~/.claude/checkpoints/` after a compact | Hooks load at session start, so start a new session after installing. Confirm the entries with `jq .hooks ~/.claude/settings.json`. |
| `latest.md` says `EMPTY SUMMARY` | Your Claude Code version passes no summary to `PostCompact`. The file lists the keys it did receive. Please open an issue with them. |
| `latest.md` says `INCOMPLETE` | The model skipped a required section. The full transcript is beside it, so grep there for the missing details. |
| `/summary` reports drift | The checkpoint is older than the code. Run `/checkpoint`. |
| Two different folders map to one slug | Paths that differ only in punctuation (`a.b`, `a-b`) share a slug. This is a known limitation. |

## Development

```bash
bash tests/test-checkpoint.sh
```

78 black-box tests run the real hook, installer and uninstaller against a temporary
`HOME`, so your own `~/.claude` is never touched. They cover hardlinks, retention,
session-aware pointers, path handling, permissions, installer idempotency and
uninstall. CI runs them on Ubuntu and macOS, and runs ShellCheck. See
[CONTRIBUTING.md](CONTRIBUTING.md) to add a skill.

## Roadmap

More skills for harness operators are coming. Ideas and pull requests are welcome:
open an issue describing the problem you keep solving by hand.

## License

[MIT](LICENSE)
