# Safety Model

Voltune is designed around **Safe by default. Reversible by design.**

## Safe Mode and Dry Run

Safe Mode is enabled by default. It keeps experimental and higher-impact operations out of the normal path. Dry Run simulates supported mutations. CLI developer cleanup is also dry-run unless `--apply` is explicitly supplied.

## Filesystem safety engine

All vNext filesystem deletion features use `FilesystemSafety` before mutation. The policy:

- rejects empty paths and filesystem roots;
- protects Windows/system roots and prevents deleting a parent that contains them;
- blocks symlinks, junctions and other reparse points by default;
- honors persistent user-protected paths even when a cleanup category is selected;
- allows narrowly scoped exceptions for known cleanup roots such as a temp directory without authorizing the surrounding Windows tree;
- estimates the candidate size before deletion and verifies whether deletion completed;
- never follows symlinks during disk/developer scanning.

Configured protected paths include common local AI/developer data such as `.ollama`, `.claude`, `.cursor`, `.vscode`, and Docker data. Users can manage the list from **Protected Paths** or `config.json`.

## Developer cleanup guardrail

Developer artifacts such as `node_modules`, virtualenvs, `.next`, `target`, and build directories are candidates only. Projects active within `storage.recent_project_days` are marked recent and excluded from the default selection. Safe Mode refuses manual selection of recent artifacts.

## Installer cleanup guardrail

Executable installer formats are age/size filtered. Generic `.zip` and `.7z` files are not considered installers unless the filename contains installer-like tokens such as `setup`, `installer`, `driver`, or `update`.

## Smart uninstaller guardrail

Voltune reads standard Windows uninstall registry entries and launches the registered uninstaller without a command shell. MSI install actions are normalized to uninstall actions where possible. Leftover detection exposes only HIGH/MEDIUM candidates and never automatically deletes them.

## Existing mutation lifecycle

Where practical, established Windows changes use:

`DETECT -> SNAPSHOT -> APPLY -> VERIFY -> RESTORE`

Examples include Gaming Session state, DNS settings, privacy policies, power plans and supported registry changes.

## Limitations

No local utility can guarantee recovery from every Windows failure, power loss, third-party driver issue or external policy change. A restore history is not a substitute for normal backups. Destructive network reset and experimental BCD/network controls remain separated from routine maintenance.
