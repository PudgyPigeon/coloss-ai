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

        # # Haskell Packaging Logic
        # haskellVersion = pkgs.haskell.packages.ghc910;
        # haskellPkg = haskellVersion.developPackage {
        #   root = ./.;
        #   modifier = drv:
        #     pkgs.haskell.lib.addBuildTools drv [
        #       pkgs.zlib
        #       pkgs.pkg-config
        #     ];
        # };
      in
      {
        # Formatting
        formatter = pkgs.nixpkgs-fmt; #pkgs.alejandra;

        # Packages and Apps
        # packages.default = haskellPkg;
        # apps.default = {
        #   type = "app";
        #   program = "${haskellPkg}/bin/k8s-mcp";
        # };

        # Inline shell logic
        # Defines `nix develop`
        devShells.default = pkgs.mkShell {
          # inputsFrom = [ haskellPkg ];
          buildInputs = with pkgs.haskellPackages; [
            # Haskell Tooling
            hpkgs.ghc
            hpkgs.cabal-install
            hpkgs.haskell-language-server
            hpkgs.ghcid
            # Custom input -> output
            just.packages.${system}.default
            ghciwatch.packages.${system}.default
            # System Tools/NixPkgs
            pkgs.zlib
            pkgs.pkg-config
          ];
        };
      }
    );
}
