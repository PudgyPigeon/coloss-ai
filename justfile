#!/usr/bin/env -S just --justfile

# --- Variables ---
system := `nix eval --raw --impure --expr 'builtins.currentSystem'`

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
[group: 'kubernetes-mcp']
kubernetes-mcp-load:
    nix run .#kubernetes-mcp-load
    minikube image load kubernetes-mcp:latest

# Run the MCP server directly via Nix
[group: 'kubernetes-mcp']
kubernetes-mcp-run:
    nix run .#kubernetes-mcp

# --- Rig Brain ---

# Load the image into the local Docker daemon
[group: 'rig-brain']
rig-brain-load:
    nix run .#rig-brain-load
    minikube image load rig-brain:latest

# Run the orchestrator directly via Nix
[group: 'rig-brain']
rig-brain-run:
    nix run .#rig-brain

# --- Infrastructure ---

# Verify that all flakes in the repo evaluate correctly
[group: 'infra']
check:
    nix flake check .

# Clean up the Nix store and delete old generations
[group: 'infra']
gc:
    nix-collect-garbage -d

# # Push the image directly to a remote registry using skopeo
# [group: 'registry']
# kubernetes-mcp-push registry="ghcr.io/my-user":
#     skopeo copy \
#       nix:$(nix build .#kubernetes-mcp-image --print-out-paths) \
#       docker://{{registry}}/kubernetes-mcp:latest

[group: 'help']
list-all:
    @echo "=== Root Commands ==="
    @just --list
    @echo "\n=== Kubernetes MCP Commands ==="
    @just --justfile apps/kubernetes-mcp/justfile --list
    @echo "\n=== Rig Brain Commands ==="
    @just --justfile apps/rig-brain/justfile --list

# List all low-level Nix apps available in this flake
[group: 'help']
nix-apps:
    @echo "--- Available Nix Apps (nix run .#<name>) ---"
    @nix eval --json .#apps.{{system}} --apply builtins.attrNames | jq -r 'sort | .[]' | sed 's/^/  - /'


##############################################
# --- Git Subtree Management ---
##############################################
# Path to the sub-projects
haskell_kubernetes_mcp_path := "apps/kubernetes-mcp"
rust_rig_brain_path := "apps/rig-brain"

# Replace these with your actual public repository URLs
haskell_kubernetes_mcp_remote := "https://github.com/PudgyPigeon/haskell-kubernetes-mcp.git"
rust_rig_brain_remote := "https://github.com/your-username/rig-brain.git"

# Push the Kubernetes MCP code to its own public repo
[group: 'git']
git-haskell-kubernetes-mcp-push:
    git subtree push --prefix={{ haskell_kubernetes_mcp_path }} {{ haskell_kubernetes_mcp_remote }} main

# Pull updates from the public Kubernetes MCP repo back into the monorepo
[group: 'git']
git-haskell-kubernetes-mcp-pull:
    git subtree pull --prefix={{ haskell_kubernetes_mcp_path }} {{ haskell_kubernetes_mcp_remote }} main --squash

# Push the Rig Brain code to its own public repo
[group: 'git']
git-rust-rig-brain-push:
    git subtree push --prefix={{ rust_rig_brain_path }} {{ rust_rig_brain_remote }} main

# Pull updates from the public Rig Brain repo back into the monorepo
[group: 'git']
git-rust-rig-brain-pull:
    git subtree pull --prefix={{ rust_rig_brain_path }} {{ rust_rig_brain_remote }} main --squash

# --- [ Sub-Project Dispatchers ] ---

# Dispatch any command to the Kubernetes MCP justfile
[group: 'subdir']
kubernetes-mcp +args:
    @just --justfile apps/kubernetes-mcp/justfile --working-directory apps/kubernetes-mcp {{args}}

# Dispatch any command to the Rig Brain justfile
[group: 'subdir']
rig-brain +args:
    @just --justfile apps/rig-brain/justfile --working-directory apps/rig-brain {{args}}