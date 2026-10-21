#!/usr/bin/env bash
# usage: dev/test.sh <deadbugs|c1|c2|c3|c4>  -> Den templates/ci category on this checkout via fastest; last line "TALLY <cat> <pass>/<total>"
set -u
cat=${1:?usage: dev/test.sh deadbugs|c1|c2|c3|c4}
err=$(mktemp)
fastest --flake "github:denful/den?dir=templates/ci#tests" --override-input den "path:$PWD" "$cat" 2>&1 >/dev/null | tee "$err" >&2; rc=${PIPESTATUS[0]}
t=$(sed "s/\x1b\[[0-9;]*m//g" "$err" | grep -oE "[0-9]+/[0-9]+" | tail -1); echo "TALLY $cat ${t:-0/0}"
exit "$rc"
