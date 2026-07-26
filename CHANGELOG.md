# Changelog

All notable changes to Retrarr are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); Retrarr uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Sections used:

- **Added** — new features and integrations
- **Changed** — updates to existing behavior, non-breaking refinements
- **Fixed** — bug fixes

## [Unreleased]

Nothing yet.

## [0.3.5] — 2026-07-26

Alpha channel established. Rolling development branch for new
feature testing before graduation to beta.

### Added

- `downloader_retrarr.ini` at repo root — drop-in registration file
  pointing at the alpha DB. Users install by placing this one file
  in `/media/fat/`, no editing of shared config required
- Explicit third-party binary attribution in
  [`bin/README.md`](bin/README.md) — upstream projects, static-build
  sources, exact tags/versions, verified file properties, GPL v2
  compliance notes
- Top-level `LICENSE` (MIT for Retrarr's source) and
  `LICENSES/GPL-2.0.txt` for the bundled binaries
- Skip-if-exists check in `download_roms` — files already present at
  the destination are counted separately and not re-downloaded;
  summary msgbox reports `N downloaded, M skipped, K failed`
- Minerva download stall detection with 30-second progress logging —
  aborts with a clear "stalled" message when no bytes have transferred
  in 60s, instead of burning the full 5-minute max wait

### Changed

- Version bumped `v0.3.4` → `v0.3.5` to mark the alpha channel
- `db/build_db.sh` — branch detection uses `git branch --show-current`
  (git 2.22+) instead of `git rev-parse --abbrev-ref HEAD`, which was
  ambiguous when a tag shared the branch name
- IA extract path now captures stderr+stdout and checks exit codes,
  surfacing the actual error text in a dialog + log instead of
  swallowing it behind `-qq`/`-y` and `&& rm -f`
- AO486 branch order in `ia_download_rom` repaired — the previous
  condition made the AO486-specific `.mgl` setname post-processing
  unreachable dead code; 0MHz files now unzip and post-process correctly

### Fixed

- 0MHz DOS Collection extracts silently failing when unzip errors
  couldn't survive the next dialog repaint (same swallow-errors
  pattern that hit Minerva)

## [0.3.4] — 2026-07-26

### Added

- **Multi-disc menu collapse** — game picker groups `(Disc N)` entries
  into a single row per game, e.g. `Final Fantasy VII (USA) [3 discs]`;
  selecting it queues all discs in one operation. Applies to CD-based
  cores only (PSX, MCD, SS, TG16CD, CD32)
- **Per-game folders for all CD cores** — both IA and Minerva paths
  now route CD downloads through `${CORE_GAMEDIR}/<game>/`
  subdirectories. Documented requirement for PSX_MiSTer (per-game
  virtual memory cards, auto disc-swap needs all discs in one folder);
  compatible with the other CD cores. No M3U — MiSTer cores don't
  use `.m3u` the way RetroArch does
- `is_cd_core()` helper and `strip_to_gamebase()` helper

### Changed

- Minerva torrent behavior is now torrent-native:
  - Dropped `--bt-stop-timeout=90` — was killing downloads whenever
    the swarm briefly went quiet (opposite of what a torrent client
    should do); the polling loop's 5-minute max still caps total time
  - Segment file (`.aria2`) preserved across all outcomes — retries
    now resume from verified pieces, multi-disc games benefit from
    piece history accumulated by their siblings
  - `--bt-max-peers=100` (up from 55) and
    `--bt-request-peer-speed-limit=500K` for more aggressive leeching
- Folder naming preserves every filename tag except the disc marker —
  `(USA)`, `(Rev 2)`, `(Alt)` etc. all survive; runs of spaces from
  removal get collapsed and edges trimmed

### Fixed

- aria2c partial downloads (exit code 7) no longer slip through to
  the extract step. With `--file-allocation=none`, an incomplete file
  exists at its full byte length with zeroed holes where missing
  pieces belong; retrarr now checks the exit code and aborts with a
  clear "download incomplete" message
- Minerva torrent index lookup now matches basename exactly instead
  of using `path.endswith()`, which had been picking
  `Super Mario All-Stars + Super Mario World` for a request of
  `Super Mario World`

## [0.3.3] — 2026-07-25

### Added

