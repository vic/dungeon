#!/usr/bin/env bash
# usage: ci/den-src.sh [rev|dir]  -> prints a Den source dir (default: rev pinned in ci/den-rev).
# `prefetch` copies the source into the store; `flake metadata .path` only names it, and the path is missing on a clean runner.
# Bump: `nix flake metadata github:denful/den --json | jq -r .locked.rev > ci/den-rev`.
set -eu
a=${1:-$(tr -d '\n' < "$(dirname "$0")/den-rev")}
if [ -d "$a" ]; then realpath "$a"; else nix flake prefetch --json "github:denful/den/$a" | jq -r .storePath; fi
