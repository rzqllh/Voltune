# Windows Integration Test Checklist

Use this checklist on a disposable or non-critical Windows 11 machine before publishing a tagged release.

## Baseline
- [ ] Launch from `python .\voltune.py` as a normal user and confirm UAC elevation succeeds.
- [ ] Main menu redraws on a clean screen after Success, Cancel, Back, and recoverable errors.
- [ ] `H` opens plain-language Help and returns to a clean main menu.
- [ ] Safe Mode is enabled by default.
- [ ] Dry Run visibly skips supported mutations and does not change Windows state.
- [ ] `config.json`, `state.json`, and session logs are created locally and remain gitignored.

## Gaming Session
- [ ] Preflight changes nothing.
- [ ] Starting a session records the original power plan and service states.
- [ ] Ending the session restores the exact original power plan.
- [ ] Services that were already stopped remain stopped after restore.
- [ ] Force-close Voltune during a Gaming Session, relaunch it, and verify recovery is offered.

## Power Plans
- [ ] Balanced can be selected and verified.
- [ ] High Performance gracefully reports unavailable plans where applicable.
- [ ] Power Saver gracefully reports unavailable plans where applicable.
- [ ] Ultimate Performance detects an existing scheme without creating a duplicate.
- [ ] When absent, Ultimate Performance captures the GUID returned by `/duplicatescheme` and verifies it in `/list`.
- [ ] Repeating Add Ultimate does not create duplicate schemes.

## Performance Settings
- [ ] Apply Recommended runs both visual and Game DVR operations.
- [ ] Restore & History can restore the captured supported registry values.
- [ ] Experimental timer/Nagle controls are unavailable in Safe Mode.

## Storage Cleanup
- [ ] Preview completes without deleting anything.
- [ ] Firefox cache discovery uses Local AppData profiles.
- [ ] Chromium profile caches beyond `Default` are detected where present.
- [ ] Prefetch is not included in normal cleanup.
- [ ] Reclaimed byte count is plausible after cleanup.
- [ ] DISM component cleanup remains separate from ordinary cache cleanup.

## DNS and networking
- [ ] Active adapter matches the interface carrying the default IPv4 route.
- [ ] VPN/virtual adapters do not accidentally become the default target when they are not carrying the route.
- [ ] DNS benchmark performs real resolver queries and reports median/P95/success rate.
- [ ] Apply DNS changes only the selected active adapter.
- [ ] DNS apply is verified after `Set-DnsClientServerAddress`.
- [ ] Restore Previous restores the exact prior DNS server list.
- [ ] Restore Automatic resets the adapter to DHCP-provided DNS.
- [ ] Gateway diagnostics, internet diagnostics, jitter, loss, and traceroute behave sensibly.
- [ ] Safe Network Repair does not reset firewall rules.
- [ ] Destructive reset displays a strong confirmation warning.
- [ ] Static-IP adapters are not blindly subjected to DHCP release/renew.

## Startup / apps / updates
- [ ] Startup registry entry disable stores the original value and type.
- [ ] Restore recreates the exact startup value.
- [ ] Scheduled startup task view works on Windows PowerShell 5.1.
- [ ] App Manager verifies package removal instead of assuming success.
- [ ] WinGet missing state is reported clearly.
- [ ] App Updates previews changes before install.

## System / Defender
- [ ] System Dashboard works on a machine without `wmic.exe`.
- [ ] CIM OS/CPU/GPU/baseboard/BIOS reads return sensible values.
- [ ] Physical disk data degrades gracefully if `Get-PhysicalDisk` is unavailable.
- [ ] TPM and Secure Boot checks degrade gracefully on unsupported hardware.
- [ ] Defender panel behaves correctly with Microsoft Defender active.
- [ ] Defender panel degrades gracefully with third-party antivirus or managed policy.

## Recovery / Advanced
- [ ] History survives application restart.
- [ ] Atomic state writes do not leave a half-written live `state.json` during normal operation.
- [ ] Corrupt a copy of `state.json`; verify Voltune preserves it as a timestamped corrupt file and recovers defaults.
- [ ] Process termination remains locked in Safe Mode.
- [ ] Advanced Mode clearly identifies experimental operations.

## Release executable
- [ ] Build `voltune.exe` with the documented PyInstaller command.
- [ ] Launch the EXE on a clean Windows account without a Python installation.
- [ ] UAC elevation works from the EXE.
- [ ] Runtime config/state/log paths are next to the EXE as documented.
- [ ] SHA-256 checksum matches the release asset.
