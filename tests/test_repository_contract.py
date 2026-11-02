from __future__ import annotations

import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "src" / "voltune" / "app.py"


def source() -> str:
    return APP.read_text(encoding="utf-8")


def test_source_compiles():
    ast.parse(source())


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
    assert ").update(" not in source()


def test_menu_numbering_is_contiguous():
    tree = ast.parse(source())
    menu_keys = None
    for node in tree.body:
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == "MENU":
            menu_keys = [ast.literal_eval(k) for k in node.value.keys]
            break
    assert menu_keys == [str(i) for i in range(1, 28)]


def test_vnext_features_are_exposed():
    text = source()
    for label in ["Disk Analyzer", "Developer Cleanup", "Installer Cleanup", "Smart Uninstaller", "Live System Monitor", "Protected Paths"]:
        assert label in text


def test_no_top_level_voltune_module_shadows_package():
    assert not (ROOT / "voltune.py").exists()
    assert (ROOT / "run_voltune.py").exists()


def test_pyinstaller_spec_uses_non_shadowing_entrypoint():
    spec = (ROOT / "Voltune.spec").read_text(encoding="utf-8")
    assert 'run_voltune.py' in spec
    assert 'uac_admin=True' in spec
    assert 'voltune.py' not in spec.replace('run_voltune.py', '')
