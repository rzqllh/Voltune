# Troubleshooting

## Administrator prompt loops
Run from Windows Terminal or PowerShell and ensure Python is installed for the same user context. If using the release executable, launch the downloaded `voltune.exe` directly.

## Ultimate Performance is unavailable
Some devices or Windows power models do not expose every legacy power scheme. Voltune first checks existing schemes, then duplicates the official Ultimate Performance template and verifies the returned GUID. If Windows rejects the scheme, Voltune reports failure instead of claiming activation.

## DNS benchmark shows timeouts
A network, VPN, firewall, captive portal, or resolver policy may block direct queries to public DNS services. Restore Automatic/DHCP DNS and test the active adapter first.

## WinGet is missing
Install/update App Installer from Microsoft Store. Voltune does not bundle WinGet.

## Defender controls are unavailable
Third-party antivirus, organizational policy, or Windows edition/configuration can disable or restrict Microsoft Defender cmdlets.

## A previous Gaming Session was not restored
On the next launch Voltune detects the saved active session and offers recovery before drawing the main menu.
