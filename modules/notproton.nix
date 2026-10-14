{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.notproton;
  user = cfg.user;
  home = "/Users/${user}";

  # NotProton patches Steam.app in place (dylib copy, Info.plist edit,
  # ad-hoc re-sign) and discovers CrossOver only under /Applications or
  # ~/Applications, so all three apps must land as real, user-owned,
  # writable copies in /Applications -- Nix store symlinks do not work.
  installApp = src: app: mode: ''
    srcApp="${src}/Applications/${app}"
    dstApp="/Applications/${app}"
    if [ ! -d "$srcApp" ]; then
      echo "notproton: $srcApp not found; the package must contain Applications/${app}" >&2
      exit 1
    fi
    ${
      if mode == "if-absent" then
        # Steam self-updates inside its bundle and NotProton patches it;
        # never overwrite an installed copy.
        ''
          if [ -d "$dstApp" ]; then
            echo "notproton: $dstApp already present, leaving it alone"
          else
            echo "notproton: installing ${app} to /Applications"
            cp -R "$srcApp" "$dstApp"
            chown -R ${user}:staff "$dstApp"
            chmod -R u+w "$dstApp"
          fi
        ''
      else
        # Replace only when the bundle version changes.
        ''
          srcVer=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$srcApp/Contents/Info.plist" 2>/dev/null || echo none)
          dstVer=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$dstApp/Contents/Info.plist" 2>/dev/null || echo none)
          if [ "$srcVer" = "$dstVer" ] && [ -d "$dstApp" ]; then
            echo "notproton: ${app} $srcVer already installed"
          else
            echo "notproton: installing ${app} $srcVer to /Applications (was: $dstVer)"
            rm -rf "$dstApp"
            cp -R "$srcApp" "$dstApp"
            chown -R ${user}:staff "$dstApp"
            chmod -R u+w "$dstApp"
          fi
        ''
    }
    # Steam self-updates inside its bundle and NotProton re-signs it, both
    # after this script runs; CrossOver/NotProton are replaced wholesale.
    # Any in-place bundle change leaves LaunchServices holding the old
    # bundle's registration, and launchd then kills the app with
    # "Taskgated Invalid Signature" even though codesign verifies.
    # Re-registering on every activation repairs that state.
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
        package must contain a real NotProton.app; it is copied to
        /Applications and replaced when its bundle version changes.
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
        package must contain a real CrossOver.app; it is copied to
        /Applications and replaced when its bundle version changes.
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
    system.activationScripts.postActivation.text = ''
      echo "notproton: installing Steam/CrossOver/NotProton to /Applications..."
      ${installApp cfg.steam.package "Steam.app" "if-absent"}
      ${installApp cfg.crossover.package "CrossOver.app" "on-version-change"}
      ${installApp cfg.package "NotProton.app" "on-version-change"}

      # First-run wiring: NotProton is GUI-only (no CLI/headless install).
      # Open it once for the user; it clones CrossOver into
      # ~/Library/Application Support/notproton/runners/ and patches
      # Steam.app from its Status view. dylib.version is written by
      # NotProton when the Steam install completes, so this fires only
      # until setup is done.
      if [ ! -f "${home}/Library/Application Support/notproton/dylib.version" ]; then
        echo "notproton: first run -- opening NotProton for ${user} to finish setup"
        /bin/launchctl asuser "$(/usr/bin/id -u ${user})" /usr/bin/open -a /Applications/NotProton.app || true
      fi
    '';
  };
}
