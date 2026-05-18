{ pkgs, config, helmSource, imageLoadCommands ? [ ] }:

let
  # --- Dynamic Helm Manifest Renderer ---
  renderedManifests = pkgs.runCommand "rendered-manifests-${config.envName}"
    {
      nativeBuildInputs = [ pkgs.kubernetes-helm ];
      TIER_NAMES = "mgmt infra apps";
      TIER_MAPPINGS = "mgmt:${helmSource}/mgmt infra:${helmSource}/infra apps:${helmSource}/apps";
      ENV_VALUES_DIR = "${helmSource}/values/${config.envName}";
    }
    (builtins.readFile ./scripts/gitops/render-manifests.sh);

  # --- Helper to bootstrap config environment variables into scripts ---
  mkScript = name: file: extraBash: pkgs.writeShellScriptBin name ''
    # --- Standardized Configuration Envs ---
    export ARGO_CD_NAMESPACE="${config.argoCdNamespace}"
    export ARGOCD_LOCAL_PORT="${config.argocdLocalPort}"
    export ARGOCD_SVC_PORT="${config.argocdSvcPort}"
    export GIT_SERVICE_NAME="${config.gitServiceName}"
    export GIT_PORT="${config.gitPort}"
    export GIT_USER="${config.gitUser}"
    export GIT_PASS="${config.gitPass}"
    export CPU_COUNT="${config.cpuCount}"
    export MEM_COUNT="${config.memCount}"
    export NODE_COUNT="${config.nodeCount}"
    export OPEN_WEBUI_DEST_PORT="${config.openWebUiDestPort}"
    export OPEN_WEBUI_SOURCE_PORT="${config.openWebUiSourcePort}"
    export WIRE_LOCAL_PORT="${config.wireLocalPort}"
    export WIRE_SVC_PORT="${config.wireSvcPort}"

    # --- Directory and Mount references ---
    export HELM_SOURCE_PATH="${helmSource}"
    export IMAGE_LOAD_COMMANDS="${pkgs.lib.concatStringsSep "\n" imageLoadCommands}"

    # --- Extra Context Hooks ---
    ${extraBash}

    # --- Script Execution Core ---
    ${builtins.readFile ./scripts/${file}}
  '';

in
{
  scripts = {
    # --- Infrastructure Layer ---
    gitea-up = mkScript "gitea-up" "infra/gitea-up.sh" "";
    minikube-up = mkScript "minikube-up" "infra/minikube-up.sh" "";
    infra-up = mkScript "infra-up" "infra/infra-up.sh" "";
    down = mkScript "down" "infra/down.sh" "";

    # --- Management Layer ---
    argocd-up = mkScript "argocd-up" "mgmt/argocd-up.sh" "";
    argocd-creds = mkScript "argocd-creds" "mgmt/argocd-creds.sh" "";

    # --- GitOps Core Layer ---
    sync-helm = mkScript "sync-helm" "gitops/git-sync.sh" ''
      export TARGET_BRANCH="${config.targetBranch}"
      export ENV_NAME="${config.envName}"
      export RENDERED_MANIFESTS_PATH="${renderedManifests}"
      export GIT_BIN="${pkgs.git}/bin/git"
      set -- "http://$GIT_USER:$GIT_PASS@localhost:$GIT_PORT/$GIT_USER/manifests.git"
    '';
    helm-deps-update = mkScript "helm-deps-update" "gitops/helm-deps-update.sh" "";

    # --- Interactive Developer Layer ---
    up = mkScript "up" "local/up.sh" "";
    expose = mkScript "expose" "local/expose.sh" "";
    load-images = mkScript "load-images" "local/load-images.sh" "";
    sandbox-help = mkScript "sandbox-help" "local/sandbox-help.sh" "";
  };

  dependencies = [
    pkgs.minikube
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.argocd
    pkgs.git
    pkgs.curl
    pkgs.jq
    pkgs.just
  ];
}
