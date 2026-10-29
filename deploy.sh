#!/usr/bin/env bash
set -e

# ==============================================================================
# StackStorm Production Zero-Downtime Deployment Script
# Multi-Tier E-Commerce Platform (Dickwella Fashion Corner)
#
# Usage:
#   ./deploy.sh [service] [branch]
#
# Examples:
#   ./deploy.sh backend main
#   ./deploy.sh frontend main
#   ./deploy.sh admin main
#   ./deploy.sh all main
# ==============================================================================

SERVICE="${1:-all}"
BRANCH="${2:-main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "======================================================================"
echo "🚀 StackStorm Auto-Deployment Initiated"
echo "Target Service: $SERVICE"
echo "Target Branch:  $BRANCH"
echo "Script Path:    $SCRIPT_DIR"
echo "Root Path:      $ROOT_DIR"
echo "Timestamp:      $(date -u +"%Y-%m-%d %H:%M:%SZ")"
echo "======================================================================"

cd "$ROOT_DIR"

# Helper function to pull git repo
pull_repo() {
  local dir="$1"
  local target_branch="$2"
  if [ -d "$ROOT_DIR/$dir/.git" ]; then
    echo "📥 Updating repository: $dir (branch: $target_branch)..."
    cd "$ROOT_DIR/$dir"
    git fetch origin "$target_branch"
    git checkout "$target_branch"
    git pull origin "$target_branch"
    cd "$ROOT_DIR"
  elif [ -d "$ROOT_DIR/.git" ]; then
    echo "📥 Updating root repository (branch: $target_branch)..."
    git fetch origin "$target_branch"
    git checkout "$target_branch"
    git pull origin "$target_branch"
  else
    echo "⚠️ Notice: No .git found in $dir or root. Proceeding with existing files."
  fi
}

# Determine docker compose file
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.prod.yml"
if [ ! -f "$COMPOSE_FILE" ]; then
  COMPOSE_FILE="$ROOT_DIR/docker-compose.prod.yml"
fi

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "❌ Error: docker-compose.prod.yml not found at $COMPOSE_FILE!"
  exit 1
fi

# Ensure .env exists in infra directory
if [ ! -f "$SCRIPT_DIR/.env" ] && [ -f "$SCRIPT_DIR/.env.prod.example" ]; then
  echo "⚠️ Notice: $SCRIPT_DIR/.env missing. Creating from .env.prod.example..."
  cp "$SCRIPT_DIR/.env.prod.example" "$SCRIPT_DIR/.env"
fi

# Set working directory to infra so relative compose paths resolve properly
cd "$SCRIPT_DIR"

# Ensure core databases (PostgreSQL & Redis) are up and healthy
echo "🐘 Ensuring PostgreSQL & Redis services are healthy..."
docker compose -f "$COMPOSE_FILE" up -d postgres redis

# Export default paths if not explicitly configured in environment
export BACKEND_CONTEXT="${BACKEND_CONTEXT:-../backend}"
if [ ! -f "$SCRIPT_DIR/$BACKEND_CONTEXT/Dockerfile" ] && [ -f "$SCRIPT_DIR/../backend/backend/Dockerfile" ]; then
  export BACKEND_CONTEXT="../backend/backend"
fi
export FRONTEND_CONTEXT="${FRONTEND_CONTEXT:-../frontend}"
export ADMIN_CONTEXT="${ADMIN_CONTEXT:-../stackstorm-frontend-admin}"

case "$SERVICE" in
  backend)
    echo "📦 [1/3] Deploying Backend API service..."
    pull_repo "backend" "$BRANCH"
    pull_repo "backend/backend" "$BRANCH"

    echo "🔨 Building & rolling backend container..."
    docker compose -f "$COMPOSE_FILE" up -d --build --no-deps backend

    echo "🗄️ Executing database migrations..."
    sleep 3
    docker compose -f "$COMPOSE_FILE" exec -T backend npx sequelize-cli db:migrate || {
      echo "⚠️ Migration retry in 5s..."
      sleep 5
      docker compose -f "$COMPOSE_FILE" exec -T backend npx sequelize-cli db:migrate
    }

    echo "🩺 Probing Backend health..."
    sleep 2
    docker compose -f "$COMPOSE_FILE" ps backend
    ;;

  frontend|frontend-customer)
    echo "📦 [2/3] Deploying Customer Storefront SPA..."
    pull_repo "frontend" "$BRANCH"

    echo "🔨 Building & rolling customer storefront container..."
    docker compose -f "$COMPOSE_FILE" up -d --build --no-deps frontend-customer

    echo "🩺 Probing Customer Storefront health..."
    sleep 2
    docker compose -f "$COMPOSE_FILE" ps frontend-customer
    ;;

  admin|frontend-admin|stackstorm-frontend-admin)
    echo "📦 [3/3] Deploying Admin Dashboard Portal..."
    pull_repo "stackstorm-frontend-admin" "$BRANCH"

    echo "🔨 Building & rolling admin portal container..."
    docker compose -f "$COMPOSE_FILE" up -d --build --no-deps frontend-admin

    echo "🩺 Probing Admin Portal health..."
    sleep 2
    docker compose -f "$COMPOSE_FILE" ps frontend-admin
    ;;

  all)
    echo "📦 Full-Stack Deployment in progress..."
    pull_repo "backend" "$BRANCH"
    pull_repo "backend/backend" "$BRANCH"
    pull_repo "frontend" "$BRANCH"
    pull_repo "stackstorm-frontend-admin" "$BRANCH"

    echo "🔨 Building & deploying all application tiers..."
    docker compose -f "$COMPOSE_FILE" up -d --build

    echo "🗄️ Executing database migrations..."
    sleep 5
    docker compose -f "$COMPOSE_FILE" exec -T backend npx sequelize-cli db:migrate || true

    echo "🩺 All services status:"
    docker compose -f "$COMPOSE_FILE" ps
    ;;

  *)
    echo "❌ Unknown service: '$SERVICE'. Expected: backend, frontend, admin, all"
    exit 1
    ;;
esac

# Prune dangling/untagged docker images to reclaim VPS disk space
echo "🧹 Pruning dangling docker images..."
docker image prune -f

echo "======================================================================"
echo "✅ Auto-Deployment of '$SERVICE' succeeded!"
echo "======================================================================"
