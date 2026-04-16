{ pkgs }:
let
  # Instantiate the renderer for Sandbox
  sandboxManifests = import ./helm.nix {
    inherit pkgs;
    env = "sandbox";
  };

  # Instantiate the renderer for Production
  prodManifests = import ./helm.nix {
    inherit pkgs;
    env = "prod";
  };
in
{
  apps = {
    # The application program entry points
    sync-sandbox = {
      type = "app";
      program = "${sandboxManifests.syncScript}/bin/sync-sandbox";
      meta.description = "Sync Helm charts to the Sandbox Gitea/ArgoCD environment";
    };
    sync-prod = {
      type = "app";
      program = "${prodManifests.syncScript}/bin/sync-prod";
      meta.description = "Sync Helm charts to the Production Gitea/ArgoCD environment";
    };
  };

  # Expose the raw Nix store paths for debugging or other logic
  rendered = {
    sandbox = sandboxManifests.renderedManifests;
    prod = prodManifests.renderedManifests;
  };
}
