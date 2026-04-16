# nix/apps.nix
{ pkgs }:
let
  ciData = import ./ci.nix { inherit pkgs; };

  # ciData looks like { apps = { sync-sandbox = ... }; rendered = ...; }
  # We want just the apps part.
  ciApps = ciData.apps;
in
{
  # 1. This provides the nested 'ci' key back to shell.nix
  # We wrap it in an 'apps' attribute to match what shell.nix expects
  ci = { inherit (ciData) apps; };

  # 2. This is what the Root Flake uses (MUST be a flat list of apps)
  all = ciApps;
}
