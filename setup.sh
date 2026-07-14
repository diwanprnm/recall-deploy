#!/bin/bash

# ──────────────────────────────────────────────────────────────────
# Recall Local Dev Setup
# ──────────────────────────────────────────────────────────────────
# Usage:   ./setup.sh           → bring up the stack
#          ./setup.sh down      → tear down everything (keep volumes)
#          ./setup.sh reset     → tear down and DELETE volumes + node_modules
# ──────────────────────────────────────────────────────────────────

set -e

MODE="${1:-up}"

case "$MODE" in
  up)
    echo "╭───────────────────────────────────────╮"
    echo "│ Recall – Local Dev Setup              │"
    echo "╰───────────────────────────────────────╯"
    echo ""

    # 1. Ensure .env exists at the root.
    if [ ! -f .env ]; then
      echo "▶ No .env found. Copying .env.example → .env"
      cp .env.example .env
      echo ""
      echo "  ⚠  IMPORTANT: edit .env with your real Supabase keys!"
      echo "     (and OPENAI_API_KEY for the AI features)"
      echo ""
      echo "     When you're done, run ./setup.sh again."
      exit 1
    fi

    # 2. Make sure backend has its own .env (FastAPI loads ./app/.env).
    if [ ! -f recall-api/.env ]; then
      echo "▶ Creating recall-api/.env (FastAPI loads relative to WORKDIR)"
      cp .env recall-api/.env
    fi

    # 3. Make sure frontend has its own .env.local (Next.js convention).
    if [ ! -f recall-web/.env.local ]; then
      echo "▶ Creating recall-web/.env.local (Next.js build-time env)"
      cat > recall-web/.env.local <<EOF
NEXT_PUBLIC_SUPABASE_URL=$(grep '^NEXT_PUBLIC_SUPABASE_URL=' .env | cut -d= -f2-)
NEXT_PUBLIC_SUPABASE_ANON_KEY=$(grep '^NEXT_PUBLIC_SUPABASE_ANON_KEY=' .env | cut -d= -f2-)
NEXT_PUBLIC_API_URL=http://localhost:8000
EOF
    fi

    # 4. Make sure node_modules volume is fresh.
    docker volume create my-app_node_modules > /dev/null 2>&1 || true

    # 5. Build & start.
    echo "▶ Building and starting containers..."
    docker compose --env-file .env -f docker-compose.yml up --build -d

    # 6. Wait for backend & frontend health.
    echo "▶ Waiting for backend health..."
    until curl -sf http://localhost:8000/health > /dev/null 2>&1; do
      sleep 2
    done
    echo "✓ backend healthy"

    echo "▶ Waiting for frontend..."
    sleep 5
    echo "✓ frontend assumed healthy"

    echo ""
    echo "╭──────────────────────────────────────────────╮"
    echo "│  Recall is up!                              │"
    echo "│                                              │"
    echo "│  Frontend:  http://localhost:3000            │"
    echo "│  Backend:   http://localhost:8000            │"
    echo "│  API docs:  http://localhost:8000/docs       │"
    echo "╰──────────────────────────────────────────────╯"
    echo ""
    echo "  Tail logs:   docker compose -f docker-compose.yml logs -f"
    echo "  Stop:        docker compose -f docker-compose.yml down"
    ;;

  down)
    echo "▶ Stopping containers (volumes preserved)..."
    docker compose -f docker-compose.yml down
    ;;

  reset)
    echo "⚠  This will DELETE node_modules volume and reset everything!"
    read -p "  Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      docker compose -f docker-compose.yml down -v
      docker volume rm my-app_node_modules 2>/dev/null || true
      rm -f recall-api/.env recall-web/.env.local .env
      echo "✓ Reset done. Run ./setup.sh to start fresh."
    else
      echo "Cancelled."
    fi
    ;;

  *)
    echo "Usage: $0 {up|down|reset}"
    exit 1
    ;;
esac
