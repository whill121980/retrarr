# Retrarr (Retro Retriever)

A ROM and disc image downloader for [MiSTer FPGA](https://mister-devel.github.io/MkDocs_MiSTer/), built as a spiritual successor to [MiSTer-ROMweasel](https://github.com/Koston-0xDEADBEEF/MiSTer-ROMweasel).

Browse and download verified No-Intro ROM sets and Redump disc images directly on your MiSTer, with a familiar dialog-based TUI over SSH.

## Why?

MiSTer-ROMweasel's archive.org identifiers (`nointro.snes`, etc.) went dark. Myrient shut down March 31, 2026. Retrarr was built from scratch to replace both with a modern, working solution.

## Features

- **52 supported systems** across Nintendo, Atari, NEC, Sega, SNK, Sony, Commodore, and more
- **Two download backends:**
  - `ni` -- No-Intro ROM sets via archive.org `ni-roms` (zip streaming through `view_archive.php`)
  - `ia` -- CHD/disc images via `ia download` CLI (PlayStation, Saturn, Mega CD, TG16-CD, AO486, CD32)
- **SHA1 verification** of every download against archive.org metadata
- **Encrypted credentials** -- archive.org login stored with AES-256-CBC, keyed to your device
- **Leveled logging** -- `error` / `warn` / `info` / `debug` with automatic rotation
- **Region and filter options** -- show/hide betas, prototypes, demos, unlicensed titles
- **AO486 integration** -- auto-generates MGL setnames and per-game configs for the 0MHz DOS Collection
- **Multi-disc CHD organization** -- automatically groups disc images into per-game subdirectories
- **Zaparoo integration** -- `--zaparoo` CLI mode for NFC-triggered downloads with progress gauge

## Supported Systems

| Manufacturer | Systems |
|---|---|
| Nintendo | NES, SNES, N64, Game Boy, Game Boy Color, Game Boy Advance, Pokemon Mini |
| Atari | 2600, 5200, 7800, Lynx, 800/XL/XE, ST |
| NEC | TurboGrafx-16 / PC Engine, TurboGrafx-CD / PC Engine CD, SuperGrafx |
| Sega | Master System, Game Gear, SG-1000, Mega Drive / Genesis, 32X, Mega CD / Sega CD, Saturn |
| SNK | Neo Geo Pocket, Neo Geo Pocket Color |
| Sony | PlayStation (USA, Europe, Japan, Japan #2, Miscellaneous) |
| Commodore | 64, VIC-20, 16 / Plus-4 |
| Microsoft | MSX, MSX2 |
| Bandai | RX-78 Gundam |
| Other | Intellivision, ColecoVision, Vectrex, Odyssey 2, Channel F, WonderSwan, WonderSwan Color, PV-1000, Bally Astrocade, Emerson Arcadia 2001, Adventure Vision, Bit Corp Gamate, Mega Duck, Epoch Super Cassette Vision, AO486 (0MHz DOS), Amiga CD32 |

## Requirements

- **MiSTer FPGA** running the standard Linux distribution (Mr. Fusion or equivalent)
- **archive.org account** ([free registration](https://archive.org/account/signup))
- All other dependencies are either pre-installed on MiSTer or installed automatically

## Installation

### Recommended — drop-in downloader.ini file

Retrarr ships a ready-to-use downloader registration file. Drop it into
`/media/fat/` on your MiSTer and `update_all` picks it up alongside your
existing `downloader.ini` — no editing of shared config.

**Option A — one-liner from SSH:**

```bash
wget https://raw.githubusercontent.com/whill121980/retrarr/beta/downloader_retrarr.ini \
  -O /media/fat/downloader_retrarr.ini
```

Then run `update_all` from the Scripts menu.

**Option B — create manually:**

Create `/media/fat/downloader_retrarr.ini` with these two lines:

```ini
[retrarr]
db_url = https://raw.githubusercontent.com/whill121980/retrarr/beta/db/retrarr.json
```

Then run `update_all`.

### Migrating from the deprecated `master` channel

Retrarr has moved to a channel-based release model. The old
single-`master` branch tried to be both bleeding-edge and stable at
the same time, which caused incoming updates to sometimes break
working installs. Master is now frozen (no more updates) so anyone
still installed from it can't be accidentally broken; new work
lives here on `beta`.

If your `/media/fat/downloader.ini` currently has a `[retrarr]`
section pointing at `/master/db/retrarr.json`, follow these steps
to switch to the beta channel:

1. **Remove the master entry** — edit `/media/fat/downloader.ini`
   and delete the two lines:

   ```ini
   [retrarr]
   db_url = https://raw.githubusercontent.com/whill121980/retrarr/master/db/retrarr.json
   ```

   `update_all` rejects duplicate `db_id: retrarr` registrations, so
   the beta drop-in would fail if the master entry is still there.

2. **Install the drop-in registration file** (see the Recommended
   install section above — same as a fresh install):

   ```bash
   wget https://raw.githubusercontent.com/whill121980/retrarr/beta/downloader_retrarr.ini \
     -O /media/fat/downloader_retrarr.ini
   ```

3. **Run `update_all`** from the Scripts menu. It'll pick up the
   drop-in file and pull the beta channel's current retrarr.sh.

Your existing settings, credentials, and download cache all live
under `/media/fat/Scripts/.config/retrarr/` and are preserved
across the migration.

### Fully manual (no update_all)

SSH into your MiSTer and run:

```bash
python3 -m ensurepip
pip3 install --upgrade pip
pip3 install internetarchive

# Copy retrarr.sh to your MiSTer (from your PC)
scp retrarr.sh root@<mister-ip>:/media/fat/Scripts/

# Run it
/media/fat/Scripts/retrarr.sh
```

All other dependencies (`zsh`, `curl`, `dialog`, `python3`, `xmllint`,
`7zr`, `unzip`, `jq`, `bc`, `numfmt`, `openssl`, `sha1sum`) are
pre-installed on stock MiSTer.

On first launch, Retrarr will prompt you to configure your archive.org
credentials.

## Usage

Launch the script and use the dialog menu to:

1. **Select a system** from the main menu
2. **Browse the game list** -- multi-select with spacebar
3. **Download** -- progress bars, SHA1 verification, automatic extraction to the correct game directory

### Settings

Access settings from the main menu (Settings button):

- **archive.org credentials** -- enter/update your login
- **Game directories** -- override default paths per-system or per-manufacturer group
- **Display filters** -- toggle betas, prototypes, demos, unlicensed titles
- **Region preference** -- filter by USA, Europe, Japan, World, or All
- **Advanced** -- log level info, clear metadata cache

### Zaparoo Mode

Retrarr can be called directly from [Zaparoo](https://github.com/wizzomafizzo/zaparoo) to download a game on demand -- tap an NFC tag, Retrarr downloads the game (if not already present), and outputs the file path for Zaparoo to launch.

```bash
# Download a specific game (exact match)
retrarr.sh --zaparoo SNES "Super Mario World (USA).zip"

# Search by keyword (shows picker if multiple matches)
retrarr.sh --zaparoo SNES "Mario"

# Wildcard search
retrarr.sh --zaparoo NES "*Mega Man*"

# CHD / disc system
retrarr.sh --zaparoo PSXUS "Crash Bandicoot"
```

- **Single match** -- downloads immediately with progress gauge
- **Multiple matches** -- shows a selection menu
- **Already downloaded** -- exits immediately, outputs existing file path
- **No credentials** -- fails fast with error (run `retrarr.sh` interactively first to set up)

The game file path is printed to stdout on success, making it easy to chain with other tools.

### Logging

Retrarr logs to `/media/fat/Scripts/.config/retrarr/retrarr.log` at `info` level by default.

```bash
# Watch the log live from a second SSH session
tail -f /media/fat/Scripts/.config/retrarr/retrarr.log

# Run with debug-level logging
RETRARR_DEBUG=1 /media/fat/Scripts/retrarr.sh

# Or set a specific level (error, warn, info, debug)
RETRARR_LOG_LEVEL=debug /media/fat/Scripts/retrarr.sh
```

## File Locations

| Path | Description |
|---|---|
| `/media/fat/Scripts/retrarr.sh` | The script |
| `/media/fat/Scripts/.config/retrarr/` | Config and cache directory |
| `/media/fat/Scripts/.config/retrarr/settings.sh` | User settings (credentials, paths, filters) |
| `/media/fat/Scripts/.config/retrarr/retrarr.log` | Log file |
| `/media/fat/Scripts/.config/retrarr/ni_cache/` | Per-system ROM catalog cache |

## Roadmap

See [`CHANGELOG.md`](CHANGELOG.md) for version history. Forward plans
are tracked in [GitHub Issues](https://github.com/whill121980/retrarr/issues).

## Credits

- Inspired by [MiSTer-ROMweasel](https://github.com/Koston-0xDEADBEEF/MiSTer-ROMweasel) by Koston-0xDEADBEEF
- Built for the [MiSTer FPGA](https://mister-devel.github.io/MkDocs_MiSTer/) community

## License

MIT
