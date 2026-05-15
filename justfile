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
    @echo "Updating Don-Erleone..."
    (cd apps/don-erleone && nix flake update)

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

# --- Don Erleone ---

# Load the image into the local Docker daemon
[group: 'don-erleone']
don-erleone-load:
    nix run .#don-erleone-load
    minikube image load don-erleone:latest

# Run the orchestrator directly via Nix
[group: 'don-erleone']
don-erleone-run:
    nix run .#don-erleone-run

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
    @echo "\n=== Don Erleone Commands ==="
    @just --justfile apps/don-erleone/justfile --list

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
erlang_don_erleone_path := "apps/don-erleone"

# Replace these with your actual public repository URLs
haskell_kubernetes_mcp_remote := "https://github.com/PudgyPigeon/haskell-kubernetes-mcp.git"
erlang_don_erleone_remote := "https://github.com/PudgyPigeon/don-erleone.git"

# Push the Kubernetes MCP code to its own public repo
[group: 'git']
git-haskell-kubernetes-mcp-push:
    git subtree push --prefix={{ haskell_kubernetes_mcp_path }} {{ haskell_kubernetes_mcp_remote }} main

# Pull updates from the public Kubernetes MCP repo back into the monorepo
[group: 'git']
git-haskell-kubernetes-mcp-pull:
    git subtree pull --prefix={{ haskell_kubernetes_mcp_path }} {{ haskell_kubernetes_mcp_remote }} main --squash

# Push the Don Erleone code to its own public repo
[group: 'git']
git-erlang-don-erleone-push:
    git subtree push --prefix={{ erlang_don_erleone_path }} {{ erlang_don_erleone_remote }} main

# Pull updates from the public Don Erleone repo back into the monorepo
[group: 'git']
git-erlang-don-erleone-pull:
    git subtree pull --prefix={{ erlang_don_erleone_path }} {{ erlang_don_erleone_remote }} main --squash

# Push all changes as a single squashed commit with a custom message
[group: 'git']
git-don-erleone-squash-push message="feat: Aggregated updates from monorepo":
    @echo "=> Squashing changes for Don Erleone with message: '{{message}}'..."
    # 1. Clean up old temp branches
    @git branch -D tmp-don-erleone-split 2>/dev/null || true
    
    # 2. Extract the subtree history to a temporary branch
    git subtree split --prefix={{ erlang_don_erleone_path }} -b tmp-don-erleone-split
    
    # 3. Fetch the latest remote state
    git fetch {{ erlang_don_erleone_remote }} main
    
    # 4. Switch to the split branch and reset soft to the remote's head
    git checkout tmp-don-erleone-split
    git reset --soft FETCH_HEAD
    
    # 5. Create the single aggregated commit using your input
    git commit -m "{{message}}"
    
    # 6. Push to remote main
    git push {{ erlang_don_erleone_remote }} tmp-don-erleone-split:main
    
    # 7. Cleanup
    git checkout -
    git branch -D tmp-don-erleone-split
    @echo "=> Successfully pushed squashed update to Don Erleone."

# --- [ Sub-Project Dispatchers ] ---

# Dispatch any command to the Kubernetes MCP justfile
[group: 'subdir']
kubernetes-mcp +args:
    @just --justfile apps/kubernetes-mcp/justfile --working-directory apps/kubernetes-mcp {{args}}

# Dispatch any command to the Don Erleone justfile
[group: 'subdir']
don-erleone +args:
    @just --justfile apps/don-erleone/justfile --working-directory apps/don-erleone {{args}}