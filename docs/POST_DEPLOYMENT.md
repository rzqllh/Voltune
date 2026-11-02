# Post-Deployment Checklist

Use this after the repository has been pushed to GitHub. A green `git push` is deployment, not completion. Humans did, unfortunately, invent several more checkboxes after that.

## Repository presentation

- [ ] Repository name is `voltune`.
- [ ] Visibility is Public if this is being used as a portfolio project.
- [ ] GitHub **About** description is concise, for example: `State-aware Windows performance, maintenance, network, and recovery toolkit.`
- [ ] Add repository topics: `windows`, `python`, `cli`, `system-utilities`, `network-diagnostics`, `gaming`, `maintenance`, `pyinstaller`.
- [ ] Confirm the README banner renders correctly.
- [ ] Replace screenshot placeholders with screenshots captured from the real Windows build.
- [ ] Add at least Main Menu, DNS Benchmark, Gaming Preflight, and System Dashboard screenshots.
- [ ] Pin the repository on the GitHub profile if it is a portfolio project.

## Repository settings

- [ ] Confirm GitHub Actions are enabled.
- [ ] Confirm the CI workflow runs on `main` and pull requests.
- [ ] Confirm the release workflow has permission to create releases (`contents: write` is declared in the workflow).
- [ ] Enable Dependabot alerts/updates where available.
- [ ] Enable security scanning / CodeQL for the public repository where available.
- [ ] Protect `main` once the project is stable enough to require CI before merge.
- [ ] Disable unused repository features such as Wiki or Projects if they are not going to be maintained.

## Pre-release verification

- [ ] Run `python -m pytest`.
- [ ] Run `python -m compileall src voltune.py`.
- [ ] Run the full Windows integration checklist.
- [ ] Build `dist\\Voltune.exe` locally at least once.
- [ ] Launch the built EXE and verify UAC elevation.
- [ ] Verify Safe Mode is the default.
- [ ] Verify every menu can Back/Cancel cleanly to a cleared main screen.
- [ ] Verify Ultimate Performance install does not create duplicates.
- [ ] Verify DNS can be switched and restored.
- [ ] Verify Gaming Session restores after normal exit and after an interrupted session.
- [ ] Verify System Dashboard works on a current Windows 11 install without WMIC.

## First GitHub release

- [ ] Update `CHANGELOG.md`.
- [ ] Set the package version in `pyproject.toml` and `src/voltune/__init__.py` to the same value.
- [ ] Commit the release changes.
- [ ] Tag the release, for example `v0.1.0`.
- [ ] Push the tag.
- [ ] Wait for `Build release` to finish successfully.
- [ ] Confirm the GitHub Release contains `Voltune.exe` and `SHA256SUMS.txt`.
- [ ] Download the GitHub-built EXE yourself and launch it on Windows.
- [ ] Compare the downloaded EXE SHA-256 with the published checksum.
- [ ] Verify generated release notes are sensible; edit the release description if needed.

## User-facing release hygiene

- [ ] Clearly state that Voltune requires Windows 11 and Administrator privileges for privileged operations.
- [ ] State that the executable is unsigned unless a real code-signing certificate has been configured.
- [ ] Do **not** tell users to disable Defender or SmartScreen to run it.
- [ ] Link to `docs/SAFETY.md` from the release notes for higher-impact features.
- [ ] Keep `state.json`, `config.json`, logs, local machine paths, and personal data out of commits/releases.
- [ ] Test the downloadable release artifact, not only the source checkout.

## Portfolio polish

- [ ] Add a short demo GIF only after capturing it from the real app.
- [ ] Keep the README opening section short enough that the product is understandable before scrolling.
- [ ] Maintain at least one architecture diagram or concise architecture section as the project evolves.
- [ ] Keep issues and changelog current enough that the repository looks maintained rather than archaeologically preserved.
