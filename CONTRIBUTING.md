# Contributing

Thanks for improving Voltune. Changes should preserve three rules: safe defaults, verified mutations, and a restore path where practical.

## Local setup

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
python -m pytest
python .\voltune.py
```

## Pull requests
- Keep system-changing commands explicit and auditable.
- Never print success unless the operation is verified or the command returned success with a documented limitation.
- New destructive actions must require confirmation and belong in Advanced Mode when appropriate.
- Avoid undocumented registry folklore or performance claims without evidence.
- Add or update tests for pure logic and regression-sensitive command construction.
