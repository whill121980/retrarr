# Changelog

All notable changes to Retrarr (MiSTer FPGA) are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
Retrarr uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Sections used:

- **Added** — new features and integrations
- **Changed** — updates to existing behavior, non-breaking refinements
- **Fixed** — bug fixes

## [0.2.2] — 2026-07-26

Beta channel established. Codebase equivalent to v0.2.1 with the
install path modernized around a drop-in registration file.

### Added

- `downloader_retrarr.ini` at repo root — drop-in registration file
  for `update_all`'s `downloader_*.ini` auto-scan. Users install by
  placing this one file in `/media/fat/`, no editing of shared config
  required

### Changed

- Version bumped `v0.2.1` → `v0.2.2` to mark the new beta channel
- Install path documented in README as drop-in-file first; manual
  edit of `downloader.ini` is no longer recommended
- `db/build_db.sh` — URLs now pinned to the current git branch
  instead of hardcoded to `master`; uses `git branch --show-current`
  for unambiguous detection

## [0.2.1]

### Added

- 19 new systems, splitting the picker into Console / Computer
  categories
- Zaparoo mode (`retrarr.sh --zaparoo CORE "game name"`) for
  NFC-triggered on-demand downloads
- Leveled logging (`error` / `warn` / `info` / `debug`) with
  automatic rotation
- Encrypted credential storage (AES-256-CBC, device-keyed)
- Self-bootstrap of `internetarchive` Python package on first launch

## [0.2.0]

### Added

- Initial release
- No-Intro ROM downloads via `ni-roms` on Internet Archive
  (view_archive.php zip streaming)
- CHD/disc downloads via `ia download` for PlayStation, Saturn,
  Mega CD, TG16-CD, and CD32
- Dialog-based TUI over SSH
- SHA1 verification against archive.org metadata
- `update_all`/`downloader` integration via custom DB
