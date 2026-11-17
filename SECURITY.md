# Security

## What these skills touch

- **They read** the hook payload that Claude Code passes on stdin: the session ID,
  the working directory, the transcript path and the compact summary.
- **They write** only under `~/.claude/checkpoints/` (owner-only, `umask 077`). The
  installer also writes to `~/.claude/commands/`, `~/.claude/hooks/harnessoperator/`,
  `~/.claude/settings.json` and `~/.claude/CLAUDE.md`, and backs each file up first.
- **They make no network calls,** and there is no telemetry.

Checkpoints and saved transcripts can contain anything that appeared in your
sessions, including secrets you pasted or printed. Treat `~/.claude/checkpoints/` like
your shell history: don't sync it to shared storage, and don't attach it to issues.

## Reporting a vulnerability

Please **don't open a public issue** for a security problem. Use GitHub's
**Report a vulnerability** button on the repository's *Security* tab, which opens a
private advisory. Include the steps to reproduce and the version or commit.

You'll get an answer within a few days. Fixes are released as soon as they are ready
and credited in the changelog, unless you'd rather not be named.
