#!/usr/bin/env bash
# usage: dev/merge-tally.sh <dir>  -> merges <dir>/**/tally-*.txt ("TALLY <cat> <pass>/<total>" lines) into dev/status.json .tests
set -eu
cat "$1"/*/tally-*.txt "$1"/tally-*.txt 2>/dev/null | grep "^TALLY" | jq -Rn --slurpfile s dev/status.json '
  $s[0] * {tests: ([inputs | split(" ") | {key: .[1], value: (.[2] | split("/") | {pass: (.[0] | tonumber), total: (.[1] | tonumber)})}] | from_entries)}' > dev/status.json.new
mv dev/status.json.new dev/status.json
