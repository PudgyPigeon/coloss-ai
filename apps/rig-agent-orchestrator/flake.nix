{
  description = "Rig Agentic Brain — High-performance Rust orchestrator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils, nix2container }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };
        n2c = nix2container.packages.${system}.nix2container;

        # Use a specific Rust toolchain (stable)
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };

        # Dependencies needed just for building
        nativeBuildInputs = with pkgs; [ 
          rustToolchain 
          just
          cargo-watch
        ];

        # System libraries needed at runtime/link time.
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk.frameworks; [
          Security
          SystemConfiguration
          CoreFoundation
        ]);

        # The actual Rust Application
        rigBrainPkg = pkgs.rustPlatform.buildRustPackage {
          pname = "rig-brain";
          version = "0.1.0";
          src = ./.; # Assumes Cargo.toml is in the root

          cargoLock = {
            lockFile = ./Cargo.lock;
            allowBuiltinFetchGit = true;
          };

          nativeBuildInputs = nativeBuildInputs;
          buildInputs = buildInputs;
        };

        # Minimal container image using nix2container builder
        containerImage = n2c.buildImage {
          name = "rig-brain";
          tag = "latest";

          copyToRoot = [
            pkgs.cacert # Required for doing HTTPS requests to K8s/LLMs
          ];

          config = {
            Cmd = [ "${rigBrainPkg}/bin/rig-brain" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

      in
      {
        packages = {
          default = rigBrainPkg;
          image = containerImage;
        };

        apps = {
          default = {
            type = "app";
            program = "${rigBrainPkg}/bin/rig-brain";
          };
          # This app is specifically for loading the image into the local Docker daemon
          # It's what 'just load-image' calls
          load-image = {
            type = "app";
            program = "${containerImage.copyToDockerDaemon}/bin/copy-to-docker-daemon";
          };
        };

        devShells.default = pkgs.mkShell {
          inherit buildInputs nativeBuildInputs;
          shellHook = ''
            echo -e "\n\033[1;36m┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\033[0m"
            echo -e "\033[1;36m┃ 🤖 Rig Agentic Brain: \033[1;32mDEVELOPMENT SHELL\033[1;36m               ┃\033[0m"
            echo -e "\033[1;36m┃ Rust: $(rustc --version | cut -d' ' -f2)                                          ┃\033[0m"
            echo -e "\033[1;36m┃ Cargo: $(cargo --version | cut -d' ' -f2)                                         ┃\033[0m"
            echo -e "\033[1;36m┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m\n"
            
            # Setup environment
            export OPENAI_API_KEY="your-key-here"
            
            echo -e "\033[1;33mTip:\033[0m Run '\033[1;32mcargo run\033[0m' to start the orchestrator."
            echo -e "\033[1;33mTip:\033[0m Use '\033[1;32mnix run .#load-image\033[0m' to build/load the container.\n"
          '';
        };
      }
    );
}