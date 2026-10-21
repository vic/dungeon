# Registry of installables whose drvPaths are compared: Den vs dungeon.
# Add yours with a PR (see CONTRIBUTING in README).
#
# name      unique id
# kind      "template" | "flake": drvPathDiff, input `denInput` = Den vs dungeon
#           "nix-unit": nix-unit test `attrs` of the flake, run with den = dungeon
#           "noflake": npins-based Den template (dev/noflake.sh)
# flake     flake ref, no `#`. "github:denful/den?dir=templates/X" is read from the latest Den (override: DEN_SRC=<dir>).
# attrs     "auto" (all nixos/darwin/home configurations) or a list: [ "nixosConfigurations.foo" "packages.x86_64-linux.bar" ]
# denInput  name of the flake input that dungeon replaces (default "den")
# ignore    attr names excluded on both sides
# packages  also compare packages.x86_64-linux (attrs = "auto" only)
# owner, notes  free text, shown in README
let
  tpl = name: extra: {
    inherit name;
    kind = "template";
    flake = "github:denful/den?dir=templates/${name}";
    attrs = "auto";
    packages = true;
    owner = "denful/den";
  } // extra;
in
map (e: { denInput = "den"; ignore = [ ]; packages = false; owner = ""; notes = ""; } // e) [
  (tpl "minimal" { })
  { name = "bogus"; kind = "nix-unit"; flake = "github:denful/den?dir=templates/bogus"; attrs = [ "tests.bogus" ]; owner = "denful/den"; }
  { name = "noflake"; kind = "noflake"; flake = "github:denful/den?dir=templates/noflake"; attrs = "auto"; owner = "denful/den"; }
  (tpl "flake-parts-modules" { })
  (tpl "terranix-demo" { })
  (tpl "nvf-standalone" { })
  (tpl "default" { })
  (tpl "example" { })
  (tpl "microvm" { })
  (tpl "fleet-demo" {
    ignore = [ "fleet-fleet-ir" "fleet-namespace" "fleet-pipe-flow" "fleet-pipe-sequence" "fleet-policy-resolution" "fleet-scope-topology" "fleet-summary" "write-diagrams" ];
    notes = "hosts equal; `den-diagram` packages out of scope";
  })
]
