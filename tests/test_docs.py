from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_expected_public_repository_files_exist():
    expected = [
        "README.md", "LICENSE", "CHANGELOG.md", "CONTRIBUTING.md", "SECURITY.md",
        "config.example.json", "requirements.txt", "requirements-dev.txt", "pyproject.toml",
        "docs/FEATURES.md", "docs/SAFETY.md", "docs/BUILD.md", "docs/ARCHITECTURE.md", "docs/WINDOWS_TEST_CHECKLIST.md",
        ".github/workflows/ci.yml", ".github/workflows/build-release.yml",
    ]
    missing = [name for name in expected if not (ROOT / name).exists()]
    assert not missing, f"Missing public repository files: {missing}"
