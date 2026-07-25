#!/bin/bash
# Regenerate db/retrarr.json with current hash, size, and timestamp.
# Run this before pushing a new release.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RETRARR="$REPO_ROOT/retrarr.sh"
ARIA2_BIN="$REPO_ROOT/bin/aria2c-mister"
DB_OUT="$SCRIPT_DIR/retrarr.json"

if [[ ! -f "$RETRARR" ]]; then
    echo "ERROR: retrarr.sh not found at $RETRARR"
    exit 1
fi

HASH=$(md5sum "$RETRARR" | awk '{print $1}')
SIZE=$(wc -c < "$RETRARR" | tr -d ' ')
TIMESTAMP=$(date +%s)

GITHUB_USER="whill121980"
REPO_NAME="retrarr"
BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")

# Custom DBs are barred from writing to /media/fat/linux/ (Downloader_MiSTer
# reserves that root folder for the official Distribution_MiSTer DB). Ship
# aria2c under Scripts/.retrarr/ instead — the script knows to look there.
ARIA2_ENTRY=""
ARIA2_FOLDER=""
if [[ -f "$ARIA2_BIN" ]]; then
    ARIA2_HASH=$(md5sum "$ARIA2_BIN" | awk '{print $1}')
    ARIA2_SIZE=$(wc -c < "$ARIA2_BIN" | tr -d ' ')
    ARIA2_ENTRY=",
    \"Scripts/.retrarr/aria2c\": {
      \"hash\": \"${ARIA2_HASH}\",
      \"size\": ${ARIA2_SIZE},
      \"url\": \"https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/bin/aria2c-mister\"
    }"
    ARIA2_FOLDER=",
    \"Scripts/.retrarr\": {}"
fi

cat > "$DB_OUT" << EOF
{
  "db_id": "retrarr",
  "timestamp": ${TIMESTAMP},
  "files": {
    "Scripts/retrarr.sh": {
      "hash": "${HASH}",
      "size": ${SIZE},
      "url": "https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/retrarr.sh"
    }${ARIA2_ENTRY}
  },
  "folders": {
    "Scripts": {}${ARIA2_FOLDER}
  }
}
EOF

echo "Updated $DB_OUT"
echo "  retrarr.sh hash:  $HASH"
echo "  retrarr.sh size:  $SIZE"
if [[ -n "$ARIA2_ENTRY" ]]; then
    echo "  aria2c hash:      $ARIA2_HASH"
    echo "  aria2c size:      $ARIA2_SIZE"
    echo "  aria2c install:   Scripts/.retrarr/aria2c"
else
    echo "  aria2c binary:    NOT bundled (drop at bin/aria2c-mister to include)"
fi
echo "  timestamp:        $TIMESTAMP"
