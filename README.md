# Retrarr (Retro Retriever)

A ROM and disc image downloader for [MiSTer FPGA](https://mister-devel.github.io/MkDocs_MiSTer/), built as a spiritual successor to [MiSTer-ROMweasel](https://github.com/Koston-0xDEADBEEF/MiSTer-ROMweasel).

Browse and download verified No-Intro ROM sets and Redump disc images directly on your MiSTer, with a familiar dialog-based TUI over SSH.

## Why?

MiSTer-ROMweasel's archive.org identifiers (`nointro.snes`, etc.) went dark. Myrient shut down March 31, 2026. Retrarr was built from scratch to replace both with a modern, working solution.

## Features

- **33 supported systems** across Nintendo, Atari, NEC, Sega, Sony, and more
- **Two download backends:**
  - `ni` -- No-Intro ROM sets via archive.org `ni-roms` (zip streaming through `view_archive.php`)
  - `ia` -- CHD/disc images via `ia download` CLI (PlayStation, Saturn, Sega CD, TG16-CD, AO486, CD32)
- **SHA1 verification** of every download against archive.org metadata
- **Encrypted credentials** -- archive.org login stored with AES-256-CBC, keyed to your device
- **Leveled logging** -- `error` / `warn` / `info` / `debug` with automatic rotation
- **Region and filter options** -- show/hide betas, prototypes, demos, unlicensed titles
- **AO486 integration** -- auto-generates MGL setnames and per-game configs for the 0MHz DOS Collection
- **Multi-disc CHD organization** -- automatically groups disc images into per-game subdirectories

## Supported Systems

| Manufacturer | Systems |
|---|---|
| Nintendo | NES, SNES, N64, Game Boy, Game Boy Color, Game Boy Advance |
| Atari | 2600, 5200, 7800, Lynx |
| NEC | TurboGrafx-16 / PC Engine, TurboGrafx-CD / PC Engine CD, SuperGrafx |
| Sega | Master System, Game Gear, SG-1000, Mega Drive / Genesis, Mega CD / Sega CD, Saturn |
| Sony | PlayStation (USA, Europe, Japan, Japan #2, Miscellaneous) |
| Other | ColecoVision, Vectrex, Odyssey 2, Channel F, WonderSwan, WonderSwan Color, PV-1000, AO486 (0MHz DOS), Amiga CD32 |

## Requirements

- **MiSTer FPGA** running the standard Linux distribution (Mr. Fusion or equivalent)
- **archive.org account** ([free registration](https://archive.org/account/signup))
- All other dependencies are either pre-installed on MiSTer or installed automatically

## Installation

### Option 1: Automatic (via downloader.ini)

Add the following to `/media/fat/downloader.ini` on your MiSTer:

```ini
[retrarr]
db_url = https://raw.githubusercontent.com/whill121980/retrarr/main/db/retrarr.json
```

The next time `update_all` or `downloader` runs, Retrarr and its dependencies will be installed automatically.

### Option 2: Manual

SSH into your MiSTer and run the following:

```bash
# 1. Bootstrap pip (not installed by default)
python3 -m ensurepip

# 2. Upgrade pip to latest
pip3 install --upgrade pip

# 3. Install the internetarchive CLI
pip3 install internetarchive

# 4. Copy retrarr.sh to your MiSTer (from your PC)
#    scp retrarr.sh root@<mister-ip>:/media/fat/Scripts/

# 5. Run it
/media/fat/Scripts/retrarr.sh
```

All other dependencies (`zsh`, `curl`, `dialog`, `python3`, `xmllint`, `7zr`, `unzip`, `jq`, `bc`, `numfmt`, `openssl`, `sha1sum`) are pre-installed on stock MiSTer.

On first launch, Retrarr will prompt you to configure your archive.org credentials.

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

- **v0.2.x** -- Region filtering, multi-disc PSX testing, CD32 validation
- **v0.3** -- Resume interrupted downloads, controller/gamepad navigation, download queue
- **v0.4** -- Multi-platform support (RetroPie, Bazzite/SteamOS, RetroArch)
- **v1.0** -- *Arr-style architecture: REST API server, web UI, RetroNAS integration, ScreenScraper metadata

## Credits

- Inspired by [MiSTer-ROMweasel](https://github.com/Koston-0xDEADBEEF/MiSTer-ROMweasel) by Koston-0xDEADBEEF
- ROM sets provided by [archive.org](https://archive.org)
- Built for the [MiSTer FPGA](https://mister-devel.github.io/MkDocs_MiSTer/) community

## License

MIT
