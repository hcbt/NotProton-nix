{
  description = "nix-darwin module managing Steam, CrossOver and NotProton (Steam Play on macOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    fleiks = {
      url = "github:hcbt/fleiks";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
      fleiks,
      nix-darwin,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Evaluation fixture: a stand-in Steam package (nixpkgs has no macOS
      # Steam client) so the module's eval path can be checked.
      testConfig = nix-darwin.lib.darwinSystem {
        inherit system;
        modules = [
          self.darwinModules.default
          {
            nixpkgs.config.allowUnfree = true; # CrossOver, for the fixture
            system.stateVersion = 6;
            system.primaryUser = "notproton-test";
            notproton = {
              enable = true;
              steam.package = pkgs.stdenvNoCC.mkDerivation {
                name = "steam-test";
                dontUnpack = true;
                installPhase = ''
                  mkdir -p $out/Applications/Steam.app/Contents
                  echo test > $out/Applications/Steam.app/Contents/Info.plist
                '';
              };
            };
          }
        ];
      };
    in
    {
      darwinModules.default = {
        imports = [ ./modules/notproton.nix ];

        # Provides pkgs.notproton (notproton.package's default).
        nixpkgs.overlays = [ fleiks.overlays.default ];
      };

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
