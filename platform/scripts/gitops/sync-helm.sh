#!/usr/bin/env bash
set -e
echo "🔄 Calling CI Sync Binary..."

${SYNC_BIN} "http://${GIT_USER}:${GIT_PASS}@localhost:${GIT_PORT}/${GIT_USER}/manifests.git"
