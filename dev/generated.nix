# Contents of the generated files: README.md and .github/workflows/*.yml, from registry.nix and ci/status.json.
{ lib, registry, status }:
let
  names = map (e: e.name) registry;
  stateOf = n: let s = status.entries.${n} or null; in if s == "OK" then "equal" else if s == null then "n/a" else "DIFF";
  short = flake: if lib.hasPrefix "github:denful/den?dir=" flake then "den:" + lib.removePrefix "github:denful/den?dir=" flake else flake;
  row = e: "| ${e.name} | `${short e.flake}` | ${stateOf e.name} | ${lib.concatStringsSep "; " (lib.filter (x: x != "") [ e.notes (lib.optionalString (e.owner != "") "owner: ${e.owner}") ])} |";
  d = status.deadbugs;
  rows = lib.concatStringsSep "\n" (map row registry ++ [ "| deadbugs | Den `templates/ci/modules/deadbugs` | ${toString d.pass}/${toString d.total} | Den passes ${toString d.total}/${toString d.total} |" ]);
  readme = lib.replaceStrings [ "@TABLE@" "@DENREV@" "@PASS@" "@TOTAL@" "@TPASS@" "@TTOTAL@" ] [ rows status.denRev (toString d.pass) (toString d.total) (toString d.tests.pass) (toString d.tests.total) ] (builtins.readFile ./README.tmpl.md);

  setup = [
    { uses = "actions/checkout@v4"; }
    { uses = "cachix/install-nix-action@v31"; "with".nix_path = "nixpkgs=channel:nixos-unstable"; }
  ];
  inDev = cmd: "nix develop path:.?dir=dev -c ${cmd}";
in
{
  files = {
    "README.md".text = readme;
    ".github/workflows/ci.yml".yaml = {
      name = "ci";
      on = [ "push" "pull_request" ];
      jobs.ci = { runs-on = "ubuntu-latest"; steps = setup ++ [ { run = inDev "just ci"; } ]; };
      jobs.generated = {
        runs-on = "ubuntu-latest";
        steps = setup ++ [ { name = "README.md and workflows are in sync (run `just write`)"; run = "nix flake check path:.?dir=dev"; } ];
      };
    };
    # one job per registry entry
    ".github/workflows/den-templates.yml".yaml = {
      name = "den-templates";
      on = [ "push" "pull_request" "workflow_dispatch" ];
      jobs.entry = {
        runs-on = "ubuntu-latest";
        strategy = { fail-fast = false; matrix.entry = names; };
        steps = setup ++ [ {
          name = "gate";
          env.T = "\${{ matrix.entry }}";
          run = inDev ''just gate "$T"'';
        } ];
      };
    };
    ".github/workflows/deadbugs.yml".yaml = {
      name = "deadbugs";
      on = [ "push" "pull_request" "workflow_dispatch" ];
      # Reporting mode until dungeon reaches 65/65; then delete continue-on-error.
      jobs.deadbugs = {
        runs-on = "ubuntu-latest";
        continue-on-error = true;
        steps = setup ++ [ { run = inDev "just deadbugs"; } ];
      };
    };
    # label-gated: one job per Den complexity group (denful/den#736) + full templates/ci
    ".github/workflows/den-ci.yml".yaml = {
      name = "den-ci";
      on = { pull_request.types = [ "opened" "synchronize" "reopened" "labeled" ]; workflow_dispatch = { }; };
      jobs = lib.genAttrs [ "c1" "c2" "c3" "c4" "c5" "full" ] (g: {
        "if" = "contains(github.event.pull_request.labels.*.name, 'den-ci:${g}') || github.event_name == 'workflow_dispatch'";
        runs-on = "ubuntu-latest";
        continue-on-error = true;
        steps = setup ++ [ { run = inDev "just den-ci ${g}"; } ];
      });
    };
  };
}
