# Architecture

Voltune 0.1 uses a deliberately simple CLI architecture while its system behavior stabilizes.

```text
voltune.py                 thin source-checkout launcher
src/voltune/app.py         CLI, state model, Windows integrations, feature orchestration
src/voltune/__main__.py    python -m voltune entry point
config.example.json        documented default configuration
state.json                 local runtime restore/history state (gitignored)
logs/                      local session audit logs (gitignored)
```

## Runtime principles
1. The main menu owns screen clearing. A feature returns, then the next menu render starts from a clean CLI.
2. System-changing commands flow through shared command helpers so return codes and logs are consistent.
3. Persistent state is written atomically. Corrupt state/config is preserved with a timestamp before defaults are recreated.
4. Safe Mode keeps experimental actions out of the default workflow.
5. Runtime configuration and machine state are never committed to source control.

## Planned module split
After the feature contracts stabilize, `app.py` can be separated by domain without changing the CLI contract:

```text
src/voltune/
  core/        config, state, command execution, Windows abstractions
  features/    gaming, power, cleanup, network, dns, startup, apps, privacy, system
  ui/          menu and Rich rendering
```

Keeping this roadmap explicit is intentional: premature module slicing would make a young Windows utility look architecturally busy without making the behavior safer.
