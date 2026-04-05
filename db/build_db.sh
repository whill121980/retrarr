#!/bin/bash
# Regenerate db/retrarr.json with current hash, size, and timestamp.
# Run this before pushing a new release.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RETRARR="$REPO_ROOT/retrarr.sh"
DB_OUT="$SCRIPT_DIR/retrarr.json"

if [[ ! -f "$RETRARR" ]]; then
    echo "ERROR: retrarr.sh not found at $RETRARR"
    exit 1
fi

HASH=$(md5sum "$RETRARR" | awk '{print $1}')
SIZE=$(wc -c < "$RETRARR" | tr -d ' ')
TIMESTAMP=$(date +%s)

# TODO: Update GitHub username/org when repo is created
GITHUB_USER="whill121980"
REPO_NAME="retrarr"

cat > "$DB_OUT" << EOF
{
  "db_id": "retrarr",
  "timestamp": ${TIMESTAMP},
  "files": {
    "Scripts/retrarr.sh": {
      "hash": "${HASH}",
      "size": ${SIZE},
      "url": "https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/master/retrarr.sh"
    }
  },
  "folders": {
    "Scripts": {}
  }
}
EOF

echo "Updated $DB_OUT"
echo "  hash:      $HASH"
echo "  size:      $SIZE"
echo "  timestamp: $TIMESTAMP"
