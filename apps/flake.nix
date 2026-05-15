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
    # Agentic Brain
    don-erleone = {
      url = "path:./don-erleone";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.just.follows = "just";
      inputs.nix2container.follows = "nix2container";
    };
    # The Wire - Dashboard for Agents
    wire = {
      url = "path:./wire";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.just.follows = "just";
      inputs.nix2container.follows = "nix2container";
    };
  };

  # The '@ inputs' allows the let block to see 'inputs.kubernetes-mcp-src'
  outputs = { self, nixpkgs, flake-utils, ... }@ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        inherit (nixpkgs) lib;

        # Converts a sub-flake input into a standard set of artifacts
        mkAppBundle = name: input:
          let
            # input = self.inputs.${name};
            pkgs = input.packages.${system};
            apps = input.apps.${system};
          in
          {
            packages = {
              "${name}" = pkgs.default;
              "${name}-image" = pkgs.image;
            };
            apps = {
              "${name}" = apps.default // {
                meta.description = "The binary application for ${name}";
              };
              "${name}-load" = {
                type = "app";
                program = "${pkgs.image.copyToDockerDaemon}/bin/copy-to-docker-daemon";
                meta.description = "Build and load the OCI image for ${name} into the local Docker daemon";
              };
            };
          };
        # Generate bundles for every microservice
        # serviceNames = [ "kubernetes-mcp" "don-erleone" "wire" ];
        # bundles = map mkAppBundle serviceNames;
        bundles = [
          (mkAppBundle "kubernetes-mcp" inputs.kubernetes-mcp)
          (mkAppBundle "don-erleone" inputs.don-erleone)
          (mkAppBundle "wire" inputs.wire)
        ];
      in
      {
        # Merge all 'packages' attributes from every bundle in the list
        # Merge all 'apps' attributes from every bundle in the list
        packages = lib.attrsets.mergeAttrsList (map (b: b.packages) bundles);
        apps = lib.attrsets.mergeAttrsList (map (b: b.apps) bundles);
      }
    );
}
