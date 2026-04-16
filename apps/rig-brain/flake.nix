{
  description = "Rig Agentic Brain — High-performance Rust orchestrator";

  # Where to pull in pinned packages and tools from
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
    just.url = "github:casey/just";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # The artifacts produces by nix commands
  outputs =
    { self
    , nixpkgs
    , rust-overlay
    , flake-utils
    , nix2container
    , just
    , crane
    , ...
    } @ inputs:
    # Allow artifacts to work on different architectures
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        n2c = nix2container.packages.${system}.nix2container;

        # Use a specific Rust toolchain (stable)
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };

        # Initialize craneLib with the custom toolchain
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        # Common build arguments for Crane
        commonArgs = {
          pname = "rig-brain";
          version = "0.1.0";
          src = craneLib.cleanCargoSource ./.;
          strictDeps = true;

          # System libraries needed at runtime/link time.
          buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk.frameworks; [
            Security
            SystemConfiguration
            CoreFoundation
          ]);
        };

        # 2. Build just the dependencies to maximize caching
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        # 3. Define the Rust Package (the actual app) using Crane
        rigBrainPkg = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
        });

        # Define the Container Image
        containerImage = n2c.buildImage {
          name = "rig-brain";
          tag = "latest";

          # Use a layer for static/heavy dependencies to speed up rebuilds
          layers = [
            (n2c.buildLayer {
              deps = [
                pkgs.cacert
                pkgs.fakeNss
              ];
            })
          ];

          copyToRoot = [
            rigBrainPkg
          ];

          config = {
            # Use Entrypoint so it's "locked" as the binary
            Entrypoint = [ "${rigBrainPkg}/bin/rig-brain" ];
            WorkingDir = "/tmp";
            User = "1000";
            Env = [
              "PATH=${rigBrainPkg}/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

      in
      {
        # Formatting
        formatter = pkgs.nixpkgs-fmt;

        # Define the default package (nix build)
        packages = {
          default = rigBrainPkg;
          image = containerImage;
        };

        # Define the default app (nix run)
        apps = {
          default = {
            type = "app";
            program = "${rigBrainPkg}/bin/rig-brain";
          };
        };

        # Define nix develop shell
        devShells.default = pkgs.mkShell {
          # Use inputsFrom to ensure all dependencies of the package 
          # are automatically available in the shell
          inputsFrom = [ rigBrainPkg ];

          buildInputs = [
            # Orchestration & Task Running
            just.packages.${system}.default

            # Rust Development & Watchers
            pkgs.cargo-watch
            pkgs.cargo-edit      # Adds `cargo add`, `cargo rm` commands
            pkgs.cargo-audit     
            pkgs.cargo-deny     
            
            # Profiling & Performance (Rust equivalents to eventlog2html)
            pkgs.samply          
          ];
          
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