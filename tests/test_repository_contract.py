from __future__ import annotations

import ast
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "src" / "voltune" / "app.py"


def source() -> str:
    return APP.read_text(encoding="utf-8")


def test_source_compiles():
    ast.parse(source())


def test_config_example_is_valid_json():
    data = json.loads((ROOT / "config.example.json").read_text(encoding="utf-8"))
    assert data["schema_version"] == 2
    assert len(data["dns_providers"]) >= 3
    assert all({"name", "primary", "secondary"} <= set(p) for p in data["dns_providers"])


def test_no_wmic_dependency_regression():
    text = source().lower().replace(" ", "")
    assert 'run(["wmic"' not in text
    assert "run(['wmic'" not in text
    assert 'shutil.which("wmic")' not in text


def test_sc_config_start_syntax_regression():
    text = source()
    assert "start=disabled" not in text
    assert '["sc", "config", name, "start=", value]' in text


def test_no_rich_taskid_update_chaining():
    text = source()
    assert ".add_task(" in text
    assert ").update(" not in text


def test_menu_has_expected_public_features():
    text = source()
    required = [
        "Gaming Session", "DNS Benchmark & Switch", "System Health",
        "Restore & History", "Process Inspector", "Windows Defender",
    ]
    for label in required:
        assert label in text


def test_main_menu_centralizes_clear():
    text = source()
    assert "Centralized CLS behavior" in text
    assert "console.clear()" in text


def test_recommended_performance_runs_both_actions():
    text = source()
    assert 'if c in ("1", "3"):' in text
    assert 'if c in ("2", "3"):' in text


def test_ultimate_performance_uses_returned_guid_and_verifies():
    text = source()
    assert '["powercfg", "/duplicatescheme", ULTIMATE_TEMPLATE_GUID]' in text
    assert 'new_guid = m.group(1).lower() if m else None' in text
    assert 'STATE["ultimate_guid"] = new_guid' in text


def test_main_menu_numbering_is_contiguous():
    tree = ast.parse(source())
    menu_keys = None
    for node in tree.body:
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == "MENU":
            menu_keys = [ast.literal_eval(k) for k in node.value.keys]
            break
    assert menu_keys == [str(i) for i in range(1, 22)]
