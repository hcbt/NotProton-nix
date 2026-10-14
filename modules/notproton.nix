{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.notproton;
  user = cfg.user;

  # All three apps install the nix-darwin way: environment.systemPackages
  # -> /Applications/Nix Apps. Nothing is copied to /Applications itself.
  # Two upstream constraints shape the glue in `config`:
  #
  # - NotProton patches Steam.app in place, which a read-only Nix Apps
  #   bundle refuses. The fleiks steam package is therefore pre-patched
  #   at build time (dylib + LSEnvironment insert, ad-hoc signed), and
  #   NotProton is pointed at the Nix Apps bundle via its steamAppPath
  #   user default; it recognises the pre-patched state and skips
  #   patching. Steam still self-updates, but into
  #   ~/Library/Application Support/Steam, not the bundle.
  # - NotProton only scans /Applications and ~/Applications for
  #   CrossOver, so the Nix Apps bundle is registered through its
  #   manualCrossOverPaths user default. It also clones CrossOver into
  #   ~/Library/Application Support/notproton/runners before patching
  #   the clone, and the clone inherits the source's permissions, so
  #   the Nix Apps copy is handed to the user writable below (its only
  #   job is to be a clone source; nix-darwin re-syncs it on switch).
  crossOverApp = "/Applications/Nix Apps/CrossOver.app";
  runnersDir = "/Users/${user}/Library/Application Support/notproton/runners";
in
{
  options.notproton = {
    enable = lib.mkEnableOption "Steam + CrossOver + NotProton (Steam Play on macOS)";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.system.primaryUser;
      defaultText = lib.literalExpression "config.system.primaryUser";
      description = ''
        User who owns the CrossOver clone source and whose home
        NotProton sets up (~/Library/Application Support/notproton).
      '';
    };

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "inputs.fleiks.packages.\${pkgs.stdenv.hostPlatform.system}.notproton";
      description = ''
        Package providing Applications/NotProton.app. Required, no
        default: NotProton is not in nixpkgs. fleiks provides it. The
        package is added to environment.systemPackages and installed by
        nix-darwin's applications mechanism (/Applications/Nix Apps).
      '';
    };

    steam.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "inputs.fleiks.packages.\${pkgs.stdenv.hostPlatform.system}.steam";
      description = ''
        Package providing Applications/Steam.app. Required, no default:
        nixpkgs' pkgs.steam is the Linux client and cannot be used on
        macOS. fleiks provides a macOS steam package, pre-patched for
        NotProton at build time. It is added to
        environment.systemPackages, installed by nix-darwin's
        applications mechanism (/Applications/Nix Apps), and NotProton
        is pointed at it via its steamAppPath user default.
      '';
    };

    crossover.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.crossover";
      description = ''
        Package providing Applications/CrossOver.app. Required, no
        default. nixpkgs' pkgs.crossover is the macOS app (26.3.0, the
        stable build NotProton supports) if you set it explicitly. The
        package is added to environment.systemPackages and installed by
        nix-darwin's applications mechanism (/Applications/Nix Apps);
        the module points NotProton at it via the manualCrossOverPaths
        user default, since NotProton only scans /Applications and
        ~/Applications itself.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
        message = "notproton: only aarch64-darwin is supported (NotProton and CrossOver are arm64-only).";
      }
      {
        assertion = cfg.package != null;
        message = ''
          notproton: notproton.package must be set. NotProton is not in
          nixpkgs; supply a package containing Applications/NotProton.app
          (e.g. fleiks' notproton package).'';
      }
      {
        assertion = cfg.steam.package != null;
        message = ''
          notproton: notproton.steam.package must be set. nixpkgs has no
          macOS Steam client (pkgs.steam is the Linux buildFHSEnv client),
          so supply a package containing Applications/Steam.app.'';
      }
      {
        assertion = cfg.crossover.package != null;
        message = ''
          notproton: notproton.crossover.package must be set (e.g.
          pkgs.crossover). Supply a package containing
          Applications/CrossOver.app.'';
      }
      {
        assertion = user != "";
        message = "notproton: notproton.user must name the user who owns Steam/CrossOver/NotProton state.";
      }
    ];

    warnings =
      lib.optional (cfg.crossover.package != null && lib.getVersion cfg.crossover.package != "26.3.0")
        ''
          notproton: crossover package is version ${lib.getVersion cfg.crossover.package}, not 26.3.0.
          NotProton pins supported CrossOver builds by loader hash and will refuse
          builds it does not know. 26.3.0 (nixpkgs pkgs.crossover) is the supported
          stable build; a CrossOver Preview package is fine if NotProton lists it.
        '';

    environment.systemPackages = [
      cfg.package
      cfg.crossover.package
      cfg.steam.package
    ];

    # CrossOver lands in /Applications/Nix Apps, outside the /Applications
    # and ~/Applications roots NotProton scans, and Steam must be the
    # pre-patched Nix Apps bundle, not NotProton's /Applications default;
    # point it at both through its own user defaults.
    system.defaults.CustomUserPreferences."com.notproton.NotProton" = {
      manualCrossOverPaths = [ crossOverApp ];
      steamAppPath = "/Applications/Nix Apps/Steam.app";
    };

    # nix-darwin builds the activate script from a fixed list of
    # activationScripts names; an arbitrary name (e.g. "notproton") is
    # evaluated but never interpolated into it and never runs.
    # postActivation is in that list, and its `text` is a lines type, so
    # this composes with other modules' postActivation definitions
    # instead of overriding them.
    system.activationScripts.postActivation.text = ''
      echo "notproton: setting up Steam, CrossOver and NotProton..."
      # NotProton clones CrossOver before patching the clone, and the
      # clone keeps the source's permissions. nix-darwin installs the
      # source read-only, so hand it to the user writable; also repair
      # any clone already made from the read-only copy.
      if [ -d "${crossOverApp}" ]; then
        chown -R ${user}:staff "${crossOverApp}"
        chmod -R u+w "${crossOverApp}"
      fi
      if [ -d "${runnersDir}" ]; then
        chmod -R u+w "${runnersDir}"
      fi
      # Apps are already in /Applications/Nix Apps (that script runs
      # first) and the user defaults are already written. --setup deploys
      # NotProton's files, clones and patches CrossOver, and sets it as
      # Steam's default compatibility tool. Activation is not required.
      setupApp="/Applications/Nix Apps/NotProton.app/Contents/MacOS/NotProtonApp"
      if [ -x "$setupApp" ]; then
        echo "notproton: running setup for ${user}"
        /bin/launchctl asuser "$(id -u ${user})" /usr/bin/sudo -u ${user} -- "$setupApp" --setup
      else
        echo "notproton: $setupApp is not installed, skipping setup" >&2
        exit 1
      fi
    '';
  };
}
