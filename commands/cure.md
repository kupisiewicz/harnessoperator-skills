---
description: Fix the problems /doctor finds, using its own tested fixes; asks before any fix marked "ask", then re-checks and shows before and after
argument-hint: "[all | a finding id, e.g. wiring:Stop]"
---

Fix what `/doctor` finds. Every fix goes through `cure.sh`, never through a hand edit of `settings.json` or the hooks. Each fix there is one known operation that backs up what it changes. Arguments: $ARGUMENTS

## 1. Diagnose fresh

`bash ~/.claude/hooks/harnessoperator/doctor.sh`

Run it now, even if `/doctor` ran earlier in the session: the earlier report may be stale. Collect every `WARN` and `FAIL` with its `fix (...)` line. If the arguments name a finding id (such as `wiring:Stop`), keep only that one. If nothing is wrong, say "Healthy, nothing to cure." and stop.

## 2. Plan

Fixes that are the same command count once. `reinstall` alone usually cures every missing, outdated or unwired file, so it runs first. Group the fixes:
- **safe:** apply them without asking.
- **ask:** list them, numbered, each with what it changes ("removes `HO_EVIDENCE_GATE=off` from settings.json, so the gate is on in every session"). Ask once, in one line, which to apply. If the arguments are `all`, the user has already said yes to all of them, so don't ask.
- **manual:** don't run these. Say exactly what the user needs to do. If one is a step you can take yourself in this session, such as `/checkpoint`, offer it.

## 3. Apply

Run each chosen fix exactly as doctor printed it (`bash ~/.claude/hooks/harnessoperator/cure.sh <fix> [arg]`), one at a time, in plan order. Quote each one's result line. If a fix exits non-zero, stop there: report its error and what is still unfixed. Don't try something else in its place.

## 4. Re-check

Run `doctor.sh` again, then report in a few lines:
- what was fixed, as before → after: `FAIL wiring:Stop → OK`;
- what is still open, and why: declined, manual, or the fix failed;
- "Start a new session so the fixed hooks load", if a fix touched hooks, wiring or settings.

Never claim a problem is fixed unless the second doctor run shows it as OK.
