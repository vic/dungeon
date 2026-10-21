#!/usr/bin/env bash
# usage: dev/noflake.sh <den-src> <den-impl-dir>  -> "<toplevel.drv> <sh.drv>" of Den's noflake template with den=<den-impl-dir>
set -eu
src=$(realpath "$1") d=$(realpath "$2")
cd "$src/templates/noflake"
ulimit -v 12582912
timeout 600 nix eval --impure --raw --expr "let sources = import ./npins; o = import sources.with-inputs sources { den.outPath = $d; } (inputs: (inputs.nixpkgs.lib.evalModules { modules = [ (inputs.import-tree ./modules) ]; specialArgs = { inherit inputs; inherit (inputs) self; }; }).config); in o.flake.nixosConfigurations.igloo.config.system.build.toplevel.drvPath + \" \" + o.den.sh.drvPath" 2>/dev/null
