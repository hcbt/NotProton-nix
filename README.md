# NotProton-nix

nix-darwin module managing Steam, CrossOver and [NotProton](https://github.com/NotProtonNot/NotProton) — Steam Play for the macOS Steam client.

## Usage

All three packages are required; the module has no package defaults. [fleiks](https://github.com/hcbt/fleiks) provides the macOS Steam and NotProton packages; nixpkgs provides CrossOver.

```nix
{
  inputs = {
    notproton-nix = {
      url = "github:hcbt/NotProton-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fleiks = {
      url = "github:hcbt/fleiks";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # in your darwin configuration:
  imports = [ inputs.notproton-nix.darwinModules.default ];

  nixpkgs.config.allowUnfree = true; # CrossOver

  notproton = {
    enable = true;
    # user = "hcbt"; # defaults to system.primaryUser
    package = inputs.fleiks.packages.${pkgs.stdenv.hostPlatform.system}.notproton;
    steam.package = inputs.fleiks.packages.${pkgs.stdenv.hostPlatform.system}.steam;
    crossover.package = pkgs.crossover;
  };
}
```

## Options

| Option | Default | Notes |
| --- | --- | --- |
| `notproton.enable` | `false` | Turn the whole stack on. |
| `notproton.user` | `system.primaryUser` | Owns the `/Applications/Steam.app` copy and the NotProton state under `~/Library/Application Support/notproton`. |
| `notproton.package` | **required, no default** | Package containing `Applications/NotProton.app`. Not in nixpkgs; fleiks provides it. |
| `notproton.steam.package` | **required, no default** | Package containing `Applications/Steam.app`. nixpkgs' `pkgs.steam` is the Linux client (`buildFHSEnv`/bubblewrap) — there is no macOS Steam in nixpkgs; fleiks provides one. |
| `notproton.crossover.package` | **required, no default** | Package containing `Applications/CrossOver.app`. nixpkgs' `pkgs.crossover` is the macOS app, currently 26.3.0 — the stable build NotProton supports. |

Enabling the module without setting all three fails evaluation with an assertion naming the missing option. Every package must lay its app out as `$out/Applications/<Name>.app` (all of the above do).

## How it works

All three apps are added to `environment.systemPackages` and nix-darwin installs them its usual way (`/Applications/Nix Apps`, read-only). The module copies nothing itself. Three pieces of glue make that work with upstream NotProton:

- **CrossOver.app** — NotProton only scans `/Applications` and `~/Applications`, so the module sets its `manualCrossOverPaths` user default to `/Applications/Nix Apps/CrossOver.app`. NotProton clones CrossOver into `~/Library/Application Support/notproton/runners/` before patching the clone, and the clone keeps the source's permissions, so activation hands the Nix Apps copy to the user writable (it is only a clone source; nix-darwin re-syncs it every switch) and repairs any clone already made read-only.
- **Steam.app** — nix-darwin installs Valve's Intel bootstrap. Activation downloads the `macos-signed-2` client package and replaces both executables with its arm64 slice, then NotProton patches that binary. The module sets `steamAppPath` to the Nix Apps bundle. Steam self-updates into `~/Library/Application Support/Steam`.
- **NotProton.app** — needs no glue; it is launched from Nix Apps like any other app.

NotProton is otherwise GUI-only. Activation runs `NotProtonApp --setup` as `notproton.user` after the apps are installed. That deploys NotProton's files, clones and patches CrossOver whether or not it is activated, and sets that tool as Steam's default when Steam has no config yet. It does not open the window.

Still manual, by upstream design:

- Per-game compatibility overrides live in each game's Properties → Compatibility. The global default is set only when Steam has no `config.vdf` yet.
- VAC titles launch in insecure mode (upstream limitation).

## Checks

```
nix flake check
```

Evaluates the module inside a real `darwinSystem` (with stand-in packages) and verifies the activation script and assertions.

Dev environment is devenv: `devenv shell`, `devenv test`.
