#!/bin/bash
# Regenerate db/retrarr.json with current hash, size, and timestamp.
# URLs are pinned to the current git branch — run this after switching
# branches or before pushing.

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

GITHUB_USER="whill121980"
REPO_NAME="retrarr"

# --show-current (git 2.22+) is unambiguous even when a tag shares the
# branch name. Fallback to master keeps CI/detached-HEAD builds sane.
BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null)
[[ -z "$BRANCH" ]] && BRANCH="master"

cat > "$DB_OUT" << EOF
{
  "db_id": "retrarr",
  "timestamp": ${TIMESTAMP},
  "files": {
    "Scripts/retrarr.sh": {
      "hash": "${HASH}",
      "size": ${SIZE},
      "url": "https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/retrarr.sh"
    }
  },
  "folders": {
    "Scripts": {}
  }
}
EOF

echo "Updated $DB_OUT"
echo "  branch:    $BRANCH"
echo "  hash:      $HASH"
echo "  size:      $SIZE"
echo "  timestamp: $TIMESTAMP"
