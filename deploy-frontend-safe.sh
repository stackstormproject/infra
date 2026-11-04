#!/usr/bin/env bash
set -Eeuo pipefail

TARGET="${1:-}"

case "$TARGET" in
  customer)
    REPO="stackstorm-frontend-customer"
    CONTAINER="infra-customer-1"
    IMAGE="stackstorm-customer"
    PORT="8080"
    ALIAS="customer"
    SOCKET_KEY="VITE_SOCKET_URL_CUSTOMER"
    ;;
  admin)
    REPO="stackstorm-frontend-admin"
    CONTAINER="infra-admin-1"
    IMAGE="stackstorm-admin"
    PORT="8081"
    ALIAS="admin"
    SOCKET_KEY="VITE_SOCKET_URL_ADMIN"
    ;;
  *)
    echo "Usage: $0 customer|admin"
    exit 2
    ;;
esac

ROOT="$HOME/stackstorm"
FRONTEND="$ROOT/$REPO"
ENV_FILE="$ROOT/infra/.env.prod"
NETWORK="infra_internal"

test -d "$FRONTEND/.git" || { echo "Frontend repository missing"; exit 1; }
test -f "$ENV_FILE" || { echo ".env.prod missing"; exit 1; }
docker network inspect "$NETWORK" >/dev/null
docker inspect "$CONTAINER" >/dev/null

SOCKET_URL="$(awk -F= -v key="$SOCKET_KEY" '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  {
    k=$1
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
    if (k == key) {
      sub(/^[^=]*=/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  }
' "$ENV_FILE")"

test -n "$SOCKET_URL" || { echo "Missing $SOCKET_KEY"; exit 1; }

BRANCH="$(git -C "$FRONTEND" branch --show-current)"
test "$BRANCH" = "develop" || {
  echo "Expected develop branch; found $BRANCH"
  exit 1
}

CHANGES="$(git -C "$FRONTEND" status --porcelain)"
if [ "$TARGET" = "customer" ]; then
  if [ -n "$CHANGES" ] && [ "$CHANGES" != " M Dockerfile" ]; then
    echo "Unexpected customer repository changes; refusing deployment"
    exit 1
  fi
else
  if [ -n "$CHANGES" ]; then
    echo "Unexpected admin repository changes; refusing deployment"
    exit 1
  fi
fi

git -C "$FRONTEND" fetch origin develop
git -C "$FRONTEND" merge --ff-only origin/develop

COMMIT="$(git -C "$FRONTEND" rev-parse --short=12 HEAD)"
STAMP="$(date -u +%Y%m%d%H%M%S)"
NEW_IMAGE="$IMAGE:$STAMP-$COMMIT"
TEST_CONTAINER="$CONTAINER-test-$STAMP"
OLD_CONTAINER="$CONTAINER-rollback-$STAMP"

OLD_MOVED=0

cleanup_test() {
  docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
}

rollback() {
  status=$?
  trap - ERR
  echo "Deployment failed. Restoring previous frontend..."
  if [ "$OLD_MOVED" = "1" ]; then
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  fi
  if [ "$OLD_MOVED" = "1" ] && docker inspect "$OLD_CONTAINER" >/dev/null 2>&1; then
    docker rename "$OLD_CONTAINER" "$CONTAINER"
    docker network connect --alias "$ALIAS" "$NETWORK" "$CONTAINER" || true
    docker start "$CONTAINER" >/dev/null
  fi
  cleanup_test
  exit "$status"
}

trap cleanup_test EXIT

echo "Building selected frontend image..."
docker build \
  --build-arg VITE_API_BASE_URL=/api/v1 \
  --build-arg VITE_SOCKET_URL="$SOCKET_URL" \
  -t "$NEW_IMAGE" "$FRONTEND"

echo "Testing candidate frontend..."
docker run -d --name "$TEST_CONTAINER" \
  --network "$NETWORK" "$NEW_IMAGE" >/dev/null

healthy=0
for _ in $(seq 1 30); do
  if docker exec "$TEST_CONTAINER" wget -qO- http://127.0.0.1/ >/dev/null 2>&1; then
    healthy=1
    break
  fi
  sleep 2
done

test "$healthy" = "1" || {
  docker logs "$TEST_CONTAINER" || true
  echo "Candidate frontend failed its HTTP check"
  exit 1
}

docker exec "$TEST_CONTAINER" wget -qO- \
  http://backend:5000/api/health >/dev/null

cleanup_test

echo "Preserving old container..."
trap rollback ERR
docker stop "$CONTAINER" >/dev/null
docker rename "$CONTAINER" "$OLD_CONTAINER"
OLD_MOVED=1
docker network disconnect "$NETWORK" "$OLD_CONTAINER"

echo "Starting replacement frontend..."
docker run -d \
  --name "$CONTAINER" \
  --network "$NETWORK" \
  --network-alias "$ALIAS" \
  --restart unless-stopped \
  -p "$PORT:80" \
  "$NEW_IMAGE" >/dev/null

healthy=0
for _ in $(seq 1 30); do
  if docker exec "$CONTAINER" wget -qO- http://127.0.0.1/ >/dev/null 2>&1 \
    && docker exec "$CONTAINER" wget -qO- http://backend:5000/api/health >/dev/null 2>&1; then
    healthy=1
    break
  fi
  sleep 2
done

test "$healthy" = "1" || {
  docker logs "$CONTAINER" || true
  echo "Replacement frontend failed health checks"
  false
}

trap - ERR
trap - EXIT
cleanup_test

echo "SUCCESS: $TARGET frontend deployed."
echo "Image: $NEW_IMAGE"
echo "Previous container retained: $OLD_CONTAINER"
