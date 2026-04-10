#!/bin/zsh
# retrarr.sh — Retro Retriever v0.2.1
# Spiritual successor to MiSTer-ROMweasel by Koston-0xDEADBEEF
#
# Sources:
#   No-Intro sets : archive.org/details/ni-roms  (view_archive.php streaming)
#   CHD/disc sets : archive.org (ia download)
#
# Requirements:
#   - internetarchive CLI : pip3 install internetarchive
#     Run 'ia configure' once to set up archive.org credentials
#   - python3, xmllint, 7zr, unzip, jq, bc, numfmt, dialog
#
# TODO (future *Arr/RetroNAS integration):
#   - Offload downloads to server, MiSTer script becomes thin REST client
#   - Add REST API layer + web UI

setopt localoptions extendedglob pipefail warnnestedvar nullglob

autoload zmv

# ─── STATIC GLOBALS ────────────────────────────────────────────────────────────

init_static_globals () {
  typeset -g PLATFORM_FLAVOR="linux-retrodeck"
  typeset -g RETRODECK_ROOT="${RETRODECK_ROOT:-${HOME}/retrodeck}"
  if [[ ! -d "${RETRODECK_ROOT}/roms" ]]; then
    for cand in "${HOME}/retrodeck" "${HOME}/RetroDECK" "/var/home/${USER}/retrodeck"; do
      if [[ -d "${cand}/roms" ]]; then
        RETRODECK_ROOT="${cand}"
        break
      fi
    done
  fi

    typeset -gr RETRARR_VERSION="Retro Retriever v0.2.1"

    # Required binaries
    typeset -gr XMLLINT=$(which xmllint)  || { print -u2 "ERROR: xmllint not found"  ; return 1 }
    typeset -gr CURL=$(which curl)        || { print -u2 "ERROR: curl not found"      ; return 1 }
    typeset -gr DIALOG=$(which dialog)    || { print -u2 "ERROR: dialog not found"    ; return 1 }
    typeset -gr SHA1SUM=$(which sha1sum)  || { print -u2 "ERROR: sha1sum not found"   ; return 1 }
    typeset -gr SZR=$(which 7zr)          || { print -u2 "ERROR: 7zr not found"       ; return 1 }
    typeset -gr UNZIP=$(which unzip)      || { print -u2 "ERROR: unzip not found"     ; return 1 }
    typeset -gr NUMFMT=$(which numfmt)    || { print -u2 "ERROR: numfmt not found"    ; return 1 }
    typeset -gr BC=$(which bc)            || { print -u2 "ERROR: bc not found"        ; return 1 }
    typeset -gr JQ=$(which jq)            || { print -u2 "ERROR: jq not found"        ; return 1 }
    typeset -gr PYTHON=$(which python3)   || { print -u2 "ERROR: python3 not found"   ; return 1 }
    typeset -gr OPENSSL=$(which openssl)  || { print -u2 "ERROR: openssl not found"   ; return 1 }

    # Optional: aria2c for faster downloads (multi-connection, resume, torrent support)
    typeset -gr ARIA2C=$(which aria2c 2>/dev/null || print "")

    # internetarchive CLI — pip3 install internetarchive
    typeset -gr IA=$(which ia 2>/dev/null || print "")

    # MiSTer SSL CA bundle is outdated — suppress cert warnings
    # Fix: apt-get update && apt-get install -y ca-certificates && update-ca-certificates
    typeset -gra CURL_OPTS=(--connect-timeout 10 --retry 3 --retry-delay 5 -k)

    # Paths
    typeset -gr WRK_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/retrarr"
    typeset -gr SETTINGS_SH="${WRK_DIR}/settings.sh"
    typeset -gr CACHE_DIR="${WRK_DIR}/cache"
    typeset -gr NI_CACHE_DIR="${WRK_DIR}/ni-roms"   # per-system filtered XMLs

    # ni-roms — archive.org item for all No-Intro sets
    # Individual files served via view_archive.php zip streaming endpoint
    typeset -gr NI_IDENTIFIER="ni-roms"
    typeset -gr NI_FILES_XML="${WRK_DIR}/ni-roms_files.xml"
    typeset -gr NI_META_URL="https://archive.org/metadata/ni-roms"

    # Populated at runtime by init_ni_roms_node() and init_ia_cookie()
    typeset -g NI_NODE=""    # e.g. ia902803.us.archive.org
    typeset -g NI_DIR=""     # e.g. /17/items/ni-roms
    typeset -g IA_COOKIE=""  # logged-in-user=...; logged-in-sig=...

    # Dialog
    typeset -gr MAXHEIGHT=$(( $LINES  - 4 ))
    typeset -gr MAXWIDTH=$(( $COLUMNS - 4 ))
    typeset -gr DIALOG_OK=0
    typeset -gr DIALOG_CANCEL=1
    typeset -gr DIALOG_HELP=2
    typeset -gr DIALOG_EXTRA=3
    typeset -gr DIALOG_ESC=255
    typeset -grx NCURSES_NO_UTF8_ACS=1

    typeset -gr DIALOG_TEMPFILE=$(mktemp 2>/dev/null) || DIALOG_TEMPFILE=/tmp/retrarr_$$

    typeset -gr SIG_HUP=1
    typeset -gr SIG_INT=2
    typeset -gr SIG_QUIT=3
    typeset -gr SIG_TERM=15

    # Logging — levels: error=0 warn=1 info=2 debug=3
    # RETRARR_DEBUG=1 forces debug level; RETRARR_LOG_LEVEL overrides default
    # Watch in second SSH session: tail -f ${XDG_CONFIG_HOME:-$HOME/.config}/retrarr/retrarr.log
    typeset -gr LOG_FILE="${WRK_DIR}/retrarr.log"
    typeset -gr LOG_MAX_BYTES=1048576  # 1 MB — rotate at startup if exceeded
    typeset -gri LOG_ERROR=0
    typeset -gri LOG_WARN=1
    typeset -gri LOG_INFO=2
    typeset -gri LOG_DEBUG=3
    if [[ ${RETRARR_DEBUG:-0} -eq 1 ]]; then
        typeset -gri LOG_LEVEL=$LOG_DEBUG
    else
        case ${RETRARR_LOG_LEVEL:-info} in
            error) typeset -gri LOG_LEVEL=$LOG_ERROR ;;
            warn)  typeset -gri LOG_LEVEL=$LOG_WARN  ;;
            debug) typeset -gri LOG_LEVEL=$LOG_DEBUG  ;;
            *)     typeset -gri LOG_LEVEL=$LOG_INFO   ;;
        esac
    fi

    # ── Supported cores ────────────────────────────────────────────────────────
    # SUPPORTED_CORES is the union of consoles + computers (used by
    # fetch_metadata, Zaparoo validation, etc.).  The two sub-arrays drive
    # the top-level Console / Computer menu split.

    typeset -gra CONSOLE_CORES=( \
        "NES"        "Nintendo Entertainment System"       \
        "SNES"       "Super Nintendo"                      \
        "N64"        "Nintendo 64"                         \
        "GB"         "Nintendo GameBoy"                    \
        "GBC"        "Nintendo GameBoy Color"              \
        "GBA"        "GameBoy Advance"                     \
        "POKEMINI"   "Nintendo Pokemon Mini"               \
        "A2600"      "Atari 2600"                          \
        "A5200"      "Atari 5200"                          \
        "A7800"      "Atari 7800"                          \
        "LYNX"       "Atari Lynx"                          \
        "TG16"       "NEC TurboGrafx-16 / PC-Engine"       \
        "TG16CD"     "NEC TurboGrafx-CD / PC-Engine CD"    \
        "SGX"        "NEC SuperGrafx"                      \
        "SMS"        "SEGA Master System"                  \
        "GG"         "SEGA Game Gear"                      \
        "SG1000"     "SEGA SG-1000"                        \
        "MD"         "SEGA Mega Drive"                     \
        "S32X"       "SEGA 32X"                            \
        "MCD"        "SEGA MegaCD / SegaCD"                \
        "SS"         "SEGA Saturn"                         \
        "NGP"        "SNK Neo Geo Pocket"                  \
        "NGPC"       "SNK Neo Geo Pocket Color"            \
        "PSXUS"      "Sony PlayStation USA"                \
        "PSXEU"      "Sony PlayStation Europe"             \
        "PSXJP"      "Sony PlayStation Japan"              \
        "PSXJP2"     "Sony PlayStation Japan \#2"          \
        "PSXMISC"    "Sony PlayStation Miscellaneous"      \
        "INTV"       "Mattel Intellivision"                \
        "COLECO"     "ColecoVision"                        \
        "VECTREX"    "GCE Vectrex"                         \
        "ODYSSEY2"   "Magnavox Odyssey 2"                  \
        "CHANNELF"   "Fairchild Channel F"                 \
        "WS"         "WonderSwan"                          \
        "WSC"        "WonderSwan Color"                    \
        "PV1000"     "Casio PV-1000"                       \
        "ASTROCADE"  "Bally Astrocade"                     \
        "ARCADIA"    "Emerson Arcadia 2001"                \
        "ADVISION"   "Entex Adventure Vision"              \
        "GAMATE"     "Bit Corporation Gamate"              \
        "MEGADUCK"   "Welback Mega Duck"                   \
        "SCV"        "Epoch Super Cassette Vision"         \
    )

    typeset -gra COMPUTER_CORES=( \
        "C64"        "Commodore 64"                        \
        "VIC20"      "Commodore VIC-20"                    \
        "C16"        "Commodore 16 / Plus-4"               \
        "MSX"        "Microsoft MSX"                       \
        "MSX2"       "Microsoft MSX2"                      \
        "ATARIST"    "Atari ST"                            \
        "ATARI800"   "Atari 800 / XL / XE"                 \
        "RX78"       "Bandai RX-78 Gundam"                 \
        "AO486"      "0MHz DOS Collection"                 \
        "CD32"       "Amiga CD32"                          \
    )

    typeset -gra SUPPORTED_CORES=( $CONSOLE_CORES $COMPUTER_CORES )

    # ── ni-roms backend: No-Intro sets ─────────────────────────────────────────
    # NI_SYSTEM_ZIP = the zip filename within ni-roms/roms/
    # Must match exactly what archive.org has in ni-roms_files.xml

    typeset -gr NES_BACKEND="ni"
    typeset -gr NES_NI_SYSTEM_ZIP="Nintendo - Nintendo Entertainment System (Headered).zip"
    typeset -gr NES_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/nes"

    typeset -gr SNES_BACKEND="ni"
    typeset -gr SNES_NI_SYSTEM_ZIP="Nintendo - Super Nintendo Entertainment System.zip"
    typeset -gr SNES_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/snes"

    typeset -gr N64_BACKEND="ni"
    typeset -gr N64_NI_SYSTEM_ZIP="Nintendo - Nintendo 64 (BigEndian).zip"
    typeset -gr N64_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/n64"

    typeset -gr GB_BACKEND="ni"
    typeset -gr GB_NI_SYSTEM_ZIP="Nintendo - Game Boy.zip"
    typeset -gr GB_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/gb"

    typeset -gr GBC_BACKEND="ni"
    typeset -gr GBC_NI_SYSTEM_ZIP="Nintendo - Game Boy Color.zip"
    typeset -gr GBC_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/gbc"

    typeset -gr GBA_BACKEND="ni"
    typeset -gr GBA_NI_SYSTEM_ZIP="Nintendo - Game Boy Advance.zip"
    typeset -gr GBA_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/gba"

    typeset -gr TG16_BACKEND="ni"
    typeset -gr TG16_NI_SYSTEM_ZIP="NEC - PC Engine - TurboGrafx-16.zip"
    typeset -gr TG16_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/pcengine"

    typeset -gr SMS_BACKEND="ni"
    typeset -gr SMS_NI_SYSTEM_ZIP="Sega - Master System - Mark III.zip"
    typeset -gr SMS_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/mastersystem"

    typeset -gr GG_BACKEND="ni"
    typeset -gr GG_NI_SYSTEM_ZIP="Sega - Game Gear.zip"
    typeset -gr GG_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/gamegear"

    typeset -gr MD_BACKEND="ni"
    typeset -gr MD_NI_SYSTEM_ZIP="Sega - Mega Drive - Genesis.zip"
    typeset -gr MD_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/genesis"

    typeset -gr WS_BACKEND="ni"
    typeset -gr WS_NI_SYSTEM_ZIP="Bandai - WonderSwan.zip"
    typeset -gr WS_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/wonderswan"

    typeset -gr WSC_BACKEND="ni"
    typeset -gr WSC_NI_SYSTEM_ZIP="Bandai - WonderSwan Color.zip"
    typeset -gr WSC_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/wonderswancolor"

    typeset -gr PV1000_BACKEND="ni"
    typeset -gr PV1000_NI_SYSTEM_ZIP="Casio - PV-1000.zip"
    typeset -gr PV1000_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/pv1000"

    # ── Atari ──

    typeset -gr A2600_BACKEND="ni"
    typeset -gr A2600_NI_SYSTEM_ZIP="Atari - 2600.zip"
    typeset -gr A2600_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/atari2600"

    typeset -gr A5200_BACKEND="ni"
    typeset -gr A5200_NI_SYSTEM_ZIP="Atari - 5200.zip"
    typeset -gr A5200_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/atari5200"

    typeset -gr A7800_BACKEND="ni"
    typeset -gr A7800_NI_SYSTEM_ZIP="Atari - 7800 (A78).zip"
    typeset -gr A7800_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/atari7800"

    typeset -gr LYNX_BACKEND="ni"
    typeset -gr LYNX_NI_SYSTEM_ZIP="Atari - Lynx (LNX).zip"
    typeset -gr LYNX_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/atarilynx"

    # ── Sega (additional) ──

    typeset -gr SG1000_BACKEND="ni"
    typeset -gr SG1000_NI_SYSTEM_ZIP="Sega - SG-1000.zip"
    typeset -gr SG1000_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/sg-1000"

    # ── NEC (additional) ──

    typeset -gr SGX_BACKEND="ni"
    typeset -gr SGX_NI_SYSTEM_ZIP="NEC - PC Engine SuperGrafx.zip"
    typeset -gr SGX_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/supergrafx"

    # ── Other ──

    typeset -gr COLECO_BACKEND="ni"
    typeset -gr COLECO_NI_SYSTEM_ZIP="Coleco - ColecoVision.zip"
    typeset -gr COLECO_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/colecovision"

    typeset -gr VECTREX_BACKEND="ni"
    typeset -gr VECTREX_NI_SYSTEM_ZIP="GCE - Vectrex.zip"
    typeset -gr VECTREX_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/vectrex"

    typeset -gr ODYSSEY2_BACKEND="ni"
    typeset -gr ODYSSEY2_NI_SYSTEM_ZIP="Magnavox - Odyssey 2.zip"
    typeset -gr ODYSSEY2_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/odyssey2"

    typeset -gr CHANNELF_BACKEND="ni"
    typeset -gr CHANNELF_NI_SYSTEM_ZIP="Fairchild - Channel F.zip"
    typeset -gr CHANNELF_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/channelf"

    # ── Commodore ──

    typeset -gr C64_BACKEND="ni"
    typeset -gr C64_NI_SYSTEM_ZIP="Commodore - Commodore 64.zip"
    typeset -gr C64_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/c64"

    typeset -gr VIC20_BACKEND="ni"
    typeset -gr VIC20_NI_SYSTEM_ZIP="Commodore - VIC-20.zip"
    typeset -gr VIC20_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/vic20"

    typeset -gr C16_BACKEND="ni"
    typeset -gr C16_NI_SYSTEM_ZIP="Commodore - Plus-4.zip"
    typeset -gr C16_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/plus4"

    # ── Microsoft ──

    typeset -gr MSX_BACKEND="ni"
    typeset -gr MSX_NI_SYSTEM_ZIP="Microsoft - MSX.zip"
    typeset -gr MSX_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/msx"

    typeset -gr MSX2_BACKEND="ni"
    typeset -gr MSX2_NI_SYSTEM_ZIP="Microsoft - MSX2.zip"
    typeset -gr MSX2_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/msx2"

    # ── Atari (computer) ──

    typeset -gr ATARIST_BACKEND="ni"
    typeset -gr ATARIST_NI_SYSTEM_ZIP="Atari - ST.zip"
    typeset -gr ATARIST_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/atarist"

    typeset -gr ATARI800_BACKEND="ni"
    typeset -gr ATARI800_NI_SYSTEM_ZIP="Atari - 8-bit Family.zip"
    typeset -gr ATARI800_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/atari800"

    # ── Intellivision ──

    typeset -gr INTV_BACKEND="ni"
    typeset -gr INTV_NI_SYSTEM_ZIP="Mattel - Intellivision.zip"
    typeset -gr INTV_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/intellivision"

    # ── Additional consoles ──

    typeset -gr S32X_BACKEND="ni"
    typeset -gr S32X_NI_SYSTEM_ZIP="Sega - 32X.zip"
    typeset -gr S32X_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/sega32x"

    typeset -gr POKEMINI_BACKEND="ni"
    typeset -gr POKEMINI_NI_SYSTEM_ZIP="Nintendo - Pokemon Mini.zip"
    typeset -gr POKEMINI_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/pokemini"

    typeset -gr ASTROCADE_BACKEND="ni"
    typeset -gr ASTROCADE_NI_SYSTEM_ZIP="Bally - Astrocade.zip"
    typeset -gr ASTROCADE_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/astrocde"

    typeset -gr ARCADIA_BACKEND="ni"
    typeset -gr ARCADIA_NI_SYSTEM_ZIP="Emerson - Arcadia 2001.zip"
    typeset -gr ARCADIA_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/arcadia"

    typeset -gr GAMATE_BACKEND="ni"
    typeset -gr GAMATE_NI_SYSTEM_ZIP="Bit Corporation - Gamate.zip"
    typeset -gr GAMATE_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/gamate"

    typeset -gr MEGADUCK_BACKEND="ni"
    typeset -gr MEGADUCK_NI_SYSTEM_ZIP="Welback - Mega Duck.zip"
    typeset -gr MEGADUCK_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/megaduck"

    typeset -gr SCV_BACKEND="ni"
    typeset -gr SCV_NI_SYSTEM_ZIP="Epoch - Super Cassette Vision.zip"
    typeset -gr SCV_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/supercassettevision"

    typeset -gr ADVISION_BACKEND="ni"
    typeset -gr ADVISION_NI_SYSTEM_ZIP="Entex - Adventure Vision.zip"
    typeset -gr ADVISION_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/adventurevision"

    typeset -gr NGP_BACKEND="ni"
    typeset -gr NGP_NI_SYSTEM_ZIP="SNK - NeoGeo Pocket.zip"
    typeset -gr NGP_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/ngp"

    typeset -gr NGPC_BACKEND="ni"
    typeset -gr NGPC_NI_SYSTEM_ZIP="SNK - NeoGeo Pocket Color.zip"
    typeset -gr NGPC_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/ngpc"

    # ── Additional computers ──

    typeset -gr RX78_BACKEND="ni"
    typeset -gr RX78_NI_SYSTEM_ZIP="Bandai - Gundam RX-78.zip"
    typeset -gr RX78_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/rx78"

    # Neo Geo — DEFERRED: MiSTer core requires decrypted .neo files
    # ni-roms No-Intro sets are encrypted MAME format (incompatible)
    # typeset -gr NEOGEO_BACKEND="???"
    # typeset -gr NEOGEO_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/games/NEOGEO"

    # ── Internet Archive backend: CHD/disc sets ────────────────────────────────

    typeset -gr TG16CD_BACKEND="ia"
    typeset -gr TG16CD_IA_IDENTIFIER="chd_pcecd"
    typeset -gr TG16CD_FILES_XML="chd_pcecd_files.xml"
    typeset -gr TG16CD_META_XML="chd_pcecd_meta.xml"
    typeset -gr TG16CD_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/pcenginecd"

    typeset -gr MCD_BACKEND="ia"
    typeset -gr MCD_IA_IDENTIFIER="corpse-killer-usa-32-x-cd"
    typeset -gr MCD_FILES_XML="corpse-killer-usa-32-x-cd_files.xml"
    typeset -gr MCD_META_XML="corpse-killer-usa-32-x-cd_meta.xml"
    typeset -gr MCD_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/segacd"

    typeset -gr SS_BACKEND="ia"
    typeset -gr SS_IA_IDENTIFIER="chd_saturn"
    typeset -gr SS_FILES_XML="chd_saturn_files.xml"
    typeset -gr SS_META_XML="chd_saturn_meta.xml"
    typeset -gr SS_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/saturn"

    typeset -gr PSXUS_BACKEND="ia"
    typeset -gr PSXUS_IA_IDENTIFIER="chd_psx"
    typeset -gr PSXUS_FILES_XML="chd_psx_files.xml"
    typeset -gr PSXUS_META_XML="chd_psx_meta.xml"
    typeset -gr PSXUS_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/psx"

    typeset -gr PSXEU_BACKEND="ia"
    typeset -gr PSXEU_IA_IDENTIFIER="chd_psx_eur"
    typeset -gr PSXEU_FILES_XML="chd_psx_eur_files.xml"
    typeset -gr PSXEU_META_XML="chd_psx_eur_meta.xml"
    typeset -gr PSXEU_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/psx"

    typeset -gr PSXJP_BACKEND="ia"
    typeset -gr PSXJP_IA_IDENTIFIER="chd_psx_jap"
    typeset -gr PSXJP_FILES_XML="chd_psx_jap_files.xml"
    typeset -gr PSXJP_META_XML="chd_psx_jap_meta.xml"
    typeset -gr PSXJP_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/psx"

    typeset -gr PSXJP2_BACKEND="ia"
    typeset -gr PSXJP2_IA_IDENTIFIER="chd_psx_jap_p2"
    typeset -gr PSXJP2_FILES_XML="chd_psx_jap_p2_files.xml"
    typeset -gr PSXJP2_META_XML="chd_psx_jap_p2_meta.xml"
    typeset -gr PSXJP2_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/psx"

    typeset -gr PSXMISC_BACKEND="ia"
    typeset -gr PSXMISC_IA_IDENTIFIER="chd_psx_misc"
    typeset -gr PSXMISC_FILES_XML="chd_psx_misc_files.xml"
    typeset -gr PSXMISC_META_XML="chd_psx_misc_meta.xml"
    typeset -gr PSXMISC_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/psx"

    typeset -gr AO486_BACKEND="ia"
    typeset -gr AO486_IA_IDENTIFIER="0mhz-dos"
    typeset -gr AO486_FILES_XML="0mhz-dos_files.xml"
    typeset -gr AO486_META_XML="0mhz-dos_meta.xml"
    typeset -gr AO486_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}"

    typeset -gr CD32_BACKEND="ia"
    typeset -gr CD32_IA_IDENTIFIER="commodore-amiga-cd32-redump-collection"
    typeset -gr CD32_FILES_XML="commodore-amiga-cd32-redump-collection_files.xml"
    typeset -gr CD32_META_XML="commodore-amiga-cd32-redump-collection_meta.xml"
    typeset -gr CD32_GAMEDIR_DEFAULT="${RETRODECK_ROOT:-$HOME/retrodeck}/roms/amigacd32"
}

