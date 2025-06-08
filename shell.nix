let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/5ac14523b6ae564923fb952ca3a0a88f4bfa0322.tar.gz";
 
  pkgs = import nixpkgs { config = {}; overlays = []; };
in


pkgs.mkShellNoCC {
  packages = with pkgs; [
    # Tools
    ripgrep

    # Programming Languages
    python3
    zig
  ];
}
