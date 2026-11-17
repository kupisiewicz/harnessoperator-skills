# Contributing

Thanks for helping harness operators work faster. Issues, ideas and pull requests
are all welcome.

## Ground rules

- **Zero dependencies beyond `bash`, `jq` and `git`.** No build step, no package
  manager. A skill should install by copying files.
- **Portable shell.** It must run on macOS (BSD tools, bash 3.2) and Linux (GNU
  tools). For example, `stat` needs both forms, as `mtime()` in
  `hooks/checkpoint.sh` shows.
- **Hooks never block the harness.** A hook must exit 0 whatever goes wrong.
- **Nothing personal.** No home-directory paths, usernames, hostnames, keys or real
  transcripts in code, tests, docs or examples. Use `$HOME`, `~`, and made-up example
  projects.
- **Comments explain why,** not what.

## Repository layout

```
commands/   slash commands (Markdown prompts) -> ~/.claude/commands/
hooks/      hook scripts                      -> ~/.claude/hooks/harnessoperator/
compact/    CLAUDE.md blocks                  -> ~/.claude/CLAUDE.md (between markers)
tests/      black-box tests, run against a temporary HOME
install.sh / uninstall.sh
```

## Adding a skill

1. Add `commands/<name>.md`, with a `description` and an `argument-hint` in the front
   matter. `install.sh` picks up every file in `commands/` on its own.
2. If it needs a hook, add the script to `hooks/` and wire it in the `jq` block of
   `install.sh`. Use the same pattern: drop our old entry, then add it again, so
   re-installing never duplicates anything.
3. Add tests to `tests/`. They must use a temporary `HOME`, never the real one.
4. Document it in `README.md`: what it does, when to use it, and how.
5. Add a line to `CHANGELOG.md`.

## Before you open a pull request

```bash
bash tests/test-checkpoint.sh                                       # every test passes
shellcheck -S warning hooks/*.sh install.sh uninstall.sh            # if you have it
```

CI runs both on Ubuntu and macOS.
