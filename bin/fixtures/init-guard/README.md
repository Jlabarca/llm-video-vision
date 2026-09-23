# init-guard fixture contract

`bin/init-guard.{ps1,sh}` — PreToolUse(Bash) hook. Blocks `claude /init` in a repo with
an existing `CLAUDE.md` (it would overwrite the curated file). Careless-only gate:
**block-by-default**, no warn ladder. Exit: `0 allow · 2 block`.

Command is read from `GHOSTDEV_INITGUARD_CMD` (testing) or stdin JSON `.tool_input.command`.
Repo root is arg 1 (`.sh`) / `-RepoRoot` (`.ps1`); default = the script's parent's parent.

## Parity matrix (ps1 ≡ sh)

| GHOSTDEV_INITGUARD_CMD | CLAUDE.md in RepoRoot | exit | meaning |
|---|---|---|---|
| `claude /init` | present | **2** | block (the overwrite case) |
| `claude /init --foo` | present | **2** | block (args don't matter) |
| `claude /init` | absent | **0** | allow (nothing to clobber) |
| `grep /init AGENTS.md` | present | **0** | allow (not a `claude /init` invocation) |
| `npm run init` | present | **0** | allow (not claude) |
| _(empty / no command)_ | any | **0** | allow (no-op) |

## Drive it

```sh
# block case
GHOSTDEV_INITGUARD_CMD='claude /init' bash bin/init-guard.sh "$PWD"; echo $?   # -> 2
GHOSTDEV_INITGUARD_CMD='claude /init' pwsh -NoProfile -File bin/init-guard.ps1 -RepoRoot "$PWD"; echo $?  # -> 2
# allow case (no CLAUDE.md): point RepoRoot at a clean tmp dir
GHOSTDEV_INITGUARD_CMD='claude /init' bash bin/init-guard.sh /tmp; echo $?     # -> 0
```
