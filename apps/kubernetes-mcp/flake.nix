{
  description = "Haskell MCP Server - K8S Microservice";

  # Where to pull in pinned packages and tools from
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    just.url = "github:casey/just";
    ghciwatch.url = "github:MercuryTechnologies/ghciwatch";
  };

  # The artifacts produces by nix commands
  outputs =
    { self
    , nixpkgs
    , flake-utils
    , just
    , ghciwatch
    ,
    }:
    # Allow artifacts to work on different architectures
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        hpkgs = pkgs.haskell.packages.ghc912;

        # Define the Haskell package
        # callCabal2nix looks at your .cabal file to determine dependencies
        haskellPkg = hpkgs.callCabal2nix "kubernetes-mcp" ./. { };

        # 2. Add system-level modifiers (like pkg-config or zlib)
        haskellPkgFinal = pkgs.haskell.lib.overrideCabal haskellPkg (drv: {
          executableSystemDepends = [
            pkgs.zlib
            pkgs.pkg-config
          ];
        });
      in
      {
        # Formatting
        formatter = pkgs.nixpkgs-fmt; #pkgs.alejandra;

        # Define the default package (nix build)
        packages.default = haskellPkgFinal;

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
