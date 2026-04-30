#!/usr/bin/env bash
set -e
if [ ! "$(docker ps -aq -f name=${GIT_SERVICE_NAME})" ]; then
  echo "🚀 Starting Git Service with Push-to-Create enabled..."

  docker run -d --name ${GIT_SERVICE_NAME} -p ${GIT_PORT}:3000 -p 2222:22 --restart=always \
    -e GITEA__database__DB_TYPE=sqlite3 \
    -e GITEA__security__INSTALL_LOCK=true \
    -e GITEA__repository__ENABLE_PUSH_CREATE_USER=true \
    -e GITEA__repository__ENABLE_PUSH_CREATE_ORG=true \
    -e USER_UID=1000 \
    -e USER_GID=1000 \
    gitea/gitea:latest

  echo "⏳ Waiting for Gitea to be ready..."
  until docker exec ${GIT_SERVICE_NAME} curl -s http://localhost:3000 > /dev/null; do
    sleep 2
  done

  echo "👤 Creating Admin User..."
  docker exec -u 1000 ${GIT_SERVICE_NAME} /usr/local/bin/gitea admin user create \
    --username "${GIT_USER}" \
    --password "${GIT_PASS}" \
    --email "${GIT_USER}@local" \
    --admin \
    --must-change-password=false || true

  echo "✅ Gitea is ready. Push-to-Create is ACTIVE."
fi
