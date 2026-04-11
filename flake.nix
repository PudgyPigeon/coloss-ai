{
  description = "Rootless k3s devShell with Rust agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      repoApps = import ./nix/apps.nix {inherit pkgs;};
    in {
      apps = repoApps.all;
      devShells = {
        default = import ./shell.nix {inherit pkgs;};
      };
      formatter = pkgs.alejandra;
    });
}
