{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.notproton;
  user = cfg.user;

  # CrossOver and NotProton are immutable payloads, so they install the
  # nix-darwin way: environment.systemPackages -> /Applications/Nix Apps.
  # Steam is the one exception. NotProton patches Steam.app in place
  # (dylib copy, Info.plist edit, ad-hoc re-sign) and Steam self-updates
  # inside its bundle, so Steam must be a real, user-owned, writable copy
  # in /Applications; nix-darwin's read-only rsync copies fail both.
  installSteam = src: ''
    srcApp="${src}/Applications/Steam.app"
    dstApp="/Applications/Steam.app"
    if [ ! -d "$srcApp" ]; then
      echo "notproton: $srcApp not found; the package must contain Applications/Steam.app" >&2
      exit 1
    fi
    # Steam self-updates inside its bundle and NotProton patches it;
    # never overwrite an installed copy.
    if [ -d "$dstApp" ]; then
      echo "notproton: $dstApp already present, leaving it alone"
    else
      echo "notproton: installing Steam.app to /Applications"
      cp -R "$srcApp" "$dstApp"
      chown -R ${user}:staff "$dstApp"
      chmod -R u+w "$dstApp"
    fi
    # An in-place bundle change (Steam self-update, NotProton re-sign)
    # leaves LaunchServices holding the old bundle's registration, and
    # launchd then kills the app with "Taskgated Invalid Signature" even
    # though codesign verifies. Re-registering on every activation
    # repairs that state.
    /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$dstApp" || true
  '';
in
{
  options.notproton = {
    enable = lib.mkEnableOption "Steam + CrossOver + NotProton (Steam Play on macOS)";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.system.primaryUser;
      defaultText = lib.literalExpression "config.system.primaryUser";
      description = ''
        User who owns the /Applications app copies and whose home
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
        macOS. fleiks provides a macOS steam package. The package must
        contain a real Steam.app; it is copied to /Applications once and
        then left to Steam's self-updater and NotProton's patcher.
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

    # nix-darwin builds the activate script from a fixed list of
    # activationScripts names; an arbitrary name (e.g. "notproton") is
    # evaluated but never interpolated into it and never runs.
    # postActivation is in that list, and its `text` is a lines type, so
    # this composes with other modules' postActivation definitions
    # instead of overriding them.
    environment.systemPackages = [
      cfg.package
      cfg.crossover.package
    ];

    # CrossOver lands in /Applications/Nix Apps, outside the /Applications
    # and ~/Applications roots NotProton scans; register it through its
    # manualCrossOverPaths user default instead.
    system.defaults.CustomUserPreferences."com.notproton.NotProton" = {
      manualCrossOverPaths = [ "/Applications/Nix Apps/CrossOver.app" ];
    };

    system.activationScripts.postActivation.text = ''
      echo "notproton: setting up Steam, CrossOver and NotProton..."
      ${installSteam cfg.steam.package}
    '';
  };
}
