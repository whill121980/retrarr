# Bundled Binaries

## aria2c-mister

A statically-linked `aria2c` binary compiled for MiSTer's userland
(armv7l, kernel 4.19, minimal Buildroot rootfs).

When present, `db/build_db.sh` includes it in the update_all DB so
retrarr and aria2c install together. It lands in `/media/fat/linux/`
on the MiSTer (already on PATH).

### Sourcing a binary

Options, in rough order of trust:

1. **Compile on MiSTer** — SSH in, build aria2 from source with
   `--enable-static`. Slow but reproducible.
2. **Static ARM release from aria2's official downloads** — the
   project publishes some prebuilt static binaries per release.
   Verify architecture matches (armv7l/armhf, not aarch64).
3. **Community MiSTer distributions** — the ROMweasel predecessor
   and various downloader scripts have bundled aria2 over the years.

Whatever you use, verify:

```bash
file bin/aria2c-mister
# Expected: ELF 32-bit LSB executable, ARM, ... statically linked
```

Then rebuild the DB:

```bash
bash db/build_db.sh
```

commit both `bin/aria2c-mister` and `db/retrarr.json`, and push.
