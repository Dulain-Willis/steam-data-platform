#!/bin/bash
# setup.sh — Clone all Steam Data Platform repos into the current directory's parent.
# Run this from inside steam-data-platform/ after cloning it.

set -e

PARENT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS=(
  "steam-infra"
  "steam-pipelines"
  "steam-orchestration"
  "steam-analytics"
)

echo "Cloning sibling repos into $PARENT ..."

for REPO in "${REPOS[@]}"; do
  TARGET="$PARENT/$REPO"
  if [ -d "$TARGET" ]; then
    echo "  $REPO already exists, skipping"
  else
    # Replace the URL below with the actual GitHub remote for each repo
    git clone "https://github.com/Dulain-Willis/$REPO.git" "$TARGET"
    echo "  Cloned $REPO"
  fi
done

echo ""
echo "Done. To start the full stack:"
echo "  cd $PARENT/steam-data-platform"
echo "  docker compose up -d"
