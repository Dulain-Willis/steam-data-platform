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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    cp "$SCRIPT_DIR/.env.example" "$ENV_FILE"
    echo "Created .env from .env.example"
fi

if grep -q '^AIRFLOW_FERNET_KEY=$' "$ENV_FILE"; then
    FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
    sed -i "s|^AIRFLOW_FERNET_KEY=.*|AIRFLOW_FERNET_KEY=${FERNET_KEY}|" "$ENV_FILE"
    echo "Generated Airflow Fernet key"
fi

if grep -q '^AIRFLOW_SECRET_KEY=$' "$ENV_FILE"; then
    SECRET_KEY=$(openssl rand -hex 32)
    sed -i "s|^AIRFLOW_SECRET_KEY=.*|AIRFLOW_SECRET_KEY=${SECRET_KEY}|" "$ENV_FILE"
    echo "Generated Airflow secret key"
fi

echo ""
echo "Done. To start the full stack:"
echo "  cd $PARENT/steam-data-platform"
echo "  docker compose up -d"
