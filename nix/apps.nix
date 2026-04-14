{ pkgs }:
let
  # Import the CI apps defined in ci.nix
  ci = import ./ci.nix { inherit pkgs; };

  # Local utility apps for sandbox development
  utils = {
    "cluster-info" = {
      type = "app";
      program =
        (pkgs.writeShellScriptBin "cluster-info" ''
          echo "☸️  Kubernetes Cluster Info:"
          ${pkgs.kubectl}/bin/kubectl cluster-info
          echo ""
          echo "📦 Local Kind Clusters:"
          ${pkgs.kind}/bin/kind get clusters
        '').outPath
        + "/bin/cluster-info";
    };
  };
in
{
  # Standardized attribute names for Flake consumption
  inherit ci utils;

  # A convenience attribute containing everything
  all = ci // utils;
}
