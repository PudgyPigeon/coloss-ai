{
  description = "The Wire - Supervised Agent Dashboard (Phoenix)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
    just.url = "github:casey/just";
  };

  outputs = { self, nixpkgs, flake-utils, nix2container, just, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        n2c = nix2container.packages.${system}.nix2container;
        beamPkgs = pkgs.beam.packagesWith pkgs.erlang_28;
        elixir = beamPkgs.elixir_1_19;

        pname = "wire";
        version = "0.0.1";
        src = ./.;

        # 1. The Phoenix Release
        elixirApp = beamPkgs.mixRelease {
          inherit pname version src;
          elixir = elixir;

          mixFodDeps = beamPkgs.fetchMixDeps {
            pname = "${pname}-deps";
            inherit version src;
            hash = "sha256-Xz6yqsCpu2ZkFdV+OwLnPaiBhes4M8/gw74/TIQ/ABs=";
          };

          buildInputs = [ elixir ];
          nativeBuildInputs = [ pkgs.cmake ];

          installPhase = ''
            mix do compile, release --path $out
          '';

          meta = with pkgs.lib; {
            description = "The Wire: Agentic Swarm Dashboard";
            platforms = platforms.unix;
          };
        };

        # 2. The Runner Script (Standardized for K8s/Distributed BEAM)
        run-script = pkgs.writeShellScriptBin "${pname}-runner" ''
          set -e

          # Standardize mutable paths
          export LANG=C.UTF-8
          export LC_ALL=C.UTF-8
          export RELEASE_TMP=''${RELEASE_TMP:-/tmp}
          export RELX_OUT_FILE_PATH=''${RELX_OUT_FILE_PATH:-/tmp}
          export RELEASE_NODE=''${RELEASE_NODE:-wire@127.0.0.1}
          export RELEASE_COOKIE=''${RELEASE_COOKIE:-agentic_brain_secret}

          # Start EPMD using the stripped binary bundled inside the release
          echo "=> Starting EPMD..."
          EPMD_BIN=$(find ${elixirApp} -path "*/erts-*/bin/epmd" | head -n 1)
          
          if [ -x "$EPMD_BIN" ]; then
              "$EPMD_BIN" -daemon || true
          else
              echo "=> Warning: Bundled epmd not found."
          fi

          # Boot the app
          COMMAND=''${1:-start}
          shift || true
          echo "=> Booting ${pname}..."
          exec ${elixirApp}/bin/${pname} "$COMMAND" "$@"
        '';

        # 3. The Container Image
        containerImage = n2c.buildImage {
          name = pname;
          tag = "latest";

          layers = [
            (n2c.buildLayer {
              deps = [ 
                (pkgs.busybox.override { enableAppletSymlinks = true; })
                pkgs.glibc
                elixirApp 
              ];
            })
          ];

          config = {
            Entrypoint = [ "${run-script}/bin/${pname}-runner" ];
            Env = [
              "PHX_SERVER=true"
              "HOME=/tmp"
              "PATH=${pkgs.busybox}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:/usr/local/bin:/usr/bin:/bin"
            ];
          };
        };

        # 4. The Development Shell
        elixirDevShell = pkgs.mkShell {
          buildInputs = [
            elixir
            pkgs.inotify-tools
            pkgs.just
          ];
          shellHook = ''
            export ELIXIR_ERL_OPTIONS="+fnu"
            export MIX_ENV=dev
            export MIX_HOME=$PWD/.nix-mix
            export HEX_HOME=$PWD/.nix-hex
            export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
            export ERL_AFLAGS="-kernel shell_history enabled"
            
            # ANSI Colors for that SRE aesthetic
            echo -e "\033[1;36m--- Phoenix Dashboard Shell Ready ---\033[0m"
          '';
        };

      in
      {
        formatter = pkgs.nixpkgs-fmt;

        packages = {
          default = elixirApp;
          image = containerImage;
        };

        apps = {
          default = {
            type = "app";
            program = "${run-script}/bin/${pname}-runner";
          };
          load-image = {
            type = "app";
            program = "${containerImage.copyToDockerDaemon}/bin/copy-to-docker-daemon";
          };
        };

        devShells.default = elixirDevShell;
      });
}