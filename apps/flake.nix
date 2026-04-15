{
  description = "Apps/Internal Microservices Aggregator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    just.url = "github:casey/just";
    nix2container.url = "github:nlewo/nix2container";

    # Microservice #1
    kubernetes-mcp = {
      url = "path:./kubernetes-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.just.follows = "just";
      inputs.nix2container.follows = "nix2container";
    };
  };

  # The '@ inputs' allows the let block to see 'inputs.kubernetes-mcp-src'
  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # pkgs = import nixpkgs { inherit system; };
        inherit (nixpkgs) lib;

        # Converts a sub-flake input into a standard set of artifacts
        mkAppBundle = name: input: {
          packages = {
            "${name}" = input.packages.${system}.default;
            "${name}-image" = input.packages.${system}.image;
          };
          apps = {
            # Each function call creates two apps: one raw binary and one docker loading operation for image
            "${name}" = input.apps.${system}.default;
            "${name}-load" = {
              type = "app";
              # Accessing the binary via the package is safer than relying on sub-flake app structures
              program = "${input.packages.${system}.image.copyToDockerDaemon}/bin/copy-to-docker-daemon";
            };
          };
        };

        # Generate bundles for every microservice
        bundles = [
          (mkAppBundle "kubernetes-mcp" self.inputs.kubernetes-mcp)
        ];
        # When you add a second app, just add a line like this:
        # ghBundle = mkAppBundle "github-mcp" inputs.github-mcp-src;
      in
      {
        # Merge all 'packages' attributes from every bundle in the list
        # Merge all 'apps' attributes from every bundle in the list
        packages = lib.attrsets.mergeAttrsList (map (b: b.packages) bundles);
        apps = lib.attrsets.mergeAttrsList (map (b: b.apps) bundles);
      }
    );
}
