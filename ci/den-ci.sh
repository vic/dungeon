#!/usr/bin/env bash
# usage: ci/den-ci.sh <den-src> <deadbugs|c1..c5|full> [tsv]  -> Den's suites on this checkout via fastest.
# fastest takes one suite per call: loop, sum tallies. Optional tsv gets `<suite>\tPASS|FAIL\t<p>/<t>` rows (ci/status.sh).
set -euo pipefail
den=${1:?usage: $0 <den-src> <group> [tsv]}; group=${2:-}; tsv=${3:-/dev/null}
case $group in
  deadbugs) dirs=("$den"/templates/ci/modules/deadbugs) ;;
  c[1-5]) dirs=("$den"/templates/ci/modules/public/"$group"-*/) ;;
  full) dirs=() ;;
  *) echo "usage: $0 <den-src> deadbugs|c1|c2|c3|c4|c5|full [tsv]" >&2; exit 2 ;;
esac
suites=("")  # full: one run, no suite filter
[ ${#dirs[@]} -eq 0 ] || mapfile -t suites < <(rg -oN --no-filename -r '$1' 'flake\.tests\.([A-Za-z0-9_-]+)' "${dirs[@]}" | sort -u | if [ "$group" = deadbugs ]; then cat; else grep -vx deadbugs; fi)  # cN modules nesting under flake.tests.deadbugs run in the deadbugs job
: > "$tsv"; pass=0; total=0; bad=0; err=$(mktemp)
for s in "${suites[@]}"; do
  st=PASS; fastest --flake "path:$den/templates/ci#tests" --override-input den "path:$PWD" ${s:+"$s"} 2>"$err" >/dev/null || { st=FAIL; bad=$((bad + 1)); }
  t=$(grep -oE '[0-9]+/[0-9]+' "$err" | tail -1 || true); t=${t:-0/0}
  pass=$((pass + ${t%/*})); total=$((total + ${t#*/}))
  printf '%s\t%s\t%s\n' "${s:-full}" "$st" "$t" | tee -a "$tsv"
done
echo "TALLY $group: $pass/$total tests, $bad of ${#suites[@]} suites failed"
[ "$bad" -eq 0 ]
