#!/usr/bin/env bash
# usage: dev/gate.sh [entry...]  -> one line per gate: <name> OK|FAIL
# Entries come from registry.nix (default: all). Needs `drvPathDiff` on PATH (nix develop ./dev).
# "github:denful/den?dir=X" flakes are read from <den-src>/X (latest Den, or DEN_SRC=<dir>) and run with den=<den-src> vs den=<dungeon-dir>.
# Other flakes run with their own input vs den=<dungeon-dir>.
set -u
W=$PWD S=$(realpath "${DEN_SRC:-$(nix flake prefetch --json github:denful/den | jq -r .storePath)}")
cd "$W"
reg=$(nix eval --json --file registry.nix)
names=("$@"); [ ${#names[@]} -gt 0 ] || mapfile -t names < <(jq -r '.[].name' <<< "$reg")
for t in "${names[@]}"; do
  e=$(jq -c --arg t "$t" '.[] | select(.name == $t)' <<< "$reg")
  [ -n "$e" ] || { echo "$t FAIL (not in registry)"; continue; }
  f() { jq -r "$1" <<< "$e"; }
  kind=$(f .kind) flake=$(f .flake) input=$(f .denInput)
  isden=false; case $flake in github:denful/den\?dir=*) flake="path:$S/${flake#*dir=}"; isden=true ;; esac
  case $kind in
    nix-unit) (ulimit -v 12582912; timeout 300 nix run nixpkgs#nix-unit -- --override-input "$input" "path:$W" --flake "$flake#.$(f '.attrs[0]')" 2>&1) | grep -q '1/1 successful' && echo "$t OK" || echo "$t FAIL" ;;
    noflake) a=$(bash dev/noflake.sh "$S" "$S"); b=$(bash dev/noflake.sh "$S" "$W")
      [ -n "$a" ] && [ "$a" = "$b" ] && echo "$t OK" || echo "$t FAIL" ;;
    template|flake)
      args=(--dungeon "$W" --input "$input")
      $isden && args+=(--den "path:$S")
      [ "$(f '.packages')" = true ] && args+=(--packages)
      while read -r i; do args+=(--ignore "$i"); done < <(f '.ignore[]')
      if [ "$(f '.attrs | type')" = array ]; then args+=(--no-auto "$flake" $(f '.attrs[]')); else args+=("$flake"); fi
      (ulimit -v 12582912; timeout 900 drvPathDiff "${args[@]}" >&2) && echo "$t OK" || echo "$t FAIL" ;;
    *) echo "$t FAIL (kind $kind)" ;;
  esac
done
