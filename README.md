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
| `notproton.user` | `system.primaryUser` | Owns the `/Applications` copies and the NotProton state under `~/Library/Application Support/notproton`. |
| `notproton.package` | **required, no default** | Package containing `Applications/NotProton.app`. Not in nixpkgs; fleiks provides it. |
| `notproton.steam.package` | **required, no default** | Package containing `Applications/Steam.app`. nixpkgs' `pkgs.steam` is the Linux client (`buildFHSEnv`/bubblewrap) — there is no macOS Steam in nixpkgs; fleiks provides one. |
| `notproton.crossover.package` | **required, no default** | Package containing `Applications/CrossOver.app`. nixpkgs' `pkgs.crossover` is the macOS app, currently 26.3.0 — the stable build NotProton supports. |

Enabling the module without setting all three fails evaluation with an assertion naming the missing option. Every package must lay its app out as `$out/Applications/<Name>.app` (all of the above do).

## How it works

NotProton patches `/Applications/Steam.app` in place (copies in `notproton.dylib`, edits `Info.plist`, ad-hoc re-signs) and discovers CrossOver only under `/Applications` or `~/Applications`. Nix store symlinks in `/Applications/Nix Apps` are read-only and invisible to that discovery, so on activation the module copies real, user-owned, writable apps into `/Applications`:

- **Steam.app** — copied only if absent. Steam self-updates inside its bundle and NotProton patches it; the module never overwrites it.
- **CrossOver.app** / **NotProton.app** — replaced only when `CFBundleVersion` changes.

NotProton is GUI-only — there is no CLI or headless install. Open NotProton yourself and click through its Status view: it clones CrossOver into `~/Library/Application Support/notproton/runners/`, patches Steam, and registers the `notproton-26.3` compatibility tool. Activation only installs the apps; it never launches anything.

Still manual, by upstream design:

- Steam → Settings → Compatibility: pick the CrossOver 26.3 (Rosetta) tool as default. Per-game overrides live in each game's Properties → Compatibility.
- CrossOver licensing: the nixpkgs zip is CodeWeavers' trial build until you activate it in CrossOver itself. NotProton will not set up the compatibility tool until CrossOver is activated.
- VAC titles launch in insecure mode (upstream limitation).

## Checks

```
nix flake check
```

Evaluates the module inside a real `darwinSystem` (with stand-in packages) and verifies the activation script and assertions.

Dev environment is devenv: `devenv shell`, `devenv test`.
