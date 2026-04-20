{
  description = "Erlang Orchestrator - Supervised Agent Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
    just.url = "github:casey/just";
    nix-rebar3 = {
      url = "github:axelf4/nix-rebar3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, nix2container, just, nix-rebar3, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        rebar3Lib = nix-rebar3.lib.${system};
        n2c = nix2container.packages.${system}.nix2container;

        appName = "erlang-orchestrator";
        otpName = "hello_api"; 
        version = "0.1.0";

        erlApp = rebar3Lib.buildRebar3 {
          pname = appName;
          inherit version;
          root = ./.;
          releaseType = "release";
          profile = "prod";

          # Prevents Nix from auditing internal Rebar3 symlinks
          singleStep = true;
          dontFixup = true;

          preInstall = ''
            export HOME=$TEMPDIR
          '';

          postInstall = ''
            if [ -f "$out/bin/${otpName}" ]; then
              ln -s "$out/bin/${otpName}" "$out/bin/${appName}"
            fi
          '';
        };

        containerImage = n2c.buildImage {
          name = appName;
          tag = "latest";
          config = {
            Entrypoint = [ "${erlApp}/bin/${appName}" "foreground" ];
            WorkingDir = "/tmp";
            user = "1000";
          };
        };

        run-foreground-binary = pkgs.writeShellScriptBin "run-foreground-binary" ''
          exec ${erlApp}/bin/${appName} foreground "$@"
        '';
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        packages = {
          default = erlApp;
          image = containerImage;
        };

        apps = {
          default = {
            type = "app";
            program = "${run-foreground-binary}/bin/run-foreground-binary";
          };
          load-image = {
            type = "app";
            program = "${containerImage.copyToDockerDaemon}/bin/copy-to-docker-daemon";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.beam.packages.erlang_27.erlang
            pkgs.beam.packages.erlang_27.rebar3
            pkgs.beam.packages.erlang_27.erlfmt
            pkgs.inotify-tools
            pkgs.just
          ];

          shellHook = ''
            export REBAR3_CACHE_DIR=$PWD/.nix-rebar3
            export PATH=$PWD/_build/default/bin:$PATH

            echo "--- ${appName} Dev Shell (OTP 27) ---"
          '';
        };
      });
}