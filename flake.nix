{
  description = "nix-darwin module managing Steam, CrossOver and NotProton (Steam Play on macOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Only used by this repo's checks; consumers bring their own nix-darwin.
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Evaluation fixture: stand-in packages (the module requires all
      # three to be set explicitly) so the eval path can be checked.
      dummyApp =
        name: app:
        pkgs.stdenvNoCC.mkDerivation {
          inherit name;
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/Applications/${app}/Contents
            echo test > $out/Applications/${app}/Contents/Info.plist
          '';
        };

      testConfig = nix-darwin.lib.darwinSystem {
        inherit system;
        modules = [
          self.darwinModules.default
          {
            system.stateVersion = 6;
            system.primaryUser = "notproton-test";
            notproton = {
              enable = true;
              package = dummyApp "notproton-test" "NotProton.app";
              steam.package = dummyApp "steam-test" "Steam.app";
              crossover.package = dummyApp "crossover-test" "CrossOver.app";
            };
          }
        ];
      };
    in
    {
      darwinModules.default = ./modules/notproton.nix;

      checks.${system} = {
        # Forces full module evaluation (options, assertions, activation
        # script) without realising the app packages.
        module-eval =
          pkgs.runCommand "notproton-module-eval"
            {
              activation = builtins.unsafeDiscardStringContext (
                testConfig.config.system.activationScripts.notproton.text
              );
              assertions = builtins.toJSON (map (a: a.assertion) testConfig.config.assertions);
            }
            ''
              grep -q "installing Steam/CrossOver/NotProton" <<< "$activation"
              grep -q "Steam.app" <<< "$activation"
              grep -q "CrossOver.app" <<< "$activation"
              grep -q "NotProton.app" <<< "$activation"
              if grep -q "false" <<< "$assertions"; then
                echo "module assertions failed: $assertions" >&2
                exit 1
              fi
              touch $out
            '';
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
