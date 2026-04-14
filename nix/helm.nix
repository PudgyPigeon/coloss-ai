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
      } ''
            set -euo pipefail
            ${pkgs.lib.concatStringsSep "\n" (map (tier: "mkdir -p $out/${tier}") (pkgs.lib.attrNames tiers))}

      ${pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList (tier: path: ''
          echo "--- Rendering Tier: ${tier} ---"
          if [ -d "${path}" ]; then
            for component_path in ${path}/*; do
              if [ -d "$component_path" ] && [ -f "$component_path/Chart.yaml" ]; then
                # This captures 'cert-manager' or 'argocd' from the folder path
                name=$(basename "$component_path")

                VALS="${envValuesDir}/$name.yaml"
                RENDER_TMP=$(mktemp -d)

                # 1. Start empty
                VALS_ARG=""

                # 2. Add the base chart values (Lower Priority)
                BASE_VALS="$component_path/values.yaml"
                if [ -f "$BASE_VALS" ]; then
                  VALS_ARG="-f $BASE_VALS"
                fi

                # 3. Add the environment-specific values (Higher Priority)
                ENV_VALS="${envValuesDir}/$name.yaml"
                if [ -f "$ENV_VALS" ]; then
                  VALS_ARG="$VALS_ARG -f $ENV_VALS"
                fi

                echo "Rendering $name into namespace $name..."

                # Use $name for the namespace flag
                helm template "$name" "$component_path" \
                  $VALS_ARG \
                  --namespace "$name" \
                  --output-dir "$RENDER_TMP"

                mkdir -p "$out/${tier}/$name"
                find "$RENDER_TMP" -name "*.yaml" -exec cp {} "$out/${tier}/$name/" \;
                rm -rf "$RENDER_TMP"
              fi
            done
          fi
        '')
        tiers)}

            if [ -z "$(find $out -name "*.yaml" -print -quit)" ]; then
              echo "❌ ERROR: No manifests were rendered."
              exit 1
            fi
    '';
in
{
  inherit renderedManifests;

  syncScript = pkgs.writeShellScriptBin "sync-${env}" ''
    set -euo pipefail

    REMOTE_URL=''${1:-""}
    if [ -z "$REMOTE_URL" ]; then
      echo "❌ Error: Git Remote URL is required."
      exit 1
    fi

    WORK_DIR=$(mktemp -d)
    # FIX: Ensure we can delete the read-only files from the Nix store during cleanup
    trap 'chmod -R +w "$WORK_DIR" && rm -rf "$WORK_DIR"' EXIT

    echo "📂 Copying rendered manifests from Nix store..."
    cp -rL ${renderedManifests}/. "$WORK_DIR/"

    # FIX: Make files writable so Git can handle them and the script can delete them later
    chmod -R +w "$WORK_DIR"

    cd "$WORK_DIR"

    echo "🚀 Initializing Git for branch: ${targetBranch}"
    ${pkgs.git}/bin/git init -q
    ${pkgs.git}/bin/git config user.email "ci@nix.local"
    ${pkgs.git}/bin/git config user.name "Nix Renderer"

    ${pkgs.git}/bin/git checkout -b ${targetBranch} -q
    ${pkgs.git}/bin/git add .
    ${pkgs.git}/bin/git commit -m "Rendered ${env}: $(date)" -q || { echo "No changes to commit."; exit 0; }

    echo "📤 Pushing to Gitea (branch: ${targetBranch})..."
    ${pkgs.git}/bin/git push --force "$REMOTE_URL" ${targetBranch} -q

    echo "✅ Success: ${env} manifests pushed to ${targetBranch}."
  '';
}
