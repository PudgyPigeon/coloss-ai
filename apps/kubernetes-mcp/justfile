#!/usr/bin/env -S just --justfile

# Justfile variables
app_name := "kubernetes-mcp"
app_entrypoint := "app/Main.hs"
app_flags := "--port 30090 --env dev"

alias b := build
alias r := reload

log := "warn"
export JUST_LOG := log

# Default recipe
default:
    @just --list

# # --- dev ---

# Update environment without subshells
[group: 'dev']
reload:
    direnv reload

# Watch
[group: 'dev']
watch:
    ghciwatch \
      --command "cabal repl exe:{{ app_name }}" \
      --after-startup-ghci ":set args {{ app_flags }}" \
      --watch src \
      --watch app \
      --test-ghci "Main.main" \
      --clear
# ghciwatch --command "cabal v2-repl exe:k8s-mcp" --watch src --watch app --watch test --clearjus^C

# # Watch mode using ghcid
# [group: 'dev']
# watch +args="main":
#     ghcid --command="cabal repl {{ app_name }} --enable-multi-repl" --test=":l MyLib; {{ args }}"
# # watch +args='Main.main':
# #     ghcid --command="cabal repl exe:k8s-mcp" --test="{{ args }}"
# # watch +args='Main.main':
# #     ghcid --command="cabal repl lib:k8s-mcp" --test="{{ args }}"

# # --- build ---
# Build the Haskell project
[group: 'build']
build:
    cabal build

# Run the Haskell project - You can insert args
[group: 'build']
run *args:
    cabal run {{app_name}} -- {{args}}

[group: 'test']
watch-tests +args="Main.main":
    ghcid --command="cabal repl k8s-mcp-test" --test="{{ args }}"

# Build the final Nix artifact
[group: 'nix']
nix-build:
    nix build .#default


# # --- dev ---

# # Enter the Nix development shell (fallback for non-direnv users)
# [group: 'dev']
# shell:
#     nix develop

# # Watch mode using ghcid
# [group: 'dev']
# watch +args='Main.main':
#     ghcid --command="cabal repl lib:k8s-mcp" --test="{{ args }}"

# # --- build ---

# # Fast incremental build
# [group: 'build']
# build:
#     cabal build

# # Run the MCP server with arguments
# [group: 'build']
# run *args:
#     cabal run k8s-mcp -- {{args}}

# # --- test ---

# # Run all tests
# [group: 'test']
# test:
#     cabal test --test-show-details=always

# # --- check ---

# # CI-style check (Format, Lint, Build)
# [group: 'check']
# ci: fmt-check lint nix-build test

# # Check formatting without applying changes
# [group: 'check']
# fmt-check:
#     nixpkgs-fmt --check *.nix
#     fourmolu --mode check src/ app/

# # HLint check (The Haskell equivalent of Clippy)
# [group: 'check']
# lint:
#     hlint src/ app/

# # --- nix ---

# # Reproducible build via Flake
# [group: 'nix']
# nix-build:
#     nix build .#default

# # Run the Nix-built app
# [group: 'nix']
# nix-run *args:
#     nix run .#default -- {{args}}

# # --- release ---

# # SRE Release flow: Tag and push
# [group: 'release']
# publish:
#     #!/usr/bin/env bash
#     set -euo pipefail
#     VERSION=$(grep -m 1 "version:" k8s-mcp.cabal | awk '{print $2}')
#     echo "Releasing version $VERSION..."
#     git tag -a "v$VERSION" -m "Release $VERSION"
#     git push origin "v$VERSION"

# # --- misc ---

# # Clean up build artifacts and Nix store
# [group: 'misc']
# clean:
#     rm -rf dist-newstyle result
#     cabal clean

# # Clean up Nix store specifically (Garbage Collection)
# [group: 'misc']
# gc:
#     nix-collect-garbage -d