- Bundled `aria2c` 1.37.0 (armv7l static from
  [abcfy2/aria2-static-build](https://github.com/abcfy2/aria2-static-build))
  installed to `Scripts/.retrarr/aria2c` — Minerva torrent downloads
  work out of the box on a fresh MiSTer
- Debug logging of the exact aria2c command before invocation for
  reproducibility

### Changed

- `bootstrap_deps` runs `python3 -m ensurepip` + `pip install
  internetarchive` automatically without a yes/no prompt; launching
  retrarr is opt-in enough
- Minerva extract path captures error text on failure and shows it
  in a dialog + log instead of swallowing behind `-qq`

### Fixed

- **`bootstrap_deps` false-positive skip** — a stale `ia` shim on
  PATH (from a partial pip install) made `[[ -n $IA ]]` true and
  short-circuited the whole first-time-setup flow, then `ia_login`
  crashed on the missing Python module. Now checks both the CLI
  and that `import internetarchive` actually works
- Busybox `which` bug — MiSTer's `which` prints `<cmd> not found`
  to **stdout** (not stderr) when the target is missing, so
  `$(which foo 2>/dev/null)` captured "aria2c not found" as the
  path and produced errors like `command not found: aria2c not
  found` when the variable was invoked. Switched to `command -v`
- `IA`/`ARIA2C` no longer declared `typeset -gr` at init — the
  readonly attribute was silently preventing bootstrap from
  refreshing them after a successful install

## [0.3.2] — 2026-06-15

### Fixed

- Multi-disc path stripping — `${tag% (Disc [0-9AB])*}` wasn't
  escaping the parentheses so nothing matched; now
  `${tag% \(Disc [0-9AB]\)*}`. Multi-disc games now correctly land
  in per-game subfolders on the IA path

## [0.3.1] — 2026-04-09

### Added

- **Minerva Archive** as a full second source with three collections:
  - RetroAchievements (hash-verified ROMs)
  - No-Intro (dat-verified dumps)
  - Redump (disc images)
- Source-separated menus — Minerva and Internet Archive are distinct
  top-level paths; no cross-source merging (deliberate design)
- Async torrent downloads with peer-timeout detection so the UI
  stays responsive
- Bazzite/RetroDECK port (`retrarr-bazzite.sh`) with ES-DE folder
  conventions
- WSL/RetroBat port (`retrarr-wsl.sh`) with RetroBat folder
  conventions
- BIOS download menu on the Bazzite/WSL ports (Settings → BIOS)
- Minerva reliability warning in the README

### Changed

- ni-roms downloads use `aria2c` with curl fallback (faster,
  supports resume)

### Fixed

- Redump regex crash from a capturing group leaking a tuple to
  `re.findall`
- RA size parser reads Minerva's `<span>` markup instead of the
  earlier `<td>` assumption
- Bazzite ES-DE ROM paths corrected for 10 systems where
  RetroDECK uses different folder names than the MiSTer
  convention
- Read-only `status` variable collision in `bios_download` (zsh
  special)

## [0.2.1]

### Added

- 19 new systems, splitting the picker into Console / Computer
  categories
- Zaparoo mode (`retrarr.sh --zaparoo CORE "game name"`) for
  NFC-triggered on-demand downloads
- Leveled logging (`error` / `warn` / `info` / `debug`) with
  automatic rotation
- Encrypted credential storage (AES-256-CBC, device-keyed)
- Self-bootstrap of `internetarchive` Python package on first
  launch

## [0.2.0]

### Added

- Initial release
- No-Intro ROM downloads via `ni-roms` on Internet Archive
  (view_archive.php zip streaming)
- CHD/disc downloads via `ia download` for PlayStation, Saturn,
  Mega CD, TG16-CD, and CD32
- Dialog-based TUI over SSH
- SHA1 verification against archive.org metadata
- update_all/downloader integration via custom DB

[Unreleased]: https://github.com/whill121980/retrarr/compare/v0.3.4...devel
[0.3.4]: https://github.com/whill121980/retrarr/releases/tag/v0.3.4
[0.3.3]: https://github.com/whill121980/retrarr/releases/tag/v0.3.3
[0.3.2]: https://github.com/whill121980/retrarr/releases/tag/v0.3.2
[0.3.1]: https://github.com/whill121980/retrarr/releases/tag/v0.3.1
