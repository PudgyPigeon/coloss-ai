#!/usr/bin/env bash
set -euo pipefail

# Variables passed from Nix:
# TARGET_BRANCH
# ENV_NAME
# RENDERED_MANIFESTS_PATH
# GIT_BIN

REMOTE_URL="${1:-""}"
if [ -z "$REMOTE_URL" ]; then
  echo "❌ Error: Git Remote URL is required."
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'chmod -R +w "$WORK_DIR" && rm -rf "$WORK_DIR"' EXIT

echo "=================================================="
echo " 📂 Copying rendered manifests from Nix store..."
echo "=================================================="
cp -rL "$RENDERED_MANIFESTS_PATH"/. "$WORK_DIR/"
chmod -R +w "$WORK_DIR"
cd "$WORK_DIR"

echo "📂 Initializing Git repository on branch: $TARGET_BRANCH"
"$GIT_BIN" init -q
"$GIT_BIN" config user.email "renderer@nixos.local"
"$GIT_BIN" config user.name "Nix Swarm Renderer"

"$GIT_BIN" checkout -b "$TARGET_BRANCH" -q
"$GIT_BIN" add .

if "$GIT_BIN" diff-index --quiet HEAD --; then
  echo " ℹ️  No changes to commit. Cluster matches state."
  exit 0
fi

"$GIT_BIN" commit -m "Rendered $ENV_NAME: $(date)" -q

echo "📤 Pushing manifests to GitOps repository..."
"$GIT_BIN" push --force "$REMOTE_URL" "$TARGET_BRANCH" -q

echo "=================================================="
echo " ✅ Success: $ENV_NAME manifests synchronized."
echo "=================================================="
