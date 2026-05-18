{
  description = "Rootless Minikube devShell with Haskell MCP";

  inputs = {

    # External inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    just.url = "github:casey/just";

    # This repo's internal inputs / microservices / apps
    all-apps = {
      url = "path:./apps";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.just.follows = "just";
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , just
    , all-apps
    ,
    } @ inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        serviceApps = all-apps.apps.${system};
      in
      {
        # Automatically expose package defined in apps/flake.nix
        packages = all-apps.packages.${system};

        # Expose apps / binaries / executables
        apps = serviceApps;

        # Interactive shells
        devShells = {
          default = import ./shell.nix { inherit pkgs; };
        };

        # Formatting
        formatter = pkgs.nixpkgs-fmt;
      }
    );
}
