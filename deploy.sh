#!/bin/bash
# ────────────────────────────────────────────────────────────
#  deploy.sh — Deploy Recall via docker compose
#  Called by GitHub Actions over SSH, or manually on the server.
#
#  Usage:
#    ./deploy.sh [branch]
#  Defaults to "main".
#
#  This script:
#    1. fetches the target branch + submodules
#    2. pulls & rebuilds the docker images
#    3. restarts frontend (recall-web) and backend (recall-api)
#    4. prunes old images
# ────────────────────────────────────────────────────────────
set -euo pipefail

BRANCH="${1:-main}"
APP_DIR="/var/www/my-app"
COMPOSE_FILE="${APP_DIR}/docker-compose.yml"

log() { printf "\n\033[1;34m▶ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m⚠ %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m✗ %s\033[0m\n" "$*" >&2; }
ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }

cd "$APP_DIR"

# Sanity checks
log "Pre-flight checks"
if ! command -v docker >/dev/null 2>&1; then
  err "docker is not installed or not in PATH"; exit 1
fi
if ! docker info >/dev/null 2>&1; then
  err "docker daemon is not reachable"; exit 1
fi
if [ ! -f "$COMPOSE_FILE" ]; then
  err "$COMPOSE_FILE not found"; exit 1
fi
ok "docker ok, compose file present"

# Git: get the right code
log "Fetching branch: $BRANCH"
git remote get-url origin >/dev/null 2>&1 || {
  err "git remote 'origin' not configured"; exit 1;
}

# If running over SSH from GitHub Actions, git may not be able to switch branches
# because the FS is owned by a different user than the one authenticated.
# We tolerate that by setting safe.directory and forcing the checkout.
git config --global --add safe.directory "$APP_DIR" || true

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD || echo "")"
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
  git fetch --all --prune
  git checkout "$BRANCH"
fi
git pull --ff-only origin "$BRANCH"

# Update submodules (recall-api + recall-web)
log "Updating submodules"
git submodule sync --recursive
git submodule update --init --recursive --force
ok "submodules at $(git -c submodule.recurse=0 ls-files --stage | awk '{print $3}' | sort -u | head -1 | cut -c1-7)"

# Build + restart services
log "Building and restarting containers"
docker compose -f "$COMPOSE_FILE" pull --ignore-pull-failures || true
docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

# Show running services
log "Current container status"
docker compose -f "$COMPOSE_FILE" ps

# Cleanup
log "Pruning dangling images"
docker image prune -f >/dev/null 2>&1 || true

ok "Deployment finished for branch '$BRANCH'"