# ─── USER CONFIG ───────────────────────────────────────────────────────────────

set_conf_opts () {
    for (( i=1; i<${#SUPPORTED_CORES}; i+=2 )); do
        local core=${SUPPORTED_CORES[i]}
        typeset -g "${core}_GAMEDIR=${(P)${:-${core}_GAMEDIR}:-${(P)${:-${core}_GAMEDIR_DEFAULT}}}"
    done
    typeset -g JOY_MODE=${JOY_MODE:-false}
    # Decrypt credentials if encrypted versions are present
    if [[ -n ${IA_EMAIL_ENC:-} || -n ${IA_PASS_ENC:-} ]]; then
        local _key=$(_get_machine_key)
        [[ -n $IA_EMAIL_ENC ]] && IA_EMAIL=$(_cred_decrypt "$IA_EMAIL_ENC" "$_key")
        [[ -n $IA_PASS_ENC  ]] && IA_PASS=$(_cred_decrypt "$IA_PASS_ENC" "$_key")
        if [[ -z $IA_EMAIL && -n $IA_EMAIL_ENC ]]; then
            log_error "set_conf_opts: failed to decrypt IA_EMAIL — machine key may have changed"
        fi
    fi
    # Migration: if plaintext creds exist (pre-encryption settings.sh), encrypt and rewrite
    if [[ -n ${IA_EMAIL:-} && -z ${IA_EMAIL_ENC:-} ]]; then
        log_info "set_conf_opts: migrating plaintext credentials to encrypted"
        save_settings
    fi
    typeset -g IA_EMAIL=${IA_EMAIL:-""}
    typeset -g IA_PASS=${IA_PASS:-""}
    typeset -g REGION_PREF=${REGION_PREF:-"All"}
    typeset -g REGION_FILTER=${REGION_FILTER:-false}
    typeset -g SHOW_BETA=${SHOW_BETA:-true}
    typeset -g SHOW_PROTO=${SHOW_PROTO:-true}
    typeset -g SHOW_DEMO=${SHOW_DEMO:-true}
    typeset -g SHOW_UNLICENSED=${SHOW_UNLICENSED:-true}
}

get_config () {
    typeset -g TITLE=${RETRARR_VERSION}
    if [[ -f ${SETTINGS_SH} ]]; then
        source ${SETTINGS_SH} 2>/dev/null
    fi
    set_conf_opts
}

save_settings () {
    local -a lines
    local _key=$(_get_machine_key)
    local _email_enc="" _pass_enc=""
    [[ -n $IA_EMAIL ]] && _email_enc=$(_cred_encrypt "$IA_EMAIL" "$_key")
    [[ -n $IA_PASS  ]] && _pass_enc=$(_cred_encrypt "$IA_PASS" "$_key")
    lines=(
        "# Retro Retriever configuration"
        "# Generated by retrarr.sh — edit carefully or use the Settings menu"
        ""
        "# archive.org credentials (encrypted)"
        "IA_EMAIL_ENC=\"${_email_enc}\""
        "IA_PASS_ENC=\"${_pass_enc}\""
        ""
        "# Region preference (USA/Europe/Japan/World/All)"
        "REGION_PREF=\"${REGION_PREF}\""
        "REGION_FILTER=${REGION_FILTER}"
        ""
        "# Display options"
        "SHOW_BETA=${SHOW_BETA}"
        "SHOW_PROTO=${SHOW_PROTO}"
        "SHOW_DEMO=${SHOW_DEMO}"
        "SHOW_UNLICENSED=${SHOW_UNLICENSED}"
        "JOY_MODE=${JOY_MODE}"
        ""
        "# Game directories (uncomment and edit to override defaults)"
    )
    for (( i=1; i<${#SUPPORTED_CORES}; i+=2 )); do
        local core=${SUPPORTED_CORES[i]}
        local dir=${(P)${:-${core}_GAMEDIR}}
        local def=${(P)${:-${core}_GAMEDIR_DEFAULT}}
        if [[ $dir == $def ]]; then
            lines+=("#${core}_GAMEDIR=\"${dir}\"")
        else
            lines+=("${core}_GAMEDIR=\"${dir}\"")
        fi
    done
    print -l $lines > ${SETTINGS_SH}
    log_info "save_settings: wrote ${SETTINGS_SH}"
}

# ─── CORE SELECTION ────────────────────────────────────────────────────────────

select_core () {
    typeset -g CORE=${1}
    typeset -g CORE_BACKEND=${(P)${:-${CORE}_BACKEND}}
    typeset -g CORE_GAMEDIR=${(P)${:-${CORE}_GAMEDIR}}

    case $CORE_BACKEND in
        ni)
            typeset -g CORE_NI_SYSTEM_ZIP=${(P)${:-${CORE}_NI_SYSTEM_ZIP}}
            typeset -g CORE_FILES_XML="${NI_CACHE_DIR}/${CORE}_files.xml"
            ;;
        ia)
            typeset -g CORE_IA_IDENTIFIER=${(P)${:-${CORE}_IA_IDENTIFIER}}
            typeset -g CORE_FILES_XML="${WRK_DIR}/${(P)${:-${CORE}_FILES_XML}}"
            typeset -g CORE_META_XML="${WRK_DIR}/${(P)${:-${CORE}_META_XML}}"
            ;;
    esac
}

# ─── LOGGING ───────────────────────────────────────────────────────────────────
# log_error — always logged (fatal / breaking)
# log_warn  — always logged (recoverable problems)
# log_info  — default level (high-level flow: downloads, logins, cache hits)
# log_debug — verbose internals (URLs, sizes, checksums, variable dumps)

_log () {
    local level_num=$1 level_tag=$2 ; shift 2
    (( level_num > LOG_LEVEL )) && return 0
    print "[$(date '+%H:%M:%S')] [${level_tag}] $*" >> "$LOG_FILE"
}
log_error () { _log $LOG_ERROR ERROR "$@" }
log_warn  () { _log $LOG_WARN  WARN  "$@" }
log_info  () { _log $LOG_INFO  INFO  "$@" }
log_debug () { _log $LOG_DEBUG DEBUG "$@" }

log_init () {
    # Rotate if over 1 MB
    if [[ -f $LOG_FILE ]]; then
        local size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if (( size > LOG_MAX_BYTES )); then
            mv -f "$LOG_FILE" "${LOG_FILE}.old"
        fi
    fi
    local level_name
    case $LOG_LEVEL in
        $LOG_ERROR) level_name="error" ;;
        $LOG_WARN)  level_name="warn"  ;;
        $LOG_INFO)  level_name="info"  ;;
        $LOG_DEBUG) level_name="debug" ;;
    esac
    log_info "────────────────────────────────────────────────"
    log_info "Retrarr ${RETRARR_VERSION} starting — log_level=${level_name}"
}

