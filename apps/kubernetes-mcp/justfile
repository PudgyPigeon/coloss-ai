#!/usr/bin/env -S just --justfile

# Justfile variables
app_name       := "kubernetes-mcp"
app_flags      := "--port 30090 --env dev"
log            := "warn"

export JUST_LOG := log

# Aliases
alias b := build
alias r := reload
alias w := watch
alias f := fmt

# Default: List recipes
default:
    @just --list

# --- dev ---

# Update environment without subshells
[group: 'dev']
reload:
    direnv reload

# Watch and develop with ghciwatch
[group: 'dev']
watch:
    ghciwatch \
      --command "cabal repl exe:{{ app_name }}" \
      --after-startup-ghci ":set args {{ app_flags }}" \
      --watch src \
      --watch app \
      --test-ghci "Main.main" \
      --clear

# --- build ---

# Build the Haskell project
[group: 'build']
build:
    cabal build

# Build with profiling symbols enabled
[group: 'build']
build-profile:
    cabal build --enable-profiling --ghc-options="-fprof-auto"

# Run the project locally
[group: 'build']
run *args:
    cabal run {{ app_name }} -- {{ args }}

# --- test ---

# Run tests once
[group: 'test']
test:
    cabal test --test-show-details=always

# Watch tests using ghcid
[group: 'test']
watch-tests +args="Main.main":
    ghcid --command="cabal repl {{ app_name }}-test" --test="{{ args }}"

# --- check & format ---

# FORCE: Format code and apply HLint refactors automatically
[group: 'check']
fmt:
    nix fmt .
    find src app -name "*.hs" -exec hlint --refactor --refactor-options="-i" {} \;
    fourmolu --mode inplace src/ app/

# CHECK: CI-style check (fails if messy)
[group: 'check']
ci:
    nixpkgs-fmt --check *.nix
    fourmolu --mode check src/ app/
    hlint src/ app/ --fail-on suggestion
    cabal check
    @just build

# --- profile ---

# Performance analysis: Generates an interactive HTML dashboard
[group: 'profile']
profile:
    cabal build --enable-profiling
    # Run with EventLog enabled (+RTS -l)
    cabal run {{ app_name }} -- +RTS -l -RTS {{ app_flags }}
    eventlog2html {{ app_name }}.eventlog
    @echo "Report generated: {{ app_name }}.eventlog.html"

# --- nix ---

# Build the final production artifact via Flake
[group: 'nix']
nix-build:
    nix build .#default

# Run the Nix-built production app
[group: 'nix']
nix-run *args:
    nix run .#default -- {{ args }}

# --- misc ---

# Clean up all build artifacts
[group: 'misc']
clean:
    rm -rf dist-newstyle result *.eventlog *.html
    cabal clean

# Clean up Nix store (Garbage Collection)
[group: 'misc']
gc:
    nix-collect-garbage -d