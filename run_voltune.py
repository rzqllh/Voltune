#!/usr/bin/env python3
"""Source/build launcher for Voltune.

The launcher intentionally is NOT named ``voltune.py``. A top-level module with
that name shadows the real ``src/voltune`` package during PyInstaller analysis
and in test/import contexts.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from voltune.cli import main

if __name__ == "__main__":
    raise SystemExit(main())
