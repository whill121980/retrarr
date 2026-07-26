# Bundled Binaries

This directory contains third-party binaries that Retrarr installs on the
MiSTer via `update_all`. Each binary is sourced from a publicly-reviewable
upstream and copied verbatim — Retrarr does not patch or rebuild them. If
you'd rather audit or replace them before installing, follow the source
links below and swap the file with your own build.

All binaries target MiSTer's userland: **ELF 32-bit LSB executable, ARM,
EABI5, statically linked**. Verify with `file bin/<name>` before publishing
any change.

## Licensing

**Both binaries in this directory are licensed under GPL v2.** The full
license text lives at [`LICENSES/GPL-2.0.txt`](../LICENSES/GPL-2.0.txt) at
the repo root. Redistribution obligations under GPL v2:

- Ship a copy of the GPL v2 license text alongside the binaries — done via
  `LICENSES/GPL-2.0.txt` in this repo.
- Point users to where they can obtain the source code — done via the
  upstream links below.
- No additional restrictions on the binaries themselves beyond GPL v2.
- If you modify a binary, mark it as modified. (We don't modify — we ship
  unmodified upstream builds.)

Retrarr's own source (retrarr.sh, docs, build scripts) is MIT-licensed —
see the top-level [`LICENSE`](../LICENSE) file. The MIT script and GPL
binaries are combined as "mere aggregation" under GPL v2 §2; neither
license infects the other.

---

## `aria2c-mister` — BitTorrent downloader

Used by Retrarr's Minerva Archive path (torrent-only source).

- **Upstream project:** [aria2/aria2](https://github.com/aria2/aria2)
- **License:** GPL v2 with OpenSSL linking exception. See
  [`aria2/COPYING`](https://github.com/aria2/aria2/blob/master/COPYING)
  and [`aria2/COPYING.OpenSSL`](https://github.com/aria2/aria2/blob/master/COPYING.OpenSSL)
- **Source code:** available at the upstream project link above
- **Static-build repo (source of this binary):**
  [abcfy2/aria2-static-build](https://github.com/abcfy2/aria2-static-build)
  — build scripts (no explicit license file at time of writing; the output
  binary is a derivative of aria2 and is therefore GPL v2)
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
  (chdman is part of MAME)
- **License:** GPL v2. From MAME's `COPYING`: *"MAME as a whole is made
  available under the terms of the GNU General Public License version 2."*
  See [`mame/COPYING`](https://github.com/mamedev/mame/blob/master/COPYING)
- **Source code:** available at the upstream project link above
- **Static-build repo (source of this binary):**
  [emmercm/chdman-js](https://github.com/emmercm/chdman-js)
  — Node.js wrapper (GPLv3) that ships prebuilt static chdman binaries
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
