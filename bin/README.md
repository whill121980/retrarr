# Bundled Binaries

This directory contains third-party binaries that Retrarr installs on the
MiSTer via `update_all`. Each binary is sourced from a publicly-reviewable
upstream and copied verbatim — Retrarr does not patch or rebuild them. If
you'd rather audit or replace them before installing, follow the source
links below and swap the file with your own build.

All binaries target MiSTer's userland: **ELF 32-bit LSB executable, ARM,
EABI5, statically linked**. Verify with `file bin/<name>` before publishing
any change.

---

## `aria2c-mister` — BitTorrent downloader

Used by Retrarr's Minerva Archive path (torrent-only source).

- **Upstream project:** [aria2/aria2](https://github.com/aria2/aria2)
  (GPLv2+, upstream binary)
- **Static-build repo (source of this binary):**
  [abcfy2/aria2-static-build](https://github.com/abcfy2/aria2-static-build)
  (MIT-licensed build scripts around the upstream aria2 source)
- **Release used:**
  [`1.37.0`](https://github.com/abcfy2/aria2-static-build/releases/tag/1.37.0)
- **Asset:** `aria2-armv7-linux-musleabihf_static.zip` → `aria2c` extracted
- **Verified:** `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV),
  statically linked, stripped`, 12,304,196 bytes,
  md5 `69f0d35fdda41dd6bebbd4cf6ed79008`

Installed to `Scripts/.retrarr/aria2c` on the MiSTer. Retrarr checks
`command -v aria2c` first, then falls back to that path.

---

## `chdman-mister` — CHD ↔ CUE/BIN converter

Used by Retrarr to convert Dreamcast (and other CD-format) downloads
from CHD to formats accepted by cores that don't read CHD natively
(e.g. DreamSTer wants `.cue`/`.gdi`/`.cdi`).

- **Upstream project:** [mamedev/mame](https://github.com/mamedev/mame)
  (part of MAME, BSD-3-Clause)
- **Static-build repo (source of this binary):**
  [emmercm/chdman-js](https://github.com/emmercm/chdman-js)
  (MIT-licensed Node.js wrapper that ships prebuilt static binaries)
- **Version:** MAME `0.288.1` (chdman-js `v0.288.1`)
- **Path in repo:**
  [`packages/chdman-linux-arm/chdman-armv7`](https://github.com/emmercm/chdman-js/blob/main/packages/chdman-linux-arm/chdman-armv7)
- **Verified:** `ELF 32-bit LSB pie executable, ARM, EABI5 version 1 (SYSV),
  static-pie linked, stripped`, 1,231,260 bytes

Installed to `Scripts/.retrarr/chdman` on the MiSTer. Retrarr checks
`command -v chdman` first, then falls back to that path.

---

## Rebuilding the DB after replacing a binary

```bash
file bin/<name>              # confirm ELF/ARM/EABI5
bash db/build_db.sh          # regenerates db/retrarr.json with new hash + size
git diff db/retrarr.json     # sanity-check hash change
git add bin/<name> db/retrarr.json
git commit && git push
```

Every binary is size- and md5-pinned in `db/retrarr.json`, so any change
here requires a matching DB regenerate before `update_all` will accept the
new file.
