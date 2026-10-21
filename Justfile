# run inside `nix develop ./dev`

default:
    @just --list

# tier1 + gate (all registry entries) + deadbugs summary; writes ci/status.json
ci:
    just gate-all
    just deadbugs
    bash ci/status.sh /tmp/gate.out /tmp/deadbugs.tsv

# gate on every entry of registry.nix, output kept for ci/status.json
gate-all:
    bash ci/gate.sh . "$(bash ci/den-src.sh ${DEN_SRC:-})" | tee /tmp/gate.out /dev/stderr | { ! grep -q FAIL; }

# tier1 + registry entries (default all) with den=Den vs den=this checkout. Den source: ci/den-rev (override: DEN_SRC=<dir|rev>)
gate *entries:
    bash ci/gate.sh . "$(bash ci/den-src.sh ${DEN_SRC:-})" {{entries}} | tee /dev/stderr | { ! grep -q FAIL; }

# Den's deadbugs suites on dungeon via fastest; writes /tmp/deadbugs.tsv. Report only: Den passes 65/65.
deadbugs:
    just den-ci deadbugs /tmp/deadbugs.tsv

# Den templates/ci group on dungeon: deadbugs|c1..c5|full. Den source: ci/den-rev (override: DEN_SRC=<dir|rev>)
den-ci group="deadbugs" tsv="/dev/null":
    bash ci/den-ci.sh "$(bash ci/den-src.sh ${DEN_SRC:-})" {{group}} {{tsv}}

# regenerate README.md and .github/workflows/* (dev/generated.nix: registry.nix + ci/status.json)
write:
    nix run "path:{{justfile_directory()}}?dir=dev#write-files"

# fail if generated files are out of date
check:
    nix flake check "path:{{justfile_directory()}}?dir=dev"

fmt:
    nixfmt $(fd -e nix -E ci -E node_modules .)

# compare a flake's drvPaths: Den vs dungeon (this checkout). usage: just diff <flake-ref> [attr...]
diff flake *attrs:
    drvPathDiff --dungeon {{justfile_directory()}} {{flake}} {{attrs}}
