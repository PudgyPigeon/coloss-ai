{ pkgs }:
let
  # --- Configuration ---
  config = {
    clusterName = "sandbox-cluster";
    gitServiceName = "sandbox-gitea";
    gitPort = "3000";
    gitUser = "admin";
    gitPass = "placeholder";
    cpuCount = toString 4;
    memCount = toString 20000;
    nodeCount = toString 1;
    openWebUiDestPort = "9000";
    openWebUiSourcePort = "8080";
    argoCdNamespace = "argocd";
    argocdLocalPort = "8888";
    argocdSvcPort = "443";
  };

  # Import the platform module (Your Proprietary Platform)
  # This is now 100% independent of your nix/ folder
  platform = import ./platform {
    inherit pkgs config;
    helmSource = ./helm;
    imageLoadCommands = [
      "echo '🚀 Loading kubernetes-mcp...'; nix run ./apps#kubernetes-mcp-load && minikube image load kubernetes-mcp:latest"
      "echo '🚀 Loading don-erleone...'; nix run ./apps#don-erleone-load && minikube image load don-erleone:latest"
    ];
  };

in
pkgs.mkShell {
  buildInputs = platform.dependencies ++ (builtins.attrValues platform.scripts);
  # Note: It looks like it's not formatted correctly below but when you run 'nix develop' the box is lined up
  # so best left alone for aesthetics
  shellHook = ''
    export KUBECONFIG="$HOME/.kube/config"

    # Check if infra is actually up
    CLUSTER_STATUS=$(minikube status --format='{{.Host}}' 2>/dev/null | grep "Running" || true)

    echo -e "\n\033[1;36m┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \033[0m"
    if [[ -n "$CLUSTER_STATUS" ]]; then
        echo -e "\033[1;36m┃ 🚀 Sandbox Shell: \033[1;32mONLINE\033[1;36m                              ┃\033[0m"
        echo -e "\033[1;36m┃ ArgoCD: localhost:${config.argocdLocalPort}                                ┃\033[0m"
    else
        echo -e "\033[1;36m┃ 🚀 Sandbox Shell: \033[1;33mREADY TO START\033[1;36m                      ┃\033[0m"
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
