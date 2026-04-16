#!/usr/bin/env bash
# PDFloki Site – Server Deploy Script

set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-$HOME/pdfloki}"

cd "$DEPLOY_DIR"

echo "Pulling latest changes..."
git pull origin main

echo "Rebuilding and restarting containers..."
docker compose down
docker compose up -d --build

echo ""
echo "Site is live at pdfloki.app"
