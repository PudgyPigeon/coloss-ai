{
  description = "Haskell MCP Server - K8S Microservice";

  # Where to pull in pinned packages and tools from
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
    just.url = "github:casey/just";
    ghciwatch.url = "github:MercuryTechnologies/ghciwatch";
    mcp-server-src = {
      url = "github:drshade/haskell-mcp-server";
      flake = false;
    };
  };

  # The artifacts produces by nix commands
  outputs =
    { self
    , nixpkgs
    , flake-utils
    , nix2container
    , just
    , ghciwatch
    , mcp-server-src
    , ...
    } @ inputs:
    # Allow artifacts to work on different architectures
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        n2c = nix2container.packages.${system}.nix2container;

        # Override the Haskell package set with latest mcp-server from GitHub
        hpkgs = pkgs.haskell.packages.ghc912.override {
          overrides = self: super: {
            mcp-server = self.callCabal2nix "mcp-server" mcp-server-src { };
          };
        };

        # Define the Haskell package
        # callCabal2nix looks at your .cabal file to determine dependencies
        haskellPkg = hpkgs.callCabal2nix "kubernetes-mcp" ./. { };

        # Add system-level modifiers (like pkg-config or zlib)
        haskellPkgFinal = pkgs.haskell.lib.overrideCabal haskellPkg (drv: {
          executableSystemDepends = [
            pkgs.zlib
            pkgs.pkg-config
          ];
        });

        # Define the Container Image
        containerImage = n2c.buildImage {
          name = "kubernetes-mcp";
          tag = "latest";

          # Use a layer for static/heavy dependencies to speed up rebuilds
          layers = [
            (n2c.buildLayer {
              deps = [ pkgs.kubectl pkgs.zlib pkgs.cacert ];
            })
          ];

          config = {
            # Use Entrypoint so it's "locked" as the binary
            Entrypoint = [ "${pkgs.haskell.lib.justStaticExecutables haskellPkgFinal}/bin/kubernetes-mcp" ];
            # Optional: You can put default Cmd here, but Helm args will override them
            Cmd = [];
            WorkingDir = "/tmp";
            User = "1000";
            Env = [
              "PATH=${pkgs.kubectl}/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

      in
      {
        # Formatting
        formatter = pkgs.nixpkgs-fmt; #pkgs.alejandra;

        # Define the default package (nix build)
        packages = {
          default = haskellPkgFinal;
          image = containerImage;
        };

        # Define the default app (nix run)
        apps.default = {
          type = "app";
          program = "${haskellPkgFinal}/bin/kubernetes-mcp";
        };

        # Define nix develop shell
        devShells.default = pkgs.mkShell {
          # Use inputsFrom to ensure all dependencies of the package 
          # are automatically available in the shell
          inputsFrom = [ haskellPkgFinal ];

          buildInputs = with pkgs.haskellPackages; [
            # Development Tooling
            hpkgs.cabal-install
            hpkgs.haskell-language-server
            hpkgs.ghcid
            hpkgs.fourmolu
            hpkgs.hlint
            hpkgs.apply-refact
            hpkgs.eventlog2html

            # Kubernetes CLI (required at runtime for kubectl subprocess calls)
            pkgs.kubectl

            # Profiling & Performance
            hpkgs.eventlog2html # Visualizing K8S MCP performance

            # External Flake Tools
            just.packages.${system}.default
            ghciwatch.packages.${system}.default
          ];

          shellHook = ''
            echo "--- Kubernetes MCP Development Environment ---"
            echo "Compiler: $(ghc --version)"
            echo "Tools available: fourmolu, hlint, eventlog2html, just"
          '';
        };
      }
    );
}
