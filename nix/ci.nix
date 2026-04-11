{pkgs}: let
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
in {
  apps = {
    # The application program entry points
    sync-sandbox = {
      type = "app";
      program = "${sandboxManifests.syncScript}/bin/sync-sandbox";
    };
    sync-prod = {
      type = "app";
      program = "${prodManifests.syncScript}/bin/sync-prod";
    };
  };

  # Expose the raw Nix store paths for debugging or other logic
  rendered = {
    sandbox = sandboxManifests.renderedManifests;
    prod = prodManifests.renderedManifests;
  };
}