# ─── CREDENTIAL ENCRYPTION ─────────────────────────────────────────────────────
# Encrypts IA_EMAIL / IA_PASS at rest in settings.sh using AES-256-CBC.
# Key is derived from the machine's primary MAC address (unique per MiSTer).

_get_machine_key () {
    local mac=""
    # Try eth0 first (wired), then any interface with a MAC
    for iface in eth0 wlan0; do
        [[ -f /sys/class/net/${iface}/address ]] && {
            mac=$(<"/sys/class/net/${iface}/address")
            break
        }
    done
    # Fallback: generate a persistent random key if no MAC available
    if [[ -z $mac || $mac == "00:00:00:00:00:00" ]]; then
        local keyfile="${WRK_DIR}/.machine_key"
        if [[ ! -f $keyfile ]]; then
            $OPENSSL rand -hex 32 > "$keyfile"
            chmod 600 "$keyfile"
            log_warn "_get_machine_key: no MAC found, generated random key"
        fi
        mac=$(<"$keyfile")
    fi
    # Hash the MAC to get a consistent key string
    print -n "$mac" | $OPENSSL dgst -sha256 -r | awk '{print $1}'
}

_cred_encrypt () {
    local plaintext=$1 key=$2
    print -n "$plaintext" | $OPENSSL enc -aes-256-cbc -pbkdf2 -a -A -pass "pass:${key}" 2>/dev/null
}

_cred_decrypt () {
    local ciphertext=$1 key=$2
    print -n "$ciphertext" | $OPENSSL enc -aes-256-cbc -pbkdf2 -a -A -d -pass "pass:${key}" 2>/dev/null
}

# ─── UTILITIES ─────────────────────────────────────────────────────────────────

humanise () { print $(${NUMFMT} --to=iec-i --suffix=B --format="%9.2f" ${1}) }

