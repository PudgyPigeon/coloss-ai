{
  description = "Refactored Swarm Deck Development Shell & Platform Engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    just.url = "github:casey/just";

    all-apps = {
      url = "path:./apps";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.just.follows = "just";
    };
  };

  outputs = { self, nixpkgs, flake-utils, all-apps, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        serviceApps = all-apps.apps.${system};
      in
      {
        # Expose app derivations
        packages = all-apps.packages.${system};

        # Expose CLI binaries
        apps = serviceApps;

        # Development Environment
        devShells = {
          default = import ./shell.nix {
            inherit pkgs;
            envName = "sandbox";
            targetBranch = "sandbox";
          };
          prod = import ./shell.nix {
            inherit pkgs;
            envName = "prod";
            targetBranch = "main";
          };
        };

        # Automatic Code Formatter
        formatter = pkgs.nixpkgs-fmt;
      }
    );
}
