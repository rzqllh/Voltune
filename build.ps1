$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

if (Test-Path ".\voltune.py") {
    throw "Legacy voltune.py found in repo root. Delete it before building; it shadows the src\voltune package in PyInstaller."
}

Write-Host "[Voltune] Installing build dependencies..."
python -m pip install -r requirements-dev.txt

Write-Host "[Voltune] Removing stale build output..."
Remove-Item -Recurse -Force build, dist -ErrorAction SilentlyContinue

Write-Host "[Voltune] Running regression tests against this checkout..."
$env:PYTHONPATH = Join-Path $PSScriptRoot "src"
python -c "import pathlib, voltune; p=pathlib.Path(voltune.__file__).resolve(); expected=(pathlib.Path(r'$PSScriptRoot')/'src'/'voltune').resolve(); print(f'[Voltune] Import source: {p}'); assert expected in p.parents or p == expected/'__init__.py', f'Wrong Voltune import source: {p}'"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python -m pytest
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[Voltune] Compiling Python sources..."
python -m compileall src run_voltune.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[Voltune] Building Voltune.exe..."
python -m PyInstaller --noconfirm --clean Voltune.spec
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not (Test-Path ".\dist\Voltune.exe")) {
    throw "Build finished without dist\Voltune.exe"
}

Write-Host ""
Write-Host "Build complete: dist\Voltune.exe"
Write-Host "Run smoke tests:"
Write-Host "  .\dist\Voltune.exe status --json"
Write-Host "  .\dist\Voltune.exe dev-clean --json"
Write-Host "  .\dist\Voltune.exe"
