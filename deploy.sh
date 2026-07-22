#!/bin/bash
# ────────────────────────────────────────────────────────────
#  deploy.sh — Spring Boot script for Recall CI/CD
#  Usage: ./deploy.sh [image-tag]
#  Specifies image tags in docker-compose after pulling
# ────────────────────────────────────────────────────────────
set -euo pipefail

BRANCH="${1:-main}"
APP_DIR="/var/www/my-app"
COMPOSE_FILE="${APP_DIR}/docker-compose.yml"

TIMEZONE=$(date +%Y%m%d-%H%M%S)

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

# ─── Determine image tag ──────────────────────────────────────
SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "$TIMEZONE")
IMAGE_TAG="${1:-sha-${SHORT_SHA}}"

log "Deploying tag: ${IMAGE_TAG}"

# ─── Update docker-compose.yml with image tags ───────────────
log "Configuring image tags"
cp "$COMPOSE_FILE" "${COMPOSE_FILE}.bak.${TIMEZONE}"
sed -i "s|image: ghcr.io/diwanprnm/recall-deploy/recall-web:.*|image: ghcr.io/diwanprnm/recall-deploy/recall-web:${IMAGE_TAG}|" "$COMPOSE_FILE"
sed -i "s|image: ghcr.io/diwanprnm/recall-deploy/recall-api:.*|image: ghcr.io/diwanprnm/recall-deploy/recall-api:${IMAGE_TAG}|" "$COMPOSE_FILE"

ok "Image tags updated"

# ─── Git: Pull latest deployment repo ───────────────────────
log "Fetching branch: $BRANCH"
git remote get-url origin >/dev/null 2>&1 || { err "git remote 'origin' not configured"; exit 1; }

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

# ─── Build + restart services ────────────────────────────────
log "Building and restarting containers"

# Login to ghcr if token provided
# if [ -n "${GHCR_TOKEN:-}" ]; then
#     echo "$GHCR_TOKEN" | docker login ghcr.io -u diwanprnm --password-stdin
# fi

docker compose -f "$COMPOSE_FILE" pull --ignore-pull-failures || true
docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

# Show running services
log "Current container status"
docker compose -f "$COMPOSE_FILE" ps

# Cleanup
log "Pruning dangling images"
docker image prune -f >/dev/null 2>&1 || true

ok "Deployment finished for branch '$BRANCH' tag '$IMAGE_TAG'"