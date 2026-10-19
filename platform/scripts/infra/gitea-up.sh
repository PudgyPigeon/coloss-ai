#!/usr/bin/env bash
set -euo pipefail

: "${GIT_SERVICE_NAME:=gitea}"
: "${GIT_PORT:=3000}"
: "${GIT_USER:=gitea_admin}"
: "${GIT_PASS:=AdminPassword123!}"

if [ ! "$(docker ps -aq -f name="^/${GIT_SERVICE_NAME}$")" ]; then
  echo "=================================================="
  echo " 🚀 Launching Gitea service with Push-to-Create..."
  echo "=================================================="

  docker run -d --name "${GIT_SERVICE_NAME}" -p "${GIT_PORT}":3000 -p 2222:22 --restart=always \
    -e GITEA__database__DB_TYPE=sqlite3 \
    -e GITEA__security__INSTALL_LOCK=true \
    -e GITEA__repository__ENABLE_PUSH_CREATE_USER=true \
    -e GITEA__repository__ENABLE_PUSH_CREATE_ORG=true \
    -e USER_UID=1000 \
    -e USER_GID=1000 \
    gitea/gitea:latest

  echo "⏳ Waiting for Gitea startup checks to complete..."
  until docker exec "${GIT_SERVICE_NAME}" curl -sf http://localhost:3000/api/healthz > /dev/null 2>&1; do
    sleep 2
  done

  echo "👤 Creating cluster administrator profile..."
  docker exec -u 1000 "${GIT_SERVICE_NAME}" \
    /usr/local/bin/gitea admin user create \
      --work-path /data/gitea \
      --config /data/gitea/conf/app.ini \
      --username "${GIT_USER}" \
      --password "${GIT_PASS}" \
      --email "${GIT_USER}@cluster.local" \
      --admin \
      --must-change-password=false

  echo "✅ Gitea engine is ready. Push-to-Create is active."
else
  echo "🚀 Gitea container is already running."
fi

GITEA_CMD=(
  docker exec -u 1000 "${GIT_SERVICE_NAME}"
  /usr/local/bin/gitea
  --work-path /data/gitea
  --config /data/gitea/conf/app.ini
)

GITEA_USERS=$("${GITEA_CMD[@]}" admin user list)
if printf '%s\n' "$GITEA_USERS" |
  awk -v username="${GIT_USER}" 'NR > 1 && $2 == username { found = 1 } END { exit !found }'; then
  echo "🔑 Updating cluster administrator credentials..."
  "${GITEA_CMD[@]}" admin user change-password \
    --username "${GIT_USER}" \
    --password "${GIT_PASS}" \
    --must-change-password=false
else
  echo "👤 Creating cluster administrator profile..."
  "${GITEA_CMD[@]}" admin user create \
    --username "${GIT_USER}" \
    --password "${GIT_PASS}" \
    --email "${GIT_USER}@cluster.local" \
    --admin \
    --must-change-password=false
fi

echo "✅ Gitea engine is ready. Push-to-Create is active."