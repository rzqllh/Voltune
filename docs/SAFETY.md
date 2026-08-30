# Safety Model

Voltune is designed around **Safe by default. Reversible by design.**

## Safe Mode
Safe Mode is enabled by default. It keeps experimental and higher-impact operations out of the normal path.

## Dry Run
Dry Run allows state-changing command flows to be inspected without executing the mutation.

## Mutation lifecycle
Where practical, Voltune uses:

`DETECT -> SNAPSHOT -> APPLY -> VERIFY -> RESTORE`

Examples include Gaming Session state, DNS settings, privacy policies, and supported registry changes.

## Important limitations
- A restore path cannot guarantee recovery from every Windows failure, power loss, third-party driver issue, or external configuration change.
- App removal can require Microsoft Store/WinGet or Windows servicing to reinstall packages.
- Network reset and firewall reset are intentionally separated from routine repair because they can remove custom configuration.
- Experimental BCD/network tweaks are not part of the recommended performance path.
- Memory trimming can increase later page faults. It is a troubleshooting tool, not a generic speed boost.

## Before large changes
Create a normal backup and, where supported, a Windows restore point. Do not use an optimizer as a substitute for backups.
