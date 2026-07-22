#!/usr/bin/env bash

set -euo pipefail

# ───────────────────────────────────────────────────────────────
# Deployment script for Recall (CI/CD)
# Invoked by GitHub Actions over SSH
# ───────────────────────────────────────────────────────────────

# Configuration
APP_DIR="/var/www/my-app"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
DEPLOY_BRANCH="${1:-main}"

echo ""
echo "=========================================="
echo "  DEPLOYMENT START"
echo "=========================================="
echo "Branch: $DEPLOY_BRANCH"
echo "Working dir: $APP_DIR"

# Safely enter the app directory
if [ ! -d "$APP_DIR" ]; then
  echo "ERROR: $APP_DIR does not exist" >&2
  exit 1
fi

cd "$APP_DIR"

# ------------- Step 0: Stop existing Recall containers -----------
echo ""
echo "▶ Stopping existing Recall containers (my-app-frontend-1, my-app-backend-1)..."
if docker ps --format "{{.Names}}" | grep -qE "my-app-frontend-1|my-app-backend-1"; then
  docker stop my-app-frontend-1 my-app-backend-1 2>/dev/null || true
  docker rm my-app-frontend-1 my-app-backend-1 2>/dev/null || true
  echo "✓ Old containers stopped"
else
  echo "ℹ No old containers to stop"
fi

# ------------- Step 1: Pull latest deployment repo --------------
echo ""
echo "▶ Pulling latest deployment repository..."
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "ERROR: git remote 'origin' not configured" >&2
  exit 1
fi

# Ensure safe.directory for git
if git rev-parse --git-dir > /dev/null 2>&1; then
  git config --global --add safe.directory "$APP_DIR" || true
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [ "$CURRENT_BRANCH" != "$DEPLOY_BRANCH" ]; then
  echo "Switching to branch $DEPLOY_BRANCH..."
  if ! git checkout "$DEPLOY_BRANCH"; then
    echo "ERROR: Could not checkout branch $DEPLOY_BRANCH" >&2
    exit 1
  fi
fi
echo "Checking out branch: $CURRENT_BRANCH"

# Pull latest changes
if ! git pull --ff-only origin "$DEPLOY_BRANCH"; then
  echo "ERROR: Git pull failed" >&2
  exit 1
fi
echo "✓ Deployment repo updated"

# ------------- Step 2: Update submodules (recall-api + recall-web) -------
echo ""
echo "▶ Updating submodules..."
git submodule sync --recursive

# Try git submodule update; if fails, try using token from env if provided
if GIT_TOKEN="${GIT_TOKEN:-}" \
   git submodule update --init --recursive --force 2>/dev/null; then
  echo "✓ Submodules updated (no token needed)"
else
  echo "⚠ Standard submodule update failed, attempting with token..."
  # If you set GIT_TOKEN in env variables, you can use $GIT_TOKEN here.
  echo "Consider setting GIT_TOKEN in the workflow if submodules need auth"
fi

# ------------- Step 3: Build and start services -----------------------
echo ""
echo "▶ Building and starting containers..."
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "ERROR: docker-compose.yml not found at $COMPOSE_FILE" >&2
  exit 1
fi

# Pull new images (ignore failures)
echo "Pulling latest images (if any)..."
docker compose -f "$COMPOSE_FILE" pull --ignore-pull-failures 2>/dev/null || true

# Run containers
if ! docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans; then
  echo "ERROR: Failed to start containers" >&2
  exit 1
fi
echo "✓ Containers started"

# ------------- Step 4: Show status -----------------------
echo ""
echo "▶ Container status:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "=========================================="
echo "  DEPLOYMENT COMPLETED ✓"
echo "=========================================="
echo ""
echo "Next steps (optional):"
echo "  - Verify frontend: https://recall.theonezone.my.id/"
echo "  - Verify backend API: https://apirecall.theonezone.my.id/health"
echo ""
echo "If something doesn’t work, check container logs:"
echo "  docker compose -f $COMPOSE_FILE logs -f --tail=100"
