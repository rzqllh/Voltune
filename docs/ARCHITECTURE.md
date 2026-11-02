# Architecture

Voltune 0.2.1 continues the planned modular split without rewriting stable Windows integrations all at once.

```text
run_voltune.py                     source/build launcher -> voltune.cli
src/voltune/cli.py                 argparse subcommands + JSON/NDJSON surfaces
src/voltune/app.py                 interactive compatibility shell + established Windows integrations
src/voltune/core/config.py         storage-intelligence defaults/path expansion
src/voltune/core/safety.py         centralized filesystem deletion policy
src/voltune/features/
  storage_intelligence.py          disk, large-file, dev-artifact, installer scanning
  system_monitor.py                reusable system snapshots
  uninstaller.py                   desktop-app inventory + conservative leftovers
config.example.json                documented runtime configuration
state.json / logs/                 local runtime state (gitignored)
```

## Runtime principles

1. The interactive main menu owns screen clearing.
2. Existing registry/service/power/network mutations still use the established shared command helpers and state/history model.
3. New destructive filesystem operations must pass `FilesystemSafety`; feature code does not get a private bypass because that is how cleaners eventually eat somebody's project folder.
4. Safe Mode keeps experimental actions out of the default workflow. Disk Analyzer deletion also requires Advanced Mode.
5. Developer cleanup treats projects active within the configured recent window as protected from default selection.
6. CLI cleanup is dry-run by default; mutation requires `--apply`.
7. JSON and NDJSON output are stable machine-readable surfaces and must not contain Rich decoration.
8. Runtime configuration, machine state and logs remain outside source control.

## Incremental extraction strategy

`app.py` remains large because its Windows integrations are already regression-tested. New domains are extracted first. Older domains should move into `core/`, `features/`, and `ui/` only when their behavior can be preserved behind tests. This avoids a cosmetic big-bang refactor that changes hundreds of lines while improving exactly nothing for the user.
