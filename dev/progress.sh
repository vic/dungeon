#!/usr/bin/env bash
# usage: dev/progress.sh  -> gate on all registry entries, then deadbugs,c1..c4 in order; writes dev/status.json (README source)
set -u
gate=$(mktemp); tally=$(mktemp)
bash dev/gate.sh | tee "$gate" >&2
for c in deadbugs c1 c2 c3 c4; do bash dev/test.sh "$c" | grep "^TALLY" >> "$tally"; done
jq -n --rawfile g "$gate" --rawfile t "$tally" '{
  entries: ($g | split("\n") | map(select(test("^\\S+ (OK|FAIL)")) | split(" ") | {key: .[0], value: .[1]}) | from_entries),
  tests: ($t | split("\n") | map(select(length > 0) | split(" ") | {key: .[1], value: (.[2] | split("/") | {pass: (.[0] | tonumber), total: (.[1] | tonumber)})}) | from_entries)
}' > dev/status.json
