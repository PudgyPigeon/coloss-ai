{ pkgs
, env ? "sandbox"
,
}:
let
  targetBranch =
    if env == "sandbox"
    then "sandbox"
    else "main";
  # src = builtins.filterSource (path: type: true) ./..;
  src = pkgs.lib.cleanSource ./..;
  envValuesDir = "${src}/helm/values/${env}";

  tiers = {
    mgmt = "${src}/helm/mgmt";
    infra = "${src}/helm/infra";
    apps = "${src}/helm/apps";
  };

  renderedManifests =
    pkgs.runCommand "rendered-manifests-${env}"
      {
        nativeBuildInputs = [ pkgs.kubernetes-helm ];
        # Pass variables to the script
        TIER_NAMES = pkgs.lib.concatStringsSep " " (pkgs.lib.attrNames tiers);
        TIER_MAPPINGS = pkgs.lib.concatStringsSep " " (pkgs.lib.mapAttrsToList (name: path: "${name}:${path}") tiers);
        ENV_VALUES_DIR = envValuesDir;
      }
      (builtins.readFile ../platform/scripts/gitops/render-manifests.sh);

in
{
  inherit renderedManifests;

  syncScript = pkgs.writeShellScriptBin "sync-${env}" ''
    # Export variables for the git-sync script
    export TARGET_BRANCH="${targetBranch}"
    export ENV_NAME="${env}"
    export RENDERED_MANIFESTS_PATH="${renderedManifests}"
    export GIT_BIN="${pkgs.git}/bin/git"

    # Call the external script logic
    ${builtins.readFile ../platform/scripts/gitops/git-sync.sh}
  '';
}
