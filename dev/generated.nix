# Contents of the generated files: README.md and .github/workflows/*.yml, from registry.nix and dev/status.json.
{ lib, registry, status }:
let
  names = map (e: e.name) registry;
  categories = [ "deadbugs" "c1" "c2" "c3" "c4" ];
  stateOf = n: let s = status.entries.${n} or null; in if s == "OK" then "equal" else if s == null then "n/a" else "DIFF";
  short = flake: if lib.hasPrefix "github:denful/den?dir=" flake then "den:" + lib.removePrefix "github:denful/den?dir=" flake else flake;
  row = e: "| ${e.name} | `${short e.flake}` | ${stateOf e.name} | ${lib.concatStringsSep "; " (lib.filter (x: x != "") [ e.notes (lib.optionalString (e.owner != "") "owner: ${e.owner}") ])} |";
  rows = lib.concatStringsSep "\n" (map row registry);
  tally = c: let t = status.tests.${c} or null; in if t == null then "n/a" else "${toString t.pass}/${toString t.total}";
  testRows = lib.concatStringsSep "\n" (map (c: "| ${c} | ${tally c} |") categories);
  readme = lib.replaceStrings [ "@TABLE@" "@TESTS@" ] [ rows testRows ] (builtins.readFile ./README.tmpl.md);

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
    # Den templates/ci categories, increasing complexity. Reporting mode: all may fail while dungeon is unstable.
    ".github/workflows/tests.yml".yaml = {
      name = "tests";
      on = [ "push" "pull_request" "workflow_dispatch" ];
      # categories are independent jobs: they run in parallel
      jobs = lib.genAttrs categories (c: {
        runs-on = "ubuntu-latest";
        continue-on-error = true;
        steps = setup ++ [
          {
            name = "test ${c}";
            continue-on-error = true;
            run = inDev "just test ${c} | tee out.txt || true" + "\n" + "grep '^TALLY' out.txt > tally-${c}.txt";
          }
          {
            "if" = "always()";
            uses = "actions/upload-artifact@v4";
            "with" = { name = "tally-${c}"; path = "tally-${c}.txt"; if-no-files-found = "error"; };
          }
        ];
      }) // {
        # collects every category tally into dev/status.json and README.md; main commits them back
        progress = {
          needs = categories;
          "if" = "always()";
          runs-on = "ubuntu-latest";
          permissions.contents = "write";
          steps = setup ++ [
            { uses = "actions/download-artifact@v4"; "with".path = "tallies"; }
            { name = "merge tallies"; run = inDev "bash dev/merge-tally.sh tallies"; }
            { name = "regenerate README.md"; run = inDev "just write"; }
            { name = "summary"; run = "jq -r '.tests | to_entries[] | \"| \\(.key) | \\(.value.pass)/\\(.value.total) |\"' dev/status.json >> \"$GITHUB_STEP_SUMMARY\""; }
            {
              name = "commit progress (main only)";
              "if" = "github.ref == 'refs/heads/main' && github.event_name == 'push'";
              run = ''
                git diff --quiet dev/status.json README.md && exit 0
                git config user.name github-actions
                git config user.email github-actions@github.com
                git commit -m "ci: update test progress" dev/status.json README.md
                git push
              '';
            }
          ];
        };
      };
    };
  };
}