urlencode () {
    setopt localoptions extendedglob
    local input=(${(s::)1})
    local match mbegin mend
    print ${(j::)input/(#b)([^A-Za-z0-9_.!~*\-\/])/%${(l:2::0:)$(([##16]#match))}}
}

cleanup () {
    [[ -f $DIALOG_TEMPFILE ]] && rm -f $DIALOG_TEMPFILE
    [[ $(ls -A $CACHE_DIR 2>/dev/null) ]] && log_warn "cleanup: cache dir $CACHE_DIR not empty"
    exit 0
}

# ─── AUTH ──────────────────────────────────────────────────────────────────────

# Log in to archive.org with email/password, return cookie string
ia_login () {
    local email=$1 pass=$2
    local py="/tmp/retrarr_ia_login_$$.py"

    cat > "$py" << 'PYEOF'
import sys, os
try:
    from internetarchive import configure
    import configparser
    email = os.environ['IA_LOGIN_EMAIL']
    pwd   = os.environ['IA_LOGIN_PASS']
    config_file = configure(email, pwd)
    cfg = configparser.RawConfigParser()
    cfg.read(config_file)
    user = cfg['cookies']['logged-in-user'].split(';')[0].strip()
    sig  = cfg['cookies']['logged-in-sig'].split(';')[0].strip()
    print(f'logged-in-user={user}; logged-in-sig={sig}')
except Exception as e:
    sys.stderr.write(str(e) + '\n')
    sys.exit(1)
PYEOF

    local result
    result=$(IA_LOGIN_EMAIL="$email" IA_LOGIN_PASS="$pass" $PYTHON "$py" 2>/dev/null)
    rm -f "$py"
    print "$result"
}

bootstrap_deps () {
    # Check if internetarchive CLI is installed; if not, offer to install it
    [[ -n $IA ]] && return 0

    $DIALOG --title "First-Time Setup" --yesno \
        "The internetarchive CLI (ia) is not installed.\n\nRetrarr needs it to download ROMs from archive.org.\n\nInstall it now? This will run:\n\n  python3 -m ensurepip\n  pip3 install --upgrade pip\n  pip3 install internetarchive\n\n(Requires internet connection)" \
        16 65
    [[ $? -ne $DIALOG_OK ]] && { print -u2 "Cannot continue without internetarchive CLI." ; exit 1 }

    # Run install steps with progress feedback
    {
        print "XXX\n10\nBootstrapping pip...\nXXX"
        $PYTHON -m ensurepip 2>&1
        print "XXX\n40\nUpgrading pip...\nXXX"
        pip3 install --upgrade pip 2>&1
        print "XXX\n60\nInstalling internetarchive...\nXXX"
        pip3 install internetarchive 2>&1
        print "XXX\n100\nDone!\nXXX"
    } | $DIALOG --title "Installing Dependencies" --gauge "Starting..." 8 65 0

    # Verify it worked
    typeset -gr IA=$(which ia 2>/dev/null || print "")
    if [[ -z $IA ]]; then
        $DIALOG --title "Installation Failed" --msgbox \
            "Could not install internetarchive CLI.\n\nCheck your network connection and try:\n\n  python3 -m ensurepip\n  pip3 install --upgrade pip\n  pip3 install internetarchive" \
            12 65
        exit 1
    fi

    log_info "bootstrap_deps: internetarchive CLI installed successfully"
    $DIALOG --title "Setup Complete" --msgbox \
        "internetarchive CLI installed successfully.\n\nYou will now be prompted to configure your archive.org credentials." \
        8 65
}

check_ia () {
    # If we have stored credentials, use them
    if [[ -n $IA_EMAIL && -n $IA_PASS ]]; then
        return 0
    fi
    # Fall back to ia.ini if present
    if [[ -f ~/.config/internetarchive/ia.ini || \
          -f ~/.config/ia.ini || \
          -f ~/.ia ]]; then
        return 0
    fi
    # No credentials at all — prompt to configure
    $DIALOG --title "$TITLE" --yesno \
        "archive.org credentials are not configured.\n\nPress Yes to open Settings and configure them now." \
        8 60
    if [[ $? -eq $DIALOG_OK ]]; then
        settings_menu
    else
        cleanup
    fi
}

# Sets global IA_COOKIE from stored credentials or ia.ini fallback
init_ia_cookie () {
    # Try stored credentials first
    if [[ -n $IA_EMAIL && -n $IA_PASS ]]; then
        IA_COOKIE=$(ia_login "$IA_EMAIL" "$IA_PASS")
        if [[ -n $IA_COOKIE ]]; then
            log_info "init_ia_cookie: logged in as ${IA_EMAIL}"
            return 0
        fi
        log_warn "init_ia_cookie: stored credentials failed"
    fi

    # Fall back to ia.ini
    IA_COOKIE=$($PYTHON << 'PYEOF'
import configparser, os, sys
paths = [
    os.path.expanduser('~/.config/internetarchive/ia.ini'),
    os.path.expanduser('~/.config/ia.ini'),
    os.path.expanduser('~/.ia'),
]
cfg = configparser.RawConfigParser()
for p in paths:
    if os.path.exists(p):
        cfg.read(p)
        break
try:
    user = cfg['cookies']['logged-in-user'].split(';')[0].strip()
    sig  = cfg['cookies']['logged-in-sig'].split(';')[0].strip()
    print(f'logged-in-user={user}; logged-in-sig={sig}')
except Exception as e:
    sys.exit(1)
PYEOF
)
    log_debug "init_ia_cookie: ${IA_COOKIE[1,60]}..."
    if [[ -z $IA_COOKIE ]]; then
        $DIALOG --title "$TITLE" --yesno \
            "Could not log in to archive.org.\n\nPress Yes to open Settings and configure credentials." \
            8 60
        if [[ $? -eq $DIALOG_OK ]]; then
            settings_menu
        else
            cleanup
        fi
    fi
}

# Fetch ni-roms storage node from archive.org metadata API
# Sets NI_NODE (e.g. ia902803.us.archive.org) and NI_DIR (e.g. /17/items/ni-roms)
init_ni_roms_node () {
    log_info "init_ni_roms_node: fetching"
    local node_dir
    node_dir=$($CURL "${CURL_OPTS[@]}" -sL "$NI_META_URL" 2>/dev/null | $PYTHON -c "
import sys, json
raw = sys.stdin.read()
if not raw:
    sys.exit(1)
try:
    d = json.loads(raw, strict=False)
    print(d.get('d1',''))
    print(d.get('dir',''))
except Exception as e:
    print('', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)
    NI_NODE=${${(f)node_dir}[1]}
    NI_DIR=${${(f)node_dir}[2]}
    log_info "init_ni_roms_node: node=$NI_NODE dir=$NI_DIR"
    if [[ -z $NI_NODE || -z $NI_DIR ]]; then
        $DIALOG --title "$TITLE" --msgbox \
            "Could not reach archive.org or determine ni-roms storage node.\n\nCheck your network connection." \
            8 65
        cleanup
    fi
}

# ─── METADATA ──────────────────────────────────────────────────────────────────

# Download ni-roms_files.xml — one file covers all No-Intro systems
fetch_ni_metadata () {
    if [[ -f $NI_FILES_XML ]]; then
        log_info "fetch_ni_metadata: using cached $NI_FILES_XML"
        return 0
    fi
    log_info "fetch_ni_metadata: downloading ni-roms_files.xml"
    $IA download "$NI_IDENTIFIER" "ni-roms_files.xml" \
        --destdir="$WRK_DIR" --no-directories -q 2>/dev/null
    # Fallback to direct curl if ia fails
    if [[ ! -f $NI_FILES_XML ]]; then
        log_warn "fetch_ni_metadata: ia failed, trying curl fallback"
        $CURL "${CURL_OPTS[@]}" -sL \
            -H "Cookie: $IA_COOKIE" \
            "https://archive.org/download/${NI_IDENTIFIER}/ni-roms_files.xml" \
            -o "$NI_FILES_XML"
    fi
    log_debug "fetch_ni_metadata: exists=$([ -f $NI_FILES_XML ] && echo yes || echo NO)"
}

# Build per-system XML by scraping view_archive.php listing page
build_ni_system_xml () {
    local core=$1
    local system_zip=${(P)${:-${core}_NI_SYSTEM_ZIP}}
    local out="${NI_CACHE_DIR}/${core}_files.xml"

    [[ -f $out ]] && { log_info "build_ni_system_xml: $core cached" ; return 0 }
    log_info "build_ni_system_xml: $core ($system_zip)"

    local encoded_archive=$(urlencode "${NI_DIR}/roms/${system_zip}")
    local url="https://${NI_NODE}/view_archive.php?archive=${encoded_archive}"

    # Write Python parser to a temp file to avoid sys.argv/heredoc conflicts
    local py_tmp=$(mktemp /tmp/retrarr_XXXXXX.py)
    cat > "$py_tmp" << PYEOF
import sys, re, urllib.parse, html, os

out_path   = "${out}"
system_zip = "${system_zip}"
content    = sys.stdin.read()

href_re = re.compile(
    r'href="//archive\.org/download/ni-roms/roms/[^"]+/([^"]+\.(?:zip|7z|nes|sfc|smc|gb|gbc|gba|n64|z64|v64|md|gen|sms|gg|pce|ws|wsc|rom|bin|crt|d64|prg|t64|mx1|mx2|st|stx|a52|car|atr|xex|int|32x|min|sv|ngp|ngc|adf))"',
    re.IGNORECASE
)
size_re = re.compile(r'<td id="size">(\d+)')

hrefs = href_re.findall(content)
sizes = size_re.findall(content)

if not hrefs:
    print(f'ERROR:no entries found in {system_zip}', file=sys.stderr)
    sys.exit(1)

lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<files>']
for i, href in enumerate(hrefs):
    game = urllib.parse.unquote(href)
    game = html.unescape(game)
    size = sizes[i] if i < len(sizes) else '0'
    lines.append(f'  <file name="{html.escape(game)}">')
    lines.append(f'    <size>{size}</size>')
    lines.append(f'    <sha1></sha1>')
    lines.append(f'  </file>')

lines.append('</files>')
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w', encoding='utf-8') as fh:
    fh.write('\n'.join(lines))
print(f'OK:{len(hrefs)}')
PYEOF

    local result
    result=$($CURL "${CURL_OPTS[@]}" -sL \
        -H "Cookie: $IA_COOKIE" \
        "$url" 2>/dev/null | $PYTHON "$py_tmp" 2>>"$LOG_FILE")

    rm -f "$py_tmp"
    log_debug "build_ni_system_xml: $core result=$result"
}

# Download CHD set metadata XMLs via ia
fetch_ia_metadata () {
    local identifier=$1
    local files_xml=$2
    local meta_xml=$3

    log_info "fetch_ia_metadata: $identifier"
    if [[ ! -f ${WRK_DIR}/${files_xml} ]]; then
        log_info "fetch_ia_metadata: downloading $files_xml"
        $IA download "$identifier" "$files_xml" \
            --destdir="$WRK_DIR" --no-directories -q 2>/dev/null
        if [[ -f ${WRK_DIR}/${files_xml} ]]; then
            log_info "fetch_ia_metadata: $files_xml OK"
        else
            log_error "fetch_ia_metadata: $files_xml FAILED"
        fi
    else
        log_info "fetch_ia_metadata: $files_xml cached"
    fi
    if [[ ! -f ${WRK_DIR}/${meta_xml} ]]; then
        log_info "fetch_ia_metadata: downloading $meta_xml"
        $IA download "$identifier" "$meta_xml" \
            --destdir="$WRK_DIR" --no-directories -q 2>/dev/null
        if [[ -f ${WRK_DIR}/${meta_xml} ]]; then
            log_info "fetch_ia_metadata: $meta_xml OK"
        else
            log_error "fetch_ia_metadata: $meta_xml FAILED"
        fi
    else
        log_info "fetch_ia_metadata: $meta_xml cached"
    fi
}

# Main metadata fetch — called once at startup
fetch_metadata () {
    local -a ni_cached ia_cached
    ni_cached=($(print ${NI_CACHE_DIR}/*_files.xml(N)))
    ia_cached=($(print ${WRK_DIR}/chd_*(N) ${WRK_DIR}/0mhz*(N) ${WRK_DIR}/commodore*(N)))

    if [[ -f $NI_FILES_XML || -n $ni_cached || -n $ia_cached ]]; then
        $DIALOG --title "$TITLE" --defaultno \
            --yesno "Re-download all ROM catalog metadata?\n\n(Only needed if catalogs have been updated)" 7 62
        if [[ $? -eq $DIALOG_OK ]]; then
            rm -f $ni_cached $ia_cached "$NI_FILES_XML"
        fi
    fi

    # Single ni-roms_files.xml covers all No-Intro systems
    fetch_ni_metadata

    (for (( i=1; i<${#SUPPORTED_CORES}; i+=2 )); do
        local core=${SUPPORTED_CORES[i]}
        local name=${SUPPORTED_CORES[$(( i+1 ))]}
        local backend=${(P)${:-${core}_BACKEND}}

        printf "XXX\n%i\n\nBuilding ROM catalog\n%s of %s: %s\nXXX\n" \
            $(( 100 * i / ${#SUPPORTED_CORES} )) \
            $(( (i+1)/2 )) $(( ${#SUPPORTED_CORES}/2 )) "$name"

        select_core $core

        case $backend in
            ni)
                build_ni_system_xml $core
                ;;
            ia)
                local bare_files=${(P)${:-${core}_FILES_XML}}
                local bare_meta=${(P)${:-${core}_META_XML}}
                fetch_ia_metadata "$CORE_IA_IDENTIFIER" "$bare_files" "$bare_meta"
                ;;
        esac
    done) | $DIALOG --title "$TITLE" --gauge \
        "Building ROM catalog..." 10 $(( $MAXWIDTH / 2 )) 0

    [[ $? -ne $DIALOG_OK ]] && cleanup
}

# ─── ROM INFO ──────────────────────────────────────────────────────────────────

get_tag_filesize () {
    $XMLLINT "$CORE_FILES_XML" \
        --xpath "string(files/file[@name=\"${1}\"]/size)" 2>/dev/null
}

get_tag_sha1 () {
    $XMLLINT "$CORE_FILES_XML" \
        --xpath "string(files/file[@name=\"${1}\"]/sha1)" 2>/dev/null
}

get_rom_info () {
    local -a tags=($*)
    local rominfo="" totalsize=0 tag

    for tag in $tags; do
        local romsize=$(get_tag_filesize "$tag")
        romsize=${romsize:-0}
        [[ $romsize =~ ^[0-9]+$ ]] && totalsize=$(print "$totalsize + $romsize" | $BC)
        rominfo+="File: ${tag##*/}\n"
        [[ $romsize =~ ^[0-9]+$ ]] \
            && rominfo+="Size: $(humanise $romsize)\n\n" \
            || rominfo+="Size: ${romsize}\n\n"
    done
    rominfo+="\nTotal: $(humanise $totalsize)\n"
    print $rominfo
}

# ─── GAME DESTINATION ──────────────────────────────────────────────────────────

get_rom_gamedir () {
    setopt localoptions extendedglob
    local tag=$*
    local odir="${CORE_GAMEDIR}/"
    local match mbegin mend

    [[ $tag == *.7z || $CORE == "AO486" ]] && { print "$odir" ; return }

    tag=${${(Q)tag%.chd}##*/}

    if [[ $CORE == "MCD" || $CORE == "SS" ]]; then
        : ${tag/(#b)\((Europe|Japan|USA)\)}
        [[ -z $match ]] || odir+="${match}/"
    fi

    local base="${tag% (Disc [0-9AB])*}"
    (( $#base == $#tag )) && { print "${odir}${base}/" ; return }

    local tmpdata
    tmpdata=$($XMLLINT "$CORE_FILES_XML" \
        --xpath "files/file[sha1][contains(translate(\
@name,\"${(U)base}\",\"${(L)base}\"),\"${(L)base}\")]/@name" 2>/dev/null)
    local -a ntags=(${${${${${${(@f)tmpdata}#*\"}%\"*}##*/}:#^*.chd}//\&amp;/&})
    unset tmpdata

    local nbase
    nbase=$(find_basename "$tag" $ntags)
    [[ $? -eq 0 ]] && { print "${odir}${nbase}/" ; return }
    print $odir ; return 1
}

# ─── DOWNLOADS ─────────────────────────────────────────────────────────────────

# Download a No-Intro ROM via ni-roms view_archive.php zip streaming
ni_download_rom () {
    local tag=$1       # bare game filename e.g. "Contra III - The Alien Wars (USA).zip"
    local dest_dir=$2
    local filename=${tag##*/}
    local ofile="${CACHE_DIR}/${filename}"

    # Build view_archive.php URL
    # Pattern: https://<node>/view_archive.php?archive=<dir>/roms/<system>.zip&file=<game>.zip
    local archive_path="${NI_DIR}/roms/${CORE_NI_SYSTEM_ZIP}"
    local encoded_archive=$(urlencode "$archive_path")
    local encoded_file=$(urlencode "$filename")
    local referer="https://${NI_NODE}/view_archive.php?archive=${encoded_archive}"
    local url="${referer}&file=${encoded_file}"

    log_info "ni_download_rom: $filename"
    log_debug "ni_download_rom: url=$url"

    # Get expected file size from XML for progress polling
    local filesize=$(get_tag_filesize "$tag")

    if [[ -n $ARIA2C ]]; then
        # aria2c: multi-connection download with built-in progress
        log_debug "ni_download_rom: using aria2c"
        # aria2c with file-size polling for progress (view_archive.php has no Content-Length)
        log_debug "ni_download_rom: using aria2c"
        $ARIA2C --check-certificate=false \
            --header="Cookie: $IA_COOKIE" \
            --header="Referer: $referer" \
            --dir="$CACHE_DIR" --out="$filename" \
            --file-allocation=none \
            --console-log-level=warn \
            --download-result=hide \
            --auto-file-renaming=false \
            --allow-overwrite=true \
            --continue=true \
            -x4 -s4 -q \
            "$url" &
        local dl_pid=$!

        if [[ -n $filesize && $filesize -gt 0 ]]; then
            {
                while kill -0 $dl_pid 2>/dev/null; do
                    local current=0
                    [[ -f $ofile ]] && current=$(wc -c < "$ofile" 2>/dev/null || echo 0)
                    local pct=$(( current * 100 / filesize ))
                    [[ $pct -gt 100 ]] && pct=100
                    print "XXX\n${pct}\nDownloading: ${filename}\nXXX"
                    sleep 1
                done
                print "XXX\n100\nDownload complete!\nXXX"
            } | $DIALOG --title "Downloading: ${filename}" \
                  --gauge "Fetching from archive.org..." 8 72 0
        else
            $DIALOG --title "Downloading: ${filename}" \
                --infobox "Fetching from archive.org...\n\n${filename}" 7 72
            wait $dl_pid
        fi

        wait $dl_pid 2>/dev/null
    else
        # Fallback: curl with file-size polling
        log_debug "ni_download_rom: using curl"
        $CURL "${CURL_OPTS[@]}" -sL \
            -H "Cookie: $IA_COOKIE" \
            -H "Referer: $referer" \
            "$url" -o "$ofile" &
        local curl_pid=$!

        if [[ -n $filesize && $filesize -gt 0 ]]; then
            {
                while kill -0 $curl_pid 2>/dev/null; do
                    local current=0
                    [[ -f $ofile ]] && current=$(wc -c < "$ofile" 2>/dev/null || echo 0)
                    local pct=$(( current * 100 / filesize ))
                    [[ $pct -gt 100 ]] && pct=100
                    print "XXX\n${pct}\nDownloading: ${filename}\nXXX"
                    sleep 1
                done
                print "XXX\n100\nDownload complete!\nXXX"
            } | $DIALOG --title "Downloading: ${filename}" \
                  --gauge "Fetching from archive.org..." 8 72 0
        else
            $DIALOG --title "Downloading: ${filename}" \
                --infobox "Fetching from archive.org...\n\n${filename}" 7 72
            wait $curl_pid
        fi

        wait $curl_pid 2>/dev/null
    fi

    log_debug "ni_download_rom: size=$([ -f $ofile ] && wc -c < $ofile || echo 0)"

    # Sanity check — archive.org returns HTML error pages on auth failure
    if [[ ! -f $ofile || ! -s $ofile ]]; then
        $DIALOG --title "$TITLE" --msgbox \
            "Download failed for:\n${filename}\n\nCheck your archive.org credentials." \
            9 60
        return 1
    fi

    # Reject HTML error pages
    local magic=$(head -c 15 "$ofile" 2>/dev/null)
    if [[ $magic == *"<!DOCTYPE"* || $magic == *"<html"* ]]; then
        log_error "ni_download_rom: got HTML instead of file — auth or access issue"
        rm -f "$ofile"
        $DIALOG --title "$TITLE" --msgbox \
            "Download returned an error page for:\n${filename}\n\nYour session may have expired. Run 'ia configure' to refresh." \
            10 65
        return 1
    fi

    # SHA1 verification — look up from ni-roms_files.xml using full path
    # (per-system listing XML has no sha1, but ni-roms_files.xml has per-zip sha1)
    local full_path="roms/${CORE_NI_SYSTEM_ZIP}/${filename}"
    local metasum=$($XMLLINT "$NI_FILES_XML" \
        --xpath "string(files/file[@name=\"${full_path}\"]/sha1)" 2>/dev/null)
    if [[ -n $metasum ]]; then
        local filesum=$($SHA1SUM "$ofile" | awk '{print $1}')
        log_debug "ni_download_rom: sha1 expected=$metasum got=$filesum"
        if [[ $filesum != $metasum ]]; then
            $DIALOG --title "Checksum Error" --msgbox \
                "SHA1 mismatch for ${filename}!\n\nExpected: ${metasum}\nGot:      ${filesum}\n\nDeleting corrupt file." \
                10 72
            rm -f "$ofile"
            return 1
        fi
    fi

    # Extract to destination
    [[ -d $dest_dir ]] || mkdir -p "$dest_dir"
    if [[ $ofile == *.zip ]]; then
        $UNZIP -o -qq -d "$dest_dir" "$ofile" && rm -f "$ofile"
    elif [[ $ofile == *.7z ]]; then
        $SZR e "$ofile" -o"$dest_dir" -y && rm -f "$ofile"
    else
        mv "$ofile" "$dest_dir"
    fi

    log_info "ni_download_rom: complete -> $dest_dir"
    return 0
}

# Download a CHD/disc ROM via ia download
ia_download_rom () {
    local identifier=$1
    local tag=$2
    local dest_dir=$3
    local filename=${tag##*/}
    local ofile="${CACHE_DIR}/${filename}"

    log_info "ia_download_rom: $filename"
    log_debug "ia_download_rom: identifier=$identifier tag='$tag' ofile=$ofile"

    {
        $IA download "$identifier" "$tag" \
            --destdir="$CACHE_DIR" --no-directories 2>&1
    } | $PYTHON -c "
import sys, re, subprocess

dialog = '$DIALOG'
title = sys.argv[1] if len(sys.argv) > 1 else 'Downloading...'
maxw = '$MAXWIDTH'

proc = subprocess.Popen(
    [dialog, '--title', f'Downloading: {title}',
     '--gauge', 'Fetching from archive.org...', '8', maxw, '0'],
    stdin=subprocess.PIPE
)

# ia uses \r to rewrite progress lines in place — read char by char
buf = ''
while True:
    ch = sys.stdin.read(1)
    if not ch:
        break
    if ch == '\r' or ch == '\n':
        m = re.search(r'(\d+)%', buf)
        if m:
            pct = m.group(1)
            try:
                proc.stdin.write(f'XXX\n{pct}\nDownloading: {title}\nXXX\n'.encode())
                proc.stdin.flush()
            except BrokenPipeError:
                break
        buf = ''
    else:
        buf += ch

try:
    proc.stdin.write(b'XXX\n100\nDownload complete!\nXXX\n')
    proc.stdin.flush()
    proc.stdin.close()
except:
    pass
proc.wait()
" "$filename" 2>/dev/null

    # ia download creates subdirectories matching the tag path despite --no-directories
    # if not at top level, check the exact subdir the tag implies
    if [[ ! -f $ofile ]]; then
        local subdir_file="${CACHE_DIR}/${tag}"
        if [[ -f $subdir_file ]]; then
            log_debug "ia_download_rom: found at $subdir_file, moving to $ofile"
            mv "$subdir_file" "$ofile"
            # clean up any empty subdirs left behind (handles 1 or 2 levels deep)
            local subdir="${tag%/*}"
            while [[ $subdir != "." && $subdir != "/" ]]; do
                rmdir "${CACHE_DIR}/${subdir}" 2>/dev/null || break
                subdir="${subdir%/*}"
            done
        fi
    fi

    log_debug "ia_download_rom: exists=$([ -f $ofile ] && echo YES || echo NO)"

    if [[ ! -f $ofile ]]; then
        $DIALOG --title "$TITLE" --msgbox \
            "Download failed for:\n${tag##*/}\n\nCheck your archive.org credentials (run 'ia configure')." \
            9 65
        return 1
    fi

    # SHA1 verification
    local metasum=$(get_tag_sha1 "$tag")
    if [[ -n $metasum ]]; then
        local filesum=$($SHA1SUM "$ofile" | awk '{print $1}')
        log_debug "ia_download_rom: sha1 expected=$metasum got=$filesum"
        if [[ $filesum != $metasum ]]; then
            $DIALOG --title "Checksum Error" --msgbox \
                "SHA1 mismatch for ${tag##*/}!\n\nExpected: ${metasum}\nGot:      ${filesum}\n\nDeleting corrupt file." \
                10 72
            rm -f "$ofile"
            return 1
        fi
    fi

    [[ -d $dest_dir ]] || mkdir -p "$dest_dir"
    if [[ $ofile == *.7z || $CORE == "AO486" ]]; then
        $SZR e "$ofile" -o"$dest_dir" -y && rm -f "$ofile"
    elif [[ $ofile == *.zip ]]; then
        $UNZIP -o -qq -d "$dest_dir" "$ofile"
        if [[ $CORE == "AO486" ]]; then
            local mgl=$CORE_GAMEDIR/$($UNZIP -l "$ofile" | grep -o '_DOS Games/.*\.mgl$')
            disabled_ao486_append_setname "$mgl"
        fi
        rm -f "$ofile"
    else
        mv "$ofile" "$dest_dir"
    fi

    log_info "ia_download_rom: complete -> $dest_dir"
    return 0
}

# Download dispatcher
download_roms () {
    local -a tags=($*)
    local tag

    local rominfo="$(get_rom_info $tags)\nDownload selected game(s)?"
    $DIALOG --title "Selected ROM(s)" --clear --cr-wrap --colors \
        --yesno "$rominfo" $(( $MAXHEIGHT / 2 )) $MAXWIDTH 2>$DIALOG_TEMPFILE
    local retval=$?
    [[ $retval -eq $DIALOG_CANCEL ]] && return
    [[ $retval -ne $DIALOG_OK ]] && cleanup

    if [[ ! -d $CORE_GAMEDIR ]]; then
        $DIALOG --title "Warning" --yesno \
            "Directory \"$CORE_GAMEDIR\" doesn't exist.\n\nCreate it?" 8 70
        retval=$?
        [[ $retval -eq $DIALOG_CANCEL ]] && return
        [[ $retval -ne $DIALOG_OK ]] && cleanup
        mkdir -p "$CORE_GAMEDIR"
    fi

    local ok=0 fail=0
    for tag in $tags; do
        local dest
        log_debug "download_roms: tag='$tag' backend=$CORE_BACKEND"
        case $CORE_BACKEND in
            ni)  dest="$CORE_GAMEDIR" ;;
            ia)  dest=$(get_rom_gamedir "$tag") ;;
        esac
        log_debug "download_roms: dest='$dest'"
        [[ -n $dest && ! -d $dest ]] && mkdir -p "$dest"

        case $CORE_BACKEND in
            ni)
                if ni_download_rom "$tag" "$dest"; then
                    (( ++ok ))
                else
                    (( ++fail ))
                fi
                ;;
            ia)
                if ia_download_rom "$CORE_IA_IDENTIFIER" "$tag" "$dest"; then
                    (( ++ok ))
                else
                    (( ++fail ))
                fi
                ;;
        esac
    done

    local msg="${ok} download(s) complete"
    [[ $fail -gt 0 ]] && msg+=", ${fail} failed"
    $DIALOG --title "$TITLE" --cr-wrap --msgbox "${msg}\n\nPress OK to return." 8 40
    [[ $? -ne $DIALOG_OK ]] && cleanup
}

# ─── AO486 HELPERS (from ROMweasel) ───────────────────────────────────────────

disabled_ao486_append_setname () {
    local mgl="$*"
    local game=${mgl:t:r}
    local setname=$(xmllint <(sed -e 's/\&\([^\amp;]\)/\&amp;\1/g' $mgl) \
        --xpath "string(/mistergamedescription/file/@path)")
    setname="AO486 ${${${setname:t}%%.*}[1,26]}"
    xmllint <(sed -e 's/\&\([^\amp;]\)/\&amp;\1/g' $mgl) \
        --xpath "/mistergamedescription/setname" &>/dev/null
    (( $? == 0 )) && return
    local tmpf=$(mktemp)
    awk '/<\/mistergamedescription>/{print "  <setname same_dir=\"1\">'$setname'<\/setname>"}1' \
        $mgl > $tmpf
    cat $tmpf > $mgl ; rm $tmpf
    pushd ${RETRODECK_ROOT:-$HOME/retrodeck}/config
    cp -n AO486.CFG ${setname}.CFG
    noglob zmv -W -C AO486_*.cfg ${setname}_*.cfg 2>/dev/null
    popd
}

disabled_ao486_setnames_all () {
    local -a mgls=("${RETRODECK_ROOT:-$HOME/retrodeck}/_DOS Games"/*.mgl)
    log_info "disabled_ao486_setnames_all: ${#mgls} games found, processing"
    print "${#mgls} games found, processing.."
    local mgl
    for mgl in $mgls; do disabled_ao486_append_setname $mgl; done
    log_info "disabled_ao486_setnames_all: complete"
    print "Done!"
}

disabled_organise_chd_dir () {
    setopt localoptions extendedglob
    local gamedir="${*%/}"
    [[ -d $gamedir ]] || { log_error "disabled_organise_chd_dir: $gamedir is not a directory" ; print "ERROR: $gamedir is not a directory" ; return 1 }
    local -a tags=(${gamedir}/*.chd)
    local tag base nbase i
    for (( i=1; i <= $#tags; i++ )); do
        tag="${${(Q)tags[i]%.chd}##*/}"
        base="${tag% (Disc [0-9AB])*}"
        if (( $#base == $#tag )); then
            [[ -d "${gamedir}/${base}" ]] || mkdir "${gamedir}/${base}"
            mv "${tags[i]}" "${gamedir}/${base}"
            continue
        fi
        local -a ntags=(${(M)${${(@f)tags%.chd}##*/}:#${base}*})
        nbase=$(find_basename "$tag" $ntags)
        if [[ $? -eq 0 ]]; then
            [[ -d "${gamedir}/${nbase}" ]] || mkdir "${gamedir}/${nbase}"
            mv "${tags[i]}" "${gamedir}/${nbase}"
        fi
    done
}

find_basename () {
    setopt localoptions extendedglob
    local tag=${(Q)1##*/}
    local -a ntags=(${(Q)@[2,-1]##*/})
    local match mbegin mend ntag
    local base=${tag//(#b) \(Disc [0-9AB]\)(*)/}
    local suff="${match}"
    typeset -A discset=()
    for ntag in $ntags; do
        local nbase=${ntag//(#b)( \(Disc [0-9AB]\))(*)/}
        [[ ! $nbase = $base ]] && continue
        [[ -z ${match[2]} ]] && match[2]="0xDEADBEEF"
        discset[${base}]+=${:-${match[1]}":"${match[2]}$'\x00'}
    done
    local -a nsuff=(${(u)${(0)discset[$base]}##*:})
    (( $#nsuff == 1 )) && { print "${base}${suff}" ; return }
    local -a discs=(${${(0)discset[$base]}%%:*})
    (( $#discs == ${#${(@u)discs}} )) && { print "${base}" ; return }
    local dsets=$(( ${#discs} / ${#${(@u)discs}} ))
    (( $dsets == $#nsuff )) && { print "${base}${suff}" ; return }
    print ; return 1
}

# ─── GAME MENU ─────────────────────────────────────────────────────────────────

game_menu () {
    setopt localoptions extendedglob
    local -a all_tags selected_tags menu_tags menu_items subdirs submenu
    local -i itemwidth retval i
    local filter tmpdata st rominfo sub match mbegin mend n

    tmpdata=$($XMLLINT "$CORE_FILES_XML" \
        --xpath "files/file/@name" 2>/dev/null)
    all_tags=(${${${${${${(@f)tmpdata}#*\"}%\"*}:#^*.(7z|zip|chd)}//\&amp;/&}})
    unset tmpdata

    if [[ -z $all_tags ]]; then
        $DIALOG --title "$TITLE" --msgbox \
            "No games found for ${CORE}.\n\nTry re-fetching metadata from the main menu." \
            8 55
        return
    fi

    # Sort
    if [[ -n ${(M)all_tags:#*/*} ]]; then
        local -A tt
        for n in $all_tags; do tt[${n:t}]=${n:h}; done
        all_tags=()
        for n in ${(ok)tt}; do all_tags+=(${tt[$n]}/$n); done
        unset tt
    else
        all_tags=(${(o)all_tags})
    fi

    # Subdirectory filter — IA backend only (CHD sets have region subdirs)
    if [[ $CORE_BACKEND == "ia" ]]; then
        # Extract unique directory prefixes without using (#b) backreferences
        local -A _subdirs_seen
        local _tag _subdir
        for _tag in $all_tags; do
            _subdir=${_tag%%/*}
            [[ $_subdir != $_tag ]] && _subdirs_seen[$_subdir]=1
        done
        subdirs=(${(k)_subdirs_seen})
        unset _subdirs_seen _tag _subdir
        if (( $#subdirs != $#all_tags )) && (( $#subdirs > 1 )); then
            submenu=("ALL" "[[ All ]]")
            for sub in $subdirs; do submenu+=($sub $sub); done
            $DIALOG --clear --title "$TITLE" --no-tags \
                --menu "This repository has subdirectories. Browse which?" \
                0 0 0 $submenu 2>$DIALOG_TEMPFILE
            (( $? != $DIALOG_OK )) && return
            sub=$(<$DIALOG_TEMPFILE)
            if [[ $sub != "ALL" ]]; then
                all_tags=(${(M)all_tags:#${sub}*})
                sub="subdir: ${sub%/}, "
            else
                unset sub
            fi
        fi
    fi

    while true; do
        if [[ -z $selected_tags ]]; then
            [[ -n $filter ]] \
                && menu_tags=(${(M)all_tags:#(#i)*${filter}*}) \
                || menu_tags=($all_tags)
        fi

        itemwidth=$(( $MAXWIDTH - 14 ))
        menu_items=()
        for (( i=1; i<=${#menu_tags}; ++i )); do
            (( ${selected_tags[(Ie)${menu_tags[$i]}]} )) && st="On" || st="0"
            $JOY_MODE && unset st
            local display=${${menu_tags[$i]##*/}%.(7z|zip|chd)}
            menu_items+=(${menu_tags[$i]} ${display:0:$itemwidth} $st)
        done

        if [[ -z $menu_items ]]; then
            $DIALOG --msgbox "No games found with filter: $filter\n" 5 42
            [[ $? -ne $DIALOG_OK ]] && break
            unset filter ; continue
        fi

        if $JOY_MODE; then
            $DIALOG --clear --title "$TITLE" \
                --extra-button --extra-label "ROM info" \
                --no-tags --cancel-label "Back" --ok-label "Download" \
                --default-item "$selected_tags" \
                --menu "Choose game (${CORE}${sub:+, $sub}total: ${#menu_tags})" \
                $MAXHEIGHT $MAXWIDTH $#menu_tags $menu_items 2>$DIALOG_TEMPFILE
        else
            $DIALOG --clear --title "$TITLE" --separate-output \
                --extra-button --extra-label "ROM info" \
                --no-tags --cancel-label "Back" \
                --help-button --help-tags --help-label "Options" \
                --ok-label "Download" --default-item "${selected_tags[1]}" \
                --checklist "Choose game(s) (${CORE}${sub:+, $sub}total: $#menu_tags)" \
                $MAXHEIGHT $MAXWIDTH $#menu_tags $menu_items 2>$DIALOG_TEMPFILE
        fi

        retval=$?
        selected_tags=(${${(f)"$(<$DIALOG_TEMPFILE)"}//\&amp;/&})

        case $retval in
            $DIALOG_OK)
                [[ -z $selected_tags ]] && {
                    $DIALOG --title "$TITLE" --msgbox "No ROMs selected!" 0 0
                    continue
                }
                download_roms $selected_tags
                $JOY_MODE || unset selected_tags filter
                continue ;;
            $DIALOG_HELP)
                $DIALOG --title "Options" --clear --no-cancel \
                    --cancel-label "Back" \
                    --menu "" 10 50 3 \
                    "filter"    "Filter games..." \
                    "selall"    "Select all visible" \
                    "deselall"  "Deselect all" \
                    2>$DIALOG_TEMPFILE
                case $(<$DIALOG_TEMPFILE) in
                    filter)
                        $DIALOG --title "Filter" --clear --no-cancel \
                            --inputbox "Search keyword (case-insensitive), or clear to reset:" \
                            0 80 $filter 2>$DIALOG_TEMPFILE
                        [[ $? -ne $DIALOG_OK ]] && cleanup
                        filter="$(<$DIALOG_TEMPFILE)"
                        unset selected_tags ;;
                    selall)
                        selected_tags=($menu_tags) ;;
                    deselall)
                        unset selected_tags ;;
                esac
                continue ;;
            $DIALOG_EXTRA)
                [[ -z $selected_tags ]] && {
                    $DIALOG --title "$TITLE" --msgbox "No ROMs selected!" 0 0
                    continue
                }
                rominfo="$(get_rom_info $selected_tags)"
                $DIALOG --title "ROM Info" --clear --cr-wrap --colors \
                    --msgbox "$rominfo" $(( $MAXHEIGHT / 2 )) $MAXWIDTH
                [[ $? -ne $DIALOG_OK ]] && cleanup
                continue ;;
            $DIALOG_CANCEL) break ;;
            *) cleanup ;;
        esac
    done
}

# ─── SETTINGS MENU ─────────────────────────────────────────────────────────────

settings_ia () {
    local email pass confirm retval

    # Email
    $DIALOG --title "archive.org Credentials" --no-cancel \
        --inputbox "archive.org email address:" 8 60 "$IA_EMAIL" \
        2>$DIALOG_TEMPFILE
    retval=$?
    [[ $retval -ne $DIALOG_OK ]] && return
    email=$(<$DIALOG_TEMPFILE)
    [[ -z $email ]] && return

    # Password
    $DIALOG --title "archive.org Credentials" --no-cancel \
        --inputbox "archive.org password:" 8 60 \
        2>$DIALOG_TEMPFILE
    retval=$?
    [[ $retval -ne $DIALOG_OK ]] && return
    pass=$(<$DIALOG_TEMPFILE)
    [[ -z $pass ]] && return

    # Test login
    $DIALOG --title "archive.org Credentials" \
        --infobox "Testing credentials..." 4 40
    local cookie
    cookie=$(ia_login "$email" "$pass")

    if [[ -z $cookie ]]; then
        $DIALOG --title "Login Failed" --msgbox \
            "Could not log in to archive.org.\n\nCheck your email and password and try again." \
            8 55
        return
    fi

    # Success — save
    IA_EMAIL="$email"
    IA_PASS="$pass"
    IA_COOKIE="$cookie"
    save_settings
    $DIALOG --title "archive.org Credentials" --msgbox \
        "Logged in successfully as:\n\n  ${IA_EMAIL}" \
        8 55
}

settings_region () {
    local retval
    local -a menu
    menu=(
        "All"     "All regions (no filtering)"
        "USA"     "USA only"
        "Europe"  "Europe only"
        "Japan"   "Japan only"
        "World"   "World (multi-region releases)"
    )
    $DIALOG --title "Region Preference" \
        --default-item "$REGION_PREF" \
        --cancel-label "Back" \
        --menu "Default region preference:\n(Filtering is off by default — enable in Display options)" \
        14 55 5 $menu 2>$DIALOG_TEMPFILE
    retval=$?
    [[ $retval -ne $DIALOG_OK ]] && return
    REGION_PREF=$(<$DIALOG_TEMPFILE)
    save_settings
}

settings_display () {
    local retval
    local -a opts
    $SHOW_BETA       && opts+=(BETA        "on") || opts+=(BETA        "off")
    $SHOW_PROTO      && opts+=(PROTO       "on") || opts+=(PROTO       "off")
    $SHOW_DEMO       && opts+=(DEMO        "on") || opts+=(DEMO        "off")
    $SHOW_UNLICENSED && opts+=(UNLICENSED  "on") || opts+=(UNLICENSED  "off")
    $REGION_FILTER   && opts+=(REGION_FILT "on") || opts+=(REGION_FILT "off")
    $JOY_MODE        && opts+=(JOY_MODE    "on") || opts+=(JOY_MODE    "off")

    $DIALOG --title "Display Options" \
        --cancel-label "Back" \
        --checklist "Toggle display options:" \
        16 55 6 \
        "BETA"        "Show Beta releases"        ${opts[$(( ${opts[(i)BETA]}        + 1 ))]} \
        "PROTO"       "Show Prototype releases"   ${opts[$(( ${opts[(i)PROTO]}       + 1 ))]} \
        "DEMO"        "Show Demo releases"        ${opts[$(( ${opts[(i)DEMO]}        + 1 ))]} \
        "UNLICENSED"  "Show Unlicensed releases"  ${opts[$(( ${opts[(i)UNLICENSED]}  + 1 ))]} \
        "REGION_FILT" "Enable region filtering"   ${opts[$(( ${opts[(i)REGION_FILT]} + 1 ))]} \
        "JOY_MODE"    "Simple joystick mode"      ${opts[$(( ${opts[(i)JOY_MODE]}    + 1 ))]} \
        2>$DIALOG_TEMPFILE
    retval=$?
    [[ $retval -ne $DIALOG_OK ]] && return

    local selected=$(<$DIALOG_TEMPFILE)
    SHOW_BETA=$([[ $selected == *BETA*        ]] && print true || print false)
    SHOW_PROTO=$([[ $selected == *PROTO*      ]] && print true || print false)
    SHOW_DEMO=$([[ $selected == *DEMO*        ]] && print true || print false)
    SHOW_UNLICENSED=$([[ $selected == *UNLICENSED* ]] && print true || print false)
    REGION_FILTER=$([[ $selected == *REGION_FILT* ]] && print true || print false)
    JOY_MODE=$([[ $selected == *JOY_MODE*    ]] && print true || print false)
    save_settings
}

settings_dirs () {
    local retval core dir
    local -a groups
    groups=(Nintendo Atari NEC Sega Sony Other)

    local -A group_cores
    group_cores[Nintendo]="NES SNES N64 GB GBC GBA POKEMINI"
    group_cores[Atari]="A2600 A5200 A7800 LYNX ATARI800 ATARIST"
    group_cores[NEC]="TG16 TG16CD SGX"
    group_cores[Sega]="SMS GG SG1000 MD S32X MCD SS"
    group_cores[SNK]="NGP NGPC"
    group_cores[Sony]="PSXUS PSXEU PSXJP PSXJP2 PSXMISC"
    group_cores[Commodore]="C64 VIC20 C16"
    group_cores[Microsoft]="MSX MSX2"
    group_cores[Other]="INTV COLECO VECTREX ODYSSEY2 CHANNELF WS WSC PV1000 ASTROCADE ARCADIA ADVISION GAMATE MEGADUCK SCV RX78 AO486 CD32"

    while true; do
        $DIALOG --title "Game Directories" \
            --cancel-label "Back" \
            --menu "Select manufacturer group to configure:" \
            0 0 0 \
            "Nintendo"  "NES, SNES, N64, GB, GBC, GBA, Pokemon Mini" \
            "Atari"     "2600, 5200, 7800, Lynx, 800/XL/XE, ST"    \
            "NEC"       "TG-16, TG-CD, SuperGrafx"                  \
            "Sega"      "SMS, GG, SG-1000, MD, 32X, MegaCD, Saturn" \
            "SNK"       "Neo Geo Pocket, Neo Geo Pocket Color"      \
            "Sony"      "PlayStation (USA/EUR/JPN)"                  \
            "Commodore" "C64, VIC-20, C16/Plus-4"                   \
            "Microsoft" "MSX, MSX2"                                 \
            "Other"     "Intellivision, Coleco, Vectrex, more..."   \
            2>$DIALOG_TEMPFILE
        retval=$?
        [[ $retval -ne $DIALOG_OK ]] && break

        local group=$(<$DIALOG_TEMPFILE)
        local cores=(${=group_cores[$group]})

        for core in $cores; do
            local current=${(P)${:-${core}_GAMEDIR}}
            $DIALOG --title "${group} — ${core} Directory" \
                --cancel-label "Skip" \
                --inputbox "Game directory for ${core}:" \
                8 70 "$current" 2>$DIALOG_TEMPFILE
            [[ $? -ne $DIALOG_OK ]] && continue
            dir=$(<$DIALOG_TEMPFILE)
            [[ -n $dir ]] && typeset -g "${core}_GAMEDIR=${dir}"
        done
        save_settings
    done
}

settings_advanced () {
    local level_name
    case $LOG_LEVEL in
        $LOG_ERROR) level_name="error" ;;
        $LOG_WARN)  level_name="warn"  ;;
        $LOG_INFO)  level_name="info"  ;;
        $LOG_DEBUG) level_name="debug" ;;
    esac
    $DIALOG --title "Advanced" \
        --cancel-label "Back" \
        --menu "Advanced options:" \
        10 60 2 \
        "log"    "Log level: ${level_name} — tail -f retrarr.log" \
        "cache"  "Clear metadata cache" \
        2>$DIALOG_TEMPFILE
    [[ $? -ne $DIALOG_OK ]] && return

    case $(<$DIALOG_TEMPFILE) in
        log)
            $DIALOG --title "Logging" --msgbox \
                "Current log level: ${level_name}\nLog file: ${LOG_FILE}\n\nTo change log level, set RETRARR_LOG_LEVEL:\n\n  RETRARR_LOG_LEVEL=debug ${RETRODECK_ROOT:-$HOME/retrodeck}/Scripts/retrarr.sh\n  RETRARR_LOG_LEVEL=warn  ${RETRODECK_ROOT:-$HOME/retrodeck}/Scripts/retrarr.sh\n\nRETRARR_DEBUG=1 is shorthand for debug level.\n\nWatch live:\n\n  tail -f ${LOG_FILE}" \
                18 65
            ;;
        cache)
            $DIALOG --title "Clear Cache" --yesno \
                "Delete all cached metadata?\n\nThis will re-download index files on next launch.\nYour downloaded ROMs will not be affected." \
                9 60
            if [[ $? -eq $DIALOG_OK ]]; then
                rm -f ${WRK_DIR}/*.xml ${NI_CACHE_DIR}/*.xml
                $DIALOG --title "Clear Cache" --msgbox "Cache cleared." 5 30
            fi ;;
    esac
}

# ─── BIOS DOWNLOAD ────────────────────────────────────────────────────────────
# BIOS/firmware files required by various RetroArch cores.
# Source: archive.org/details/retroarch_bios
# Destination: ${RETRODECK_ROOT}/bios/

typeset -grA BIOS_FILES=(
    # PlayStation — Beetle PSX / PCSX ReARMed
    "scph5500.bin"      "PlayStation (JP)"
    "scph5501.bin"      "PlayStation (US)"
    "scph5502.bin"      "PlayStation (EU)"
    # Sega CD — Genesis Plus GX / PicoDrive
    "bios_CD_U.bin"     "Sega CD (US)"
    "bios_CD_E.bin"     "Sega CD (EU)"
    "bios_CD_J.bin"     "Sega CD (JP)"
    # Sega Saturn — Beetle Saturn / Yabause
    "sega_101.bin"      "Saturn (JP)"
    "mpr-17933.bin"     "Saturn (US/EU)"
    # PC Engine CD — Beetle PCE Fast
    "syscard3.pce"      "PC Engine CD / TurboGrafx-CD"
    # Atari Lynx — Handy / Beetle Lynx
    "lynxboot.img"      "Atari Lynx"
    # GBA — mGBA / Beetle GBA
    "gba_bios.bin"      "Game Boy Advance"
    # ColecoVision — blueMSX
    "colecovision.rom"  "ColecoVision"
    # Intellivision — FreeIntv
    "exec.bin"          "Intellivision (EXEC)"
    "grom.bin"          "Intellivision (GROM)"
)

typeset -gr BIOS_SOURCE_URL="https://archive.org/download/retroarch_bios"

# Map systems to their required BIOS files
typeset -grA BIOS_REQUIRED=(
    PSXUS     "scph5500.bin scph5501.bin scph5502.bin"
    PSXEU     "scph5500.bin scph5501.bin scph5502.bin"
    PSXJP     "scph5500.bin scph5501.bin scph5502.bin"
    PSXJP2    "scph5500.bin scph5501.bin scph5502.bin"
    PSXMISC   "scph5500.bin scph5501.bin scph5502.bin"
    MCD       "bios_CD_U.bin bios_CD_E.bin bios_CD_J.bin"
    SS        "sega_101.bin mpr-17933.bin"
    TG16CD    "syscard3.pce"
    LYNX      "lynxboot.img"
    GBA       "gba_bios.bin"
    COLECO    "colecovision.rom"
    INTV      "exec.bin grom.bin"
)

bios_download () {
    local bios_dir="${RETRODECK_ROOT}/bios"
    [[ -d $bios_dir ]] || mkdir -p "$bios_dir"

    # Build checklist of all BIOS files with installed status
    local -a menu_items=()
    local f desc status
    for f in ${(ko)BIOS_FILES}; do
        desc=${BIOS_FILES[$f]}
        if [[ -f "${bios_dir}/${f}" ]]; then
            status="[installed]"
        else
            status="[missing]"
        fi
        menu_items+=("$f" "${desc} ${status}" "off")
    done

    while true; do
        $DIALOG --title "BIOS / Firmware" \
            --cancel-label "Back" \
            --help-button --help-label "Download All Missing" \
            --separate-output --checklist \
            "Select BIOS files to download.\nDestination: ${bios_dir}\nSource: archive.org/details/retroarch_bios" \
            0 78 0 \
            $menu_items 2>$DIALOG_TEMPFILE

        local retval=$?
        case $retval in
            $DIALOG_CANCEL|$DIALOG_ESC) return ;;
            $DIALOG_HELP)
                # Download all missing
                local -a to_download=()
                for f in ${(ko)BIOS_FILES}; do
                    [[ ! -f "${bios_dir}/${f}" ]] && to_download+=("$f")
                done
                if [[ ${#to_download} -eq 0 ]]; then
                    $DIALOG --title "BIOS" --msgbox "All BIOS files are already installed." 6 50
                    return
                fi
                ;;
            $DIALOG_OK)
                local -a to_download=(${(f)"$(<$DIALOG_TEMPFILE)"})
                [[ ${#to_download} -eq 0 ]] && return
                ;;
            *) return ;;
        esac

        # Download selected files
        local -i ok=0 fail=0 total=${#to_download}
        local i=0
        for f in $to_download; do
            (( i++ ))
            desc=${BIOS_FILES[$f]}
            log_info "bios_download: $f ($desc)"

            printf "XXX\n%i\n\nDownloading BIOS: %s\n%s\nXXX\n" \
                $(( 100 * i / total )) "$f" "$desc"

            if $CURL "${CURL_OPTS[@]}" -sL "${BIOS_SOURCE_URL}/${f}" -o "${bios_dir}/${f}" 2>>"$LOG_FILE"; then
                if [[ -f "${bios_dir}/${f}" && -s "${bios_dir}/${f}" ]]; then
                    log_info "bios_download: $f OK"
                    (( ++ok ))
                else
                    log_error "bios_download: $f empty/missing after download"
                    rm -f "${bios_dir}/${f}"
                    (( ++fail ))
                fi
            else
                log_error "bios_download: $f FAILED"
                rm -f "${bios_dir}/${f}"
                (( ++fail ))
            fi
        done | $DIALOG --title "Downloading BIOS Files" --gauge \
            "Starting..." 8 60 0

        local msg="${ok} BIOS file(s) downloaded"
        [[ $fail -gt 0 ]] && msg+=", ${fail} failed"
        $DIALOG --title "BIOS Download" --msgbox "$msg" 6 45

        # Refresh menu items with updated status
        menu_items=()
        for f in ${(ko)BIOS_FILES}; do
            desc=${BIOS_FILES[$f]}
            [[ -f "${bios_dir}/${f}" ]] && status="[installed]" || status="[missing]"
            menu_items+=("$f" "${desc} ${status}" "off")
        done
    done
}

settings_menu () {
    local retval
    while true; do
        local ia_status
        [[ -n $IA_EMAIL ]] && ia_status="($IA_EMAIL)" || ia_status="(not configured)"

        $DIALOG --title "Settings" \
            --cancel-label "Back" \
            --menu "Configure Retrarr:" \
            15 65 6 \
            "ia"       "archive.org credentials ${ia_status}" \
            "bios"     "BIOS / Firmware files" \
            "region"   "Region preference (current: ${REGION_PREF})" \
            "display"  "Display options" \
            "dirs"     "Game directories" \
            "advanced" "Advanced" \
            2>$DIALOG_TEMPFILE
        retval=$?
        [[ $retval -ne $DIALOG_OK ]] && break

        case $(<$DIALOG_TEMPFILE) in
            ia)       settings_ia ;;
            bios)     bios_download ;;
            region)   settings_region ;;
            display)  settings_display ;;
            dirs)     settings_dirs ;;
            advanced) settings_advanced ;;
        esac
    done
}

# ─── ZAPAROO MODE ──────────────────────────────────────────────────────────────
# Called via: retrarr.sh --zaparoo CORE "game search term"
# Downloads a specific game headlessly (with progress gauge), skips all menus.
# Exits 0 on success (game ready to play), 1 on error.

zaparoo_mode () {
    setopt localoptions nowarnnestedvar
    local zap_core=$1
    local zap_search=$2

    log_info "zaparoo_mode: core=$zap_core search='$zap_search'"

    # Validate core exists in SUPPORTED_CORES
    local valid=false
    local -i zi
    for (( zi=1; zi<${#SUPPORTED_CORES}; zi+=2 )); do
        [[ ${SUPPORTED_CORES[zi]} == $zap_core ]] && { valid=true ; break }
    done
    if ! $valid; then
        log_error "zaparoo_mode: unknown core '$zap_core'"
        print -u2 "ERROR: Unknown core '$zap_core'"
        return 1
    fi

    # Must have credentials already configured — no interactive prompts
    if [[ -z $IA_EMAIL && -z $IA_PASS ]]; then
        if [[ ! -f ~/.config/internetarchive/ia.ini && \
              ! -f ~/.config/ia.ini && \
              ! -f ~/.ia ]]; then
            log_error "zaparoo_mode: no archive.org credentials configured"
            print -u2 "ERROR: archive.org credentials not configured. Run retrarr.sh first to set up."
            return 1
        fi
    fi
    if [[ -z $IA ]]; then
        log_error "zaparoo_mode: internetarchive CLI not installed"
        print -u2 "ERROR: internetarchive CLI not installed. Run retrarr.sh first to set up."
        return 1
    fi

    # Auth — declare globals that init functions will set
    typeset -g IA_COOKIE NI_NODE NI_DIR
    init_ia_cookie
    if [[ -z $IA_COOKIE ]]; then
        log_error "zaparoo_mode: failed to authenticate with archive.org"
        print -u2 "ERROR: Failed to authenticate with archive.org"
        return 1
    fi
    init_ni_roms_node

    # Set up core
    select_core $zap_core

    # Build metadata for this core only (no dialog gauge)
    case $CORE_BACKEND in
        ni)
            fetch_ni_metadata
            build_ni_system_xml $zap_core
            ;;
        ia)
            local bare_files=${(P)${:-${zap_core}_FILES_XML}}
            local bare_meta=${(P)${:-${zap_core}_META_XML}}
            fetch_ia_metadata "$CORE_IA_IDENTIFIER" "$bare_files" "$bare_meta"
            ;;
    esac

    # Search for matching game in XML
    local tmpdata
    tmpdata=$($XMLLINT "$CORE_FILES_XML" \
        --xpath "files/file/@name" 2>/dev/null)
    local -a all_tags=(${${${${${${(@f)tmpdata}#*\"}%\"*}:#^*.(7z|zip|chd)}//\&amp;/&}})
    unset tmpdata

    if [[ -z $all_tags ]]; then
        log_error "zaparoo_mode: no games found in metadata for $zap_core"
        print -u2 "ERROR: No games found in metadata for $zap_core"
        return 1
    fi

    # Find matching tag (case-insensitive substring match)
    # If search already has wildcards, use as-is; otherwise wrap with *
    local zap_pattern=$zap_search
    [[ $zap_pattern != *[\*\?]* ]] && zap_pattern="*${zap_pattern}*"
    local -a matches=(${(M)all_tags:#(#i)${~zap_pattern}})

    if [[ ${#matches} -eq 0 ]]; then
        log_error "zaparoo_mode: no match for '$zap_search' in $zap_core"
        print -u2 "ERROR: No match for '$zap_search' in $zap_core"
        return 1
    fi

    local tag filename

    if (( ${#matches} == 1 )); then
        tag=${matches[1]}
        filename=${tag##*/}
        log_info "zaparoo_mode: single match '$filename'"
    else
        # Multiple matches — show selection menu
        log_info "zaparoo_mode: ${#matches} matches for '$zap_search', showing picker"
        local -a menu_items=()
        local m
        for m in ${(o)matches}; do
            menu_items+=("$m" "${m##*/}")
        done
        $DIALOG --title "Multiple Matches" \
            --menu "${#matches} games match '${zap_search}'.\nSelect one:" \
            0 0 0 $menu_items 2>$DIALOG_TEMPFILE
        if [[ $? -ne $DIALOG_OK ]]; then
            log_info "zaparoo_mode: user cancelled selection"
            return 1
        fi
        tag=$(<$DIALOG_TEMPFILE)
        filename=${tag##*/}
        log_info "zaparoo_mode: user selected '$filename'"
    fi

    # Check if game already exists in game directory
    local dest_dir="$CORE_GAMEDIR"
    [[ $CORE_BACKEND == "ia" ]] && dest_dir=$(get_rom_gamedir "$tag")

    local check_name=${${filename%.zip}%.7z}
    check_name=${check_name%.chd}

    # Look for extracted file or CHD in destination
    local -a existing=(${dest_dir}/${check_name}*(N))
    if [[ -n $existing ]]; then
        log_info "zaparoo_mode: '$check_name' already exists in $dest_dir"
        print "${existing[1]}"
        return 0
    fi

    # Download with progress gauge
    [[ -d $dest_dir ]] || mkdir -p "$dest_dir"

    local dl_ok=false
    case $CORE_BACKEND in
        ni)
            ni_download_rom "$tag" "$dest_dir" && dl_ok=true
            ;;
        ia)
            ia_download_rom "$CORE_IA_IDENTIFIER" "$tag" "$dest_dir" && dl_ok=true
            ;;
    esac

    if ! $dl_ok; then
        log_error "zaparoo_mode: download failed for '$filename'"
        print -u2 "ERROR: Download failed for '$filename'"
        return 1
    fi

    # Output final game path for caller (e.g. Zaparoo) to launch
    local -a installed=(${dest_dir}/${check_name}*(N))
    if [[ -n $installed ]]; then
        print "${installed[1]}"
    else
        print "${dest_dir}/${check_name}"
    fi
    log_info "zaparoo_mode: complete — '$filename' ready in $dest_dir"
    return 0
}

# ─── MAIN ──────────────────────────────────────────────────────────────────────

main () {
    local -i retval
    local jm t d

    init_static_globals

    [[ -d $WRK_DIR      ]] || mkdir -p "$WRK_DIR"
    [[ -d $CACHE_DIR    ]] || mkdir -p "$CACHE_DIR"
    [[ -d $NI_CACHE_DIR ]] || mkdir -p "$NI_CACHE_DIR"

    pushd $WRK_DIR
    trap 'cleanup' $SIG_HUP $SIG_INT $SIG_QUIT $SIG_TERM

    get_config

    log_init
    log_info "IA=$([ -n \"$IA\" ] && echo available || echo missing)"
    log_info "ARIA2C=$([ -n \"$ARIA2C\" ] && echo available || echo missing)"

    # CLI modes
    [[ $* == "${RETRODECK_ROOT:-$HOME/retrodeck}/_DOS Games" ]] && { disabled_ao486_setnames_all ; return }
    [[ -n $* && -d $* ]] && { disabled_organise_chd_dir $* ; return }
    if [[ $1 == "--zaparoo" ]]; then
        [[ -z $2 || -z $3 ]] && { print -u2 "Usage: retrarr.sh --zaparoo CORE \"game name\"" ; return 1 }
        zaparoo_mode "$2" "$3"
        return $?
    fi

    bootstrap_deps
    check_ia
    init_ia_cookie
    init_ni_roms_node

    log_info "NI_NODE=$NI_NODE NI_DIR=$NI_DIR"

    fetch_metadata

    while true; do
        $JOY_MODE && jm=" (Simple Mode)" || unset jm
        typeset -g TITLE="${RETRARR_VERSION}${jm}"

        # ── Top-level: Console / Computer ──
        $DIALOG --title "$TITLE" --cancel-label "Quit" \
            --help-button --help-label "Settings" \
            --menu "Choose a category:" 0 50 0 \
            "Consoles"  "Cartridge & disc-based systems (${$(( ${#CONSOLE_CORES} / 2 ))} systems)" \
            "Computers" "Home computers & DOS (${$(( ${#COMPUTER_CORES} / 2 ))} systems)" \
            2>$DIALOG_TEMPFILE

        retval=$?
        case $retval in
            $DIALOG_HELP) settings_menu ; continue ;;
            $DIALOG_OK)   ;;
            *)            break ;;
        esac

        local category=$(<$DIALOG_TEMPFILE)
        local -a core_list
        case $category in
            Consoles)  core_list=( $CONSOLE_CORES )  ;;
            Computers) core_list=( $COMPUTER_CORES ) ;;
        esac

        # ── Second level: system picker ──
        while true; do
            local default_item=${CORE:-0}

            $DIALOG --title "$TITLE — $category" --cancel-label "Back" \
                --extra-button --extra-label "Info" \
                --default-item "$default_item" \
                --menu "Choose target system / repository:" 0 80 0 \
                $core_list 2>$DIALOG_TEMPFILE

            retval=$?
            case $retval in
                $DIALOG_OK)
                    select_core $(<$DIALOG_TEMPFILE)
                    game_menu ;;
                $DIALOG_EXTRA)
                    select_core $(<$DIALOG_TEMPFILE)
                    case $CORE_BACKEND in
                        ni)
                            $DIALOG --title "Repository Info" --msgbox \
"Core:    $CORE
Backend: Internet Archive (ni-roms)
System:  $CORE_NI_SYSTEM_ZIP
Node:    $NI_NODE" 9 72 ;;
                        ia)
                            t=$($XMLLINT "$CORE_META_XML" \
                                --xpath "string(metadata/title)" 2>/dev/null)
                            d=$($XMLLINT "$CORE_META_XML" \
                                --xpath "string(metadata/addeddate)" 2>/dev/null)
                            $DIALOG --title "Repository Info" --msgbox \
"Core:    $CORE
Backend: Internet Archive (ia download)
ID:      $CORE_IA_IDENTIFIER
Title:   $t
Added:   $d" 11 72 ;;
                    esac
                    unset t d ;;
                *)
                    break ;;
            esac
        done
    done

    cleanup
}

main "$@"
