from __future__ import annotations

import os
import time
from pathlib import Path

from voltune.cli import build_parser
from voltune.core.safety import FilesystemSafety, RiskLevel
from voltune.features.storage_intelligence import find_installers, scan_dev_artifacts
from voltune.features.uninstaller import InstalledApp, uninstall_command


def test_safety_blocks_filesystem_root():
    safety = FilesystemSafety(protected_paths=[])
    root = Path(Path.cwd().anchor or "/")
    assert safety.evaluate(root).allowed is False


def test_explicit_empty_protected_paths_disables_defaults():
    safety = FilesystemSafety(protected_paths=[])
    assert safety.protected_paths == []


def test_safety_blocks_whitelisted_intersection(tmp_path: Path):
    protected = tmp_path / "models"
    protected.mkdir()
    safety = FilesystemSafety(protected_paths=[], whitelist=[protected])
    assert not safety.evaluate(protected / "x").allowed
    assert not safety.evaluate(tmp_path).allowed


def test_safety_blocks_symlink(tmp_path: Path):
    target = tmp_path / "target"
    target.mkdir()
    link = tmp_path / "link"
    try:
        link.symlink_to(target, target_is_directory=True)
    except OSError:
        return
    safety = FilesystemSafety(protected_paths=[])
    decision = safety.evaluate(link)
    assert not decision.allowed
    assert decision.is_reparse_point


def test_delete_dry_run_keeps_target(tmp_path: Path):
    target = tmp_path / "cache"
    target.mkdir()
    (target / "a.bin").write_bytes(b"x" * 10)
    safety = FilesystemSafety(protected_paths=[])
    result = safety.delete(target, dry_run=True, risk=RiskLevel.CAUTION)
    assert result.allowed and result.dry_run and not result.deleted
    assert target.exists()


def test_recent_dev_artifact_not_selected(tmp_path: Path):
    project = tmp_path / "project"
    project.mkdir()
    (project / "package.json").write_text("{}")
    artifact = project / "node_modules"
    artifact.mkdir()
    (artifact / "x").write_bytes(b"x")
    rows = scan_dev_artifacts([tmp_path], recent_days=7, safety=FilesystemSafety(protected_paths=[]))
    assert len(rows) == 1
    assert rows[0].recent is True
    assert rows[0].default_selected is False


def test_old_dev_artifact_selected(tmp_path: Path):
    project = tmp_path / "project"
    project.mkdir()
    marker = project / "package.json"
    marker.write_text("{}")
    artifact = project / "node_modules"
    artifact.mkdir()
    old = time.time() - 30 * 86400
    os.utime(project, (old, old)); os.utime(marker, (old, old)); os.utime(artifact, (old, old))
    rows = scan_dev_artifacts([tmp_path], recent_days=7, safety=FilesystemSafety(protected_paths=[]))
    assert rows[0].default_selected is True


def test_generic_zip_is_not_treated_as_installer(tmp_path: Path):
    old = time.time() - 30 * 86400
    generic = tmp_path / "photos.zip"
    generic.write_bytes(b"x" * 1024)
    setup = tmp_path / "driver-setup.zip"
    setup.write_bytes(b"x" * 1024)
    os.utime(generic, (old, old)); os.utime(setup, (old, old))
    rows = find_installers([tmp_path], min_size_bytes=1, min_age_days=1)
    assert [Path(r.path).name for r in rows] == ["driver-setup.zip"]


def test_msi_uninstall_is_normalized_to_remove():
    app = InstalledApp("X", "", "", "MsiExec.exe /I{ABC-123}", "", "HKLM")
    cmd = uninstall_command(app)
    assert cmd[0].lower().endswith("msiexec.exe")
    assert cmd[1].upper().startswith("/X{")


def test_cli_exposes_machine_readable_commands():
    parser = build_parser()
    assert parser.parse_args(["status", "--json"]).command == "status"
    assert parser.parse_args(["analyze", "--json"]).command == "analyze"
    assert parser.parse_args(["dev-clean", "--json"]).command == "dev-clean"


def test_allowed_scope_does_not_authorize_parent(tmp_path: Path):
    protected = tmp_path / "system"
    cleanup = protected / "temp"
    cleanup.mkdir(parents=True)
    safety = FilesystemSafety(protected_paths=[protected], allowed_scopes=[cleanup])
    assert safety.evaluate(cleanup / "cache.bin").allowed
    assert not safety.evaluate(protected).allowed


def test_unmarked_build_folder_is_not_dev_artifact(tmp_path: Path):
    folder = tmp_path / "build"
    folder.mkdir()
    (folder / "important.txt").write_text("not a build artifact")
    rows = scan_dev_artifacts([tmp_path], recent_days=7, safety=FilesystemSafety(protected_paths=[]))
    assert rows == []


def test_shell_based_uninstaller_is_rejected():
    app = InstalledApp("X", "", "", 'cmd.exe /c "do-something"', "", "HKLM")
    assert uninstall_command(app) == []


def test_recent_source_file_protects_old_artifact(tmp_path: Path):
    project = tmp_path / "project"
    project.mkdir()
    marker = project / "package.json"
    marker.write_text("{}")
    source = project / "main.js"
    source.write_text("console.log('active')")
    artifact = project / "node_modules"
    artifact.mkdir()
    old = time.time() - 30 * 86400
    os.utime(project, (old, old)); os.utime(marker, (old, old)); os.utime(artifact, (old, old))
    # source remains recent
    rows = scan_dev_artifacts([tmp_path], recent_days=7, safety=FilesystemSafety(protected_paths=[]))
    assert rows[0].recent is True
    assert rows[0].default_selected is False
