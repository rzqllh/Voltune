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

The important Voltune-specific addition is `--paths src`, because the installable package lives under `src/voltune`.

## 4. Test the built EXE locally

Before publishing a release, test the actual executable rather than assuming a successful build means a working application.

```powershell
.\dist\Voltune.exe
```

At minimum, complete `docs/WINDOWS_TEST_CHECKLIST.md` on a Windows 11 machine and verify UAC elevation, menu rendering, Safe Mode, power plans, DNS switching/restoration, Gaming Session restoration/crash recovery, CIM dashboard behavior, and runtime file locations.

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

GitHub Actions will install dependencies, run tests, build the Windows executable, calculate SHA-256, upload artifacts, create/update the GitHub Release, and attach `Voltune.exe` plus `SHA256SUMS.txt`.

Do not tag a release until the Windows integration checklist passes.

## 7. Unsigned EXE / SmartScreen note

Voltune is not code-signed by default. Windows SmartScreen or antivirus products may warn about newly built PyInstaller executables. Do not instruct users to disable Defender or SmartScreen. Document the unsigned status, publish the SHA-256 checksum, and keep release artifacts built by GitHub Actions for reproducibility.
