---
description: Split a task across N subagents with a fixed model mix — Sonnet for lighter work, Opus for heavier work, Fable to review everyone's output
argument-hint: "<N> [task], e.g. '10' or '6 audit the billing module'"
---

Run this as a swarm: $ARGUMENTS

The first word is **N**, the total number of subagents. The rest is the task. If there is no task text, use the current task in this conversation. No N → ask once. N ≤ 0 or not a number → say so and stop.

## 1. Compute the mix

```
reviewers = 0 if N < 7 else ceil(N / 10)   # model: "fable"
workers   = N - reviewers
sonnet    = round(workers * 2 / 3)          # model: "sonnet"
opus      = workers - sonnet                # model: "opus"
```

Use this table, don't recompute:

| N | Sonnet | Opus | Fable |
|---|---|---|---|
| 1 | 1 | 0 | 0 |
| 2 | 1 | 1 | 0 |
| 3 | 2 | 1 | 0 |
| 4 | 3 | 1 | 0 |
| 5 | 3 | 2 | 0 |
| 6 | 4 | 2 | 0 |
| 7 | 4 | 2 | 1 |
| 8 | 5 | 2 | 1 |
| 9 | 5 | 3 | 1 |
| 10 | 6 | 3 | 1 |
| 11 | 6 | 3 | 2 |
| 12 | 7 | 3 | 2 |
| 15 | 9 | 4 | 2 |
| 20 | 12 | 6 | 2 |

Before launching, state the mix in one line, e.g. `swarm 10: 6 sonnet · 3 opus · 1 fable`.

## 2. Split the work

- Break the task into exactly `sonnet + opus` independent pieces. Pieces that would edit the same files must not run in parallel. Merge them into one piece, or give each agent `isolation: "worktree"`.
- **Opus** gets the heavier pieces: design decisions, tricky logic, security, money, cross-file refactors, root-cause debugging.
- **Sonnet** gets the lighter ones: reads and sweeps, mechanical edits, tests, docs, fixtures, checks.
- If the task has fewer real pieces than workers, don't invent busywork. Say how many you actually use, and why.

## 3. Launch

- Launch all workers in **one message** (parallel Agent calls), each with `model` set explicitly. Never use `subagent_type: "fork"`: forks ignore `model`.
- Make each brief self-contained: the goal, the exact files or area, what's already ruled out, what "done" looks like, and "report: what you changed (paths), what you verified, what you did not".
- Wait for the completion notifications. Never predict results.

## 4. Review (only when Fable count > 0)

Launch the Fable reviewer(s) (`model: "fable"`) only after **all** workers report. With 2+ reviewers, split the workers' output between them. Give each reviewer the workers' reports and the changed paths, not your own conclusions. Ask it to check correctness, missed callers and tests, conflicts between agents' changes, and claims not backed by evidence, and to return findings with file:line.

## 5. Finish

Fix confirmed review findings, or delegate the fixes. Then report concisely: what each agent did, what the reviewers found, and what's still unverified.
