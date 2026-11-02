# Build and Release

Voltune can be used in two ways: run directly from Python source, or build a standalone Windows executable. For normal end users, the GitHub Release `.exe` is the intended path. For development, run from source.

## 1. Run from source

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python .\voltune.py
```

Voltune requests Administrator privileges when a privileged operation needs them.

## 2. Editable install for development

```powershell
python -m pip install -e .
voltune
```

## 3. Build a standalone EXE

Install build dependencies first:

```powershell
python -m pip install -r requirements-dev.txt
```

Recommended build command:

```powershell
python -m PyInstaller --noconfirm --clean --onefile --uac-admin --name "Voltune" --paths src voltune.py
```

Output:

```text
dist\Voltune.exe
```

### Short alternative command

If the build environment is already clean and dependencies are installed, this shorter command is also valid:

```powershell
python -m PyInstaller voltune.py --onefile --uac-admin --name "Voltune" --paths src
```

This is the Voltune equivalent of the older single-file command:

```powershell
python -m PyInstaller voltune.py --onefile --uac-admin --name "Voltune" --paths src
```

The important Voltune-specific addition is `--paths src`, because the installable package lives under `src/voltune`.

## 4. Test the built EXE locally

Before publishing a release, test the actual executable rather than assuming a successful build means a working application.

```powershell
.\dist\Voltune.exe
```

At minimum, complete `docs/WINDOWS_TEST_CHECKLIST.md` on a Windows 11 machine and verify:

- UAC elevation works.
- Main menu renders correctly.
- Safe Mode is enabled by default.
- Back/cancel/end-session returns to a freshly cleared main menu.
- Power Plans can be detected without creating duplicate Ultimate Performance plans.
- DNS benchmark, switch, verification, and restore work on the active adapter.
- Gaming Session can restore the original service and power-plan state.
- A forced close during Gaming Session is recovered on the next launch.
- System Dashboard works without WMIC.
- `config.json`, `state.json`, and `logs/` are created beside the executable as intended.

## 5. Create a checksum locally

```powershell
$hash = (Get-FileHash .\dist\Voltune.exe -Algorithm SHA256).Hash.ToLower()
"$hash  Voltune.exe" | Set-Content -Encoding ascii .\dist\SHA256SUMS.txt
```

Users can verify it with:

```powershell
Get-FileHash .\Voltune.exe -Algorithm SHA256
```

## 6. Tagged GitHub releases

The release workflow runs automatically for tags matching `v*`.

```powershell
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions will:

1. install dependencies;
2. run the test suite;
3. build the Windows executable;
4. calculate SHA-256;
5. upload build artifacts;
6. create/update the GitHub Release with generated release notes;
7. attach `Voltune.exe` and `SHA256SUMS.txt`.

Do not tag a release until the Windows integration checklist passes.

## 7. Unsigned EXE / SmartScreen note

Voltune is not code-signed by default. Windows SmartScreen or antivirus products may warn about newly built PyInstaller executables, especially when a release has little reputation. Do not instruct users to disable Defender or SmartScreen. Document the unsigned status, publish the SHA-256 checksum, and keep release artifacts built by GitHub Actions for reproducibility.

Code signing can be added later if a trusted signing certificate is available.
