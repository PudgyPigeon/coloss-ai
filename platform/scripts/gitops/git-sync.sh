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
# Ensure we can delete the read-only files from the Nix store during cleanup
trap 'chmod -R +w "$WORK_DIR" && rm -rf "$WORK_DIR"' EXIT

echo "📂 Copying rendered manifests from Nix store..."
cp -rL "$RENDERED_MANIFESTS_PATH"/. "$WORK_DIR/"

# Make files writable so Git can handle them
chmod -R +w "$WORK_DIR"

cd "$WORK_DIR"

echo "🚀 Initializing Git for branch: $TARGET_BRANCH"
"$GIT_BIN" init -q
"$GIT_BIN" config user.email "ci@nix.local"
"$GIT_BIN" config user.name "Nix Renderer"

"$GIT_BIN" checkout -b "$TARGET_BRANCH" -q
"$GIT_BIN" add .
"$GIT_BIN" commit -m "Rendered $ENV_NAME: $(date)" -q || { echo "No changes to commit."; exit 0; }

echo "📤 Pushing to Gitea (branch: $TARGET_BRANCH)..."
"$GIT_BIN" push --force "$REMOTE_URL" "$TARGET_BRANCH" -q

echo "✅ Success: $ENV_NAME manifests pushed to $TARGET_BRANCH."
