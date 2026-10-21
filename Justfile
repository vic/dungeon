# run inside `nix develop ./dev`

default:
    @just --list

# Den templates/ci category on dungeon via fastest: deadbugs|c1|c2|c3|c4
test cat="deadbugs":
    bash dev/test.sh {{cat}}

# gate + all test categories in order; writes dev/status.json
progress:
    bash dev/progress.sh

# registry entries (default all): den=Den vs den=this checkout, drvPaths equal. Den source: latest (override: DEN_SRC=<dir>)
gate *entries:
    bash dev/gate.sh {{entries}} | tee /dev/stderr | { ! grep -q FAIL; }

# regenerate README.md and .github/workflows/* (dev/generated.nix: registry.nix + dev/status.json)
write:
    nix run "path:{{justfile_directory()}}?dir=dev#write-files"

# fail if generated files are out of date
check:
    nix flake check "path:{{justfile_directory()}}?dir=dev"

fmt:
    nixfmt $(fd -e nix -E node_modules .)

# compare a flake's drvPaths: Den vs dungeon (this checkout). usage: just diff <flake-ref> [attr...]
diff flake *attrs:
    drvPathDiff --dungeon {{justfile_directory()}} {{flake}} {{attrs}}
