{
  description = "A Clojure Hello World API for Agentic Infra";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        # The environment for development (provides clojure + jdk)
        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.clojure pkgs.jdk ];
        };

        # The runner: 'nix run' starts the server
        packages.default = pkgs.writeShellScriptBin "git-mcp" ''
          ${pkgs.clojure}/bin/clojure -M -m git-mcp.core
        '';
      });
}