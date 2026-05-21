{ pkgs, envName ? "sandbox", targetBranch ? "sandbox" }:
let
  # --- Central Sandbox Specification ---
  config = {
    clusterName = "${envName}-cluster";
    gitServiceName = "${envName}-gitea";
    gitPort = "3000";
    gitUser = "admin";
    gitPass = "placeholder";
    cpuCount = "4";
    memCount = "20000";
    nodeCount = "1";
    openWebUiDestPort = "9000";
    openWebUiSourcePort = "8080";
    argoCdNamespace = "argocd";
    argocdLocalPort = "8888";
    argocdSvcPort = "443";
    wireLocalPort = "4000";
    wireSvcPort = "4000";
    targetBranch = targetBranch;
    envName = envName;
  };

  # --- Application Container Split-Loaders ---
  swarmApps = {
    kubernetes-mcp-load = "kubernetes-mcp";
    don-erleone-load = "don-erleone";
    wire-load = "wire";
  };

  mkLoadCommand = attr: img:
    "echo '🚀 Re-building ${img} derivation...'; " +
    "nix run ./apps#${attr} && " +
    "kubectl delete deployment --all -n ${img} --ignore-not-found=true && " +
    "echo '🚀 Injecting OCI layer ${img} into Minikube...'; " +
    "minikube image load ${img}:latest --overwrite=true";

  # --- Platform Imports ---
  platform = import ./platform {
    inherit pkgs config;
    helmSource = ./helm;
    imageLoadCommands = pkgs.lib.mapAttrsToList mkLoadCommand swarmApps;
  };

in
pkgs.mkShell {
  buildInputs = platform.dependencies ++ (builtins.attrValues platform.scripts);

  shellHook = ''
    export KUBECONFIG="$HOME/.kube/config"

    # Inspect Minikube hypervisor lifecycle state
    CLUSTER_STATUS=$(minikube status --format='{{.Host}}' 2>/dev/null | grep "Running" || true)

    echo -e "\n\033[1;36m┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \033[0m"
    if [[ -n "$CLUSTER_STATUS" ]]; then
        echo -e "\033[1;36m┃ 🚀 ${config.envName} Shell: \033[1;32mONLINE\033[1;36m                              ┃\033[0m"
        echo -e "\033[1;36m┃ ArgoCD: localhost:${config.argocdLocalPort}                                ┃\033[0m"
    else
        echo -e "\033[1;36m┃ 🚀 ${config.envName} Shell: \033[1;33mREADY TO START\033[1;36m                      ┃\033[0m"
    fi
    echo -e "\033[1;36m┃ Run '\033[1;32mup\033[1;36m' to provision your local infrastructure.      ┃\033[0m"
    echo -e "\033[1;36m┃ Type '\033[1;33msandbox-help\033[1;36m' to see available commands.        ┃\033[0m"
    echo -e "\033[1;36m┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m\n"

    alias k="kubectl"
    alias s-help="sandbox-help"

    if command -v kubectl >/dev/null; then
      source <(kubectl completion bash | sed 's/kubectl/k/g')
    fi
  '';
}
