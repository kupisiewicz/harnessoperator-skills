# harnessoperator-skills

**Skills, hooks and instructions for AI coding harness operators. Starts with resumable checkpoints for Claude Code compaction: compact, /checkpoint, /summary.**

Make each one a single command.</strong></p> Skills, hooks and instructions for people who run AI coding harnesses all day, or build their own. Part of the **Harness Operator** project. It targets [Claude Code](https://docs.claude.com/en/docs/claude-code) and solves two problems:

Read [README.md](README.md) first; this file is the orientation and the rules.

## Part of the castomo estate

Before building anything here that sounds generic (auth, storage, email/SMS/push, payments,
files, chat, scraping, PDF, reference data, dashboards UI), check the estate catalog — it
almost certainly exists already: `kupisiewicz/castomapi-box/ECOSYSTEM.md`

```bash
gh api repos/kupisiewicz/castomapi-box/contents/ECOSYSTEM.md --jq .content | base64 -d
```

## Commands

```bash
./install.sh
./uninstall.sh
bash tests/test-checkpoint.sh
```

## Layout

`commands/` (7 files) · `compact/` (1 file) · `hooks/` (2 files) · `scripts/` (4 files) · `tests/` (1 file)

## Where the detail is

README.md covers: Why · Quick start · How to use them · How it works · Configuration · Safety and privacy · Uninstall · Troubleshooting · Development · Roadmap · License.
Other docs: `CONTRIBUTING.md`, `SECURITY.md`.

## Rules

1. No secret, key or token is ever committed to this repository.
2. Code comments explain *why* and what is going on, in full sentences, so a human or an agent can pick the code up cold. English only.
3. If this repo changes what it can do, update `ECOSYSTEM.md` in castomapi-box in the same piece of work.
