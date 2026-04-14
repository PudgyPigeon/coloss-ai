{
  description = "Minimal OpenClaw Agent Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # The official 2026 OpenClaw flake
    nix-openclaw.url = "github:openclaw/nix-openclaw";
  };

  outputs = { self, nixpkgs, nix-openclaw, ... }:
    let
      system = "x86_64-linux"; # Your Ryzen 9 architecture
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system} = {
        # The 'agent' shell for your Architect and Developer
        agent = pkgs.mkShell {
          buildInputs = [
            nix-openclaw.packages.${system}.default
            pkgs.nodejs_22
            pkgs.kubectl # So the agent can inspect your Minikube
          ];

          shellHook = ''
            # Isolated workspace to prevent the agent from wandering
            export OPENCLAW_WORKSPACE_DIR="$(pwd)/.openclaw-agents"
            
            # Point to your local 5080/SGLang
            export OPENAI_BASE_URL="http://localhost:30000/v1"
            export OPENAI_API_KEY="local-only"

            echo "🦞 OpenClaw Agent Shell Loaded"
            echo "Workspace: $OPENCLAW_WORKSPACE_DIR"
            
            if [ ! -d "$OPENCLAW_WORKSPACE_DIR" ]; then
              mkdir -p "$OPENCLAW_WORKSPACE_DIR"
            fi
          '';
        };

        # Your existing K8s Sandbox shell (imported)
        default = import ./shell.nix { inherit pkgs; };
      };
    };
}