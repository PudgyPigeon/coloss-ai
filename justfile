#!/usr/bin/env -S just --justfile

# --- Variables ---
# system := `nix eval --raw --expr 'builtins.currentSystem'`

# --- General ---

# List all recipes
default:
    @just --list

# Update all lockfiles recursively (Root, Aggregator, and Apps)
[group: 'general']
update-all:
    @echo "Updating Root..."
    nix flake update
    @echo "Updating Aggregator..."
    (cd apps && nix flake update)
    @echo "Updating Kubernetes MCP..."
    (cd apps/kubernetes-mcp && nix flake update)

# Format all Nix files in the repository
[group: 'general']
fmt:
    nix fmt .

# --- Kubernetes MCP ---

# Load the image into the local Docker daemon
[group: 'k8s-mcp']
k8s-mcp-load:
    nix run .#kubernetes-mcp-load
    minikube image load kubernetes-mcp:latest

# Run the MCP server directly via Nix
[group: 'k8s-mcp']
k8s-mcp-run:
    nix run .#kubernetes-mcp

# --- Infrastructure ---

# Verify that all flakes in the repo evaluate correctly
[group: 'infra']
check:
    nix flake check .

# Clean up the Nix store and delete old generations
[group: 'infra']
gc:
    nix-collect-garbage -d

# Push the image directly to a remote registry using skopeo
[group: 'registry']
k8s-mcp-push registry="ghcr.io/my-user":
    skopeo copy \
      nix:$(nix build .#kubernetes-mcp-image --print-out-paths) \
      docker://{{registry}}/kubernetes-mcp:latest

[group: 'help']
list-all:
    @echo "=== Root Commands ==="
    @just --list
    @echo "\n=== Kubernetes MCP Commands ==="
    @just --justfile apps/kubernetes-mcp/justfile --list

# --- [ Sub-Project Dispatcher ] ---

# Dispatch any command to the Kubernetes MCP justfile
# Usage: just k8s-mcp watch OR just k8s-mcp build
[group: 'subdir']
k8s-mcp +args:
    @just --justfile apps/kubernetes-mcp/justfile --working-directory apps/kubernetes-mcp {{args}}