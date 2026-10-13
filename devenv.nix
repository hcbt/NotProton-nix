{ pkgs, ... }:

{
  packages = [
    pkgs.git
    pkgs.nixfmt
  ];

  git-hooks.hooks.nixfmt.enable = true;

  enterTest = ''
    nix flake check
  '';
}
