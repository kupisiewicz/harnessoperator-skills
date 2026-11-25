---
description: Check that harnessoperator-skills is installed and working (hooks, wiring, settings, commands, this project's checkpoint and brief) and list each problem with its fix
argument-hint: ""
---

Find what is broken or degraded in this harness setup, and say how each problem gets fixed. Read-only: change nothing. `/cure` applies the fixes.

## 1. Run the checks

`bash ~/.claude/hooks/harnessoperator/doctor.sh`

Run it from the session's working directory: the last checks look at this project's checkpoint and brief. It prints one line per check (`OK`, `WARN` or `FAIL`). Under each problem it prints its fix, labelled with who may apply it:
- **safe:** `/cure` applies it without asking. These are idempotent and back up what they change.
- **ask:** `/cure` applies it only after the user says yes.
- **manual:** only the user can do it, or it needs a judgement no script makes.

Treat its findings as facts and don't re-check them by hand. If the script is missing, the install itself is broken: say so, and give the fix `cd <checkout> && bash install.sh`.

## 2. Report

Problems only, worst first, one line each in plain words:

`FAIL wiring:Stop: the evidence gate isn't wired, so claims go unchecked → safe`

Say what the problem means for the user (which feature is off, or what goes wrong), not just what the check saw. Leave out the OK lines, and give their count: "13 checks passed."

Then one closing line:
- **Any problems:** "Run `/cure` to fix them: N safe, N need your OK, N manual." Spell out each manual step.
- **None:** "Healthy." Nothing else.
