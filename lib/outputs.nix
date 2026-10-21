# Per-system output classes (guides/flake-outputs.mdx:25-36, 104-128): `den.schema.flake-system.includes` resolved once per
# den.systems entry (reference/output.mdx:90-98), routed only into declared `flake.<output>` options (flake-outputs.mdx:51-58).
# shortcut: host/user/home scopes are not collected yet; upgrade when a template exports outputs from a host aspect.
dungeon: {
  outputs =
    world: inputs: options:
    let
      lib = inputs.nixpkgs.lib;
      # output leaf (issue-674): attrsets deep-merge per key, lists concat; any other leaf (derivation, scalar) is gen-merge's
      # leaf fold (`mergeDefs` over a type with no `.merge` is `mergeLeaf`): equal definitions merge, unequal throw.
      leaf = lib.mkOptionType {
        name = "denOutput";
        merge = loc: defs:
          let vs = map (d: d.value) defs; in
          if builtins.all (v: builtins.isAttrs v && !lib.isDerivation v) vs then (lib.types.lazyAttrsOf leaf).merge loc defs
          else if builtins.all builtins.isList vs then builtins.concatLists vs
          else dungeon.gen.merge.mergeDefs loc dungeon.gen.types.any defs;
      };
      sys = lib.unique (builtins.attrNames world.hosts ++ builtins.attrNames world.homes);
      systems = if world.systems != [ ] then world.systems else if sys != [ ] then sys else lib.systems.flakeExposed;
      root = { includes = world.schema.flake-system.includes; };
      eval =
        cls: system:
        removeAttrs (lib.evalModules {
          modules = [ { config._module.freeformType = lib.types.lazyAttrsOf leaf; config._module.args.pkgs = inputs.nixpkgs.legacyPackages.${system}; } ]
            ++ (dungeon.resolve world cls root).imports;
        }).config [ "_module" ];
      # `flake` is an option (freeform submodule / flake-parts) or a plain set of output option decls
      subs = if options.flake._type or null == "option" then options.flake.type.getSubOptions [ ] else options.flake;
      classes = builtins.filter (n: subs ? ${n}) [ "packages" "apps" "checks" "devShells" "legacyPackages" ];
    in
    # one definition each, merged by the `flake` option's types: `//` would drop per-system outputs under an intoAttr head
    # like `packages`
    lib.mkMerge (
      lib.optional (world.schema ? flake-system && root.includes != [ ]) (lib.genAttrs classes (cls: lib.genAttrs systems (eval cls)))
      # custom-kind policy.instantiate results land at flake.<intoAttr> (reference/policies.mdx:162-172); host ones: instantiate.nix
      ++ map (i: lib.setAttrByPath i.path i.value) (dungeon.policy world).customInsts
    );
}
