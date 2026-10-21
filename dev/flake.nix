# Dev tooling for dungeon. Kept out of the top-level flake so users of dungeon pull only `gen`.
# Use as `path:<repo>?dir=dev` (the whole repo is the source: README.md and workflows are generated at its root).
{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    files.url = "github:sini/files";
    fastest.url = "github:denful/fastest";
  };
  outputs = inputs@{ self, nixpkgs, flake-parts, files, fastest, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      imports = [ files.flakeModule ];
      perSystem = { pkgs, lib, config, system, ... }: let
        registry = import ../registry.nix;
        status = builtins.fromJSON (builtins.readFile ./status.json);
        gen = import ./generated.nix { inherit lib registry status; };
      in {
        files.generateApp = true;
        files.root = self.sourceInfo.outPath; # whole repo, not just dev/
        files.file = gen.files;

        packages.drvPathDiff = pkgs.writeShellApplication {
          name = "drvPathDiff";
          runtimeInputs = [ pkgs.nix pkgs.jq pkgs.gnused pkgs.gnugrep pkgs.coreutils ];
          text = ''
            export DRVPATHS_NIX=${./drvpaths.nix}
            ${builtins.readFile ./drvPathDiff.sh}
          '';
          # script handles its own failures; shellcheck noise on dynamic arrays
          checkPhase = "";
        };
        apps.drvPathDiff = { type = "app"; program = lib.getExe config.packages.drvPathDiff; };
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ just nix-unit nixfmt gh jq ripgrep fd actionlint shellcheck config.packages.drvPathDiff fastest.packages.${system}.fastest ];
        };
      };
    };
}
