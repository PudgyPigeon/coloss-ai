{ pkgs, config, helmSource, imageLoadCommands ? [ ] }:

let
  # --- The Rendering Engine ---
  renderedManifests = pkgs.runCommand "rendered-manifests-sandbox"
    {
      nativeBuildInputs = [ pkgs.kubernetes-helm ];
      TIER_NAMES = "mgmt infra apps";
      TIER_MAPPINGS = "mgmt:${helmSource}/mgmt infra:${helmSource}/infra apps:${helmSource}/apps";
      ENV_VALUES_DIR = "${helmSource}/values/sandbox";
    }
    (builtins.readFile ./scripts/gitops/render-manifests.sh);

  # --- Helper: mkScript ---
  mkScript = name: file: extraBash: pkgs.writeShellScriptBin name ''
    # --- Project-Specific Config ---
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

    # --- Portability Config ---
    export HELM_SOURCE_PATH="${helmSource}"
    export IMAGE_LOAD_COMMANDS="${pkgs.lib.concatStringsSep "\n" imageLoadCommands}"

    # --- Extra Logic ---
    ${extraBash}

    # --- Script Body ---
    ${builtins.readFile ./scripts/${file}}
  '';

in
{
  scripts = {
    # Infrastructure Layer
    argocd-creds = mkScript "argocd-creds" "mgmt/argocd-creds.sh" "";
    gitea-up = mkScript "gitea-up" "infra/gitea-up.sh" "";
    minikube-up = mkScript "minikube-up" "infra/minikube-up.sh" "";
    infra-up = mkScript "infra-up" "infra/infra-up.sh" "";

    # Management Layer
    argocd-up = mkScript "argocd-up" "mgmt/argocd-up.sh" "";

    # GitOps Layer
    sync-helm = mkScript "sync-helm" "gitops/git-sync.sh" ''
      export TARGET_BRANCH="sandbox"
      export ENV_NAME="sandbox"
      export RENDERED_MANIFESTS_PATH="${renderedManifests}"
      export GIT_BIN="${pkgs.git}/bin/git"
      set -- "http://$GIT_USER:$GIT_PASS@localhost:$GIT_PORT/$GIT_USER/manifests.git"
    '';

    helm-deps-update = mkScript "helm-deps-update" "gitops/helm-deps-update.sh" "";

    # Developer UX Layer
    expose = mkScript "expose" "local/expose.sh" "";
    up = mkScript "up" "local/up.sh" "";
    down = mkScript "down" "infra/down.sh" "";
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
