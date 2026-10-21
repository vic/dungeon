# den.lib.schema.mkInstanceType options kind -> instance submodule type.
# Docs: reference/lib.mdx "mkInstanceType options kind" (options: extraModules, strict, specialArgs);
# guides/custom-entity-kinds.mdx s2 (strict=false => open instance).
dungeon: {
  # Registry-level `hasAspect`/`resolved` on every instance (entities.mdx resolved); structural: kind includes only.
  # route.nix overrides hasAspect with the scope-projected closure where the scope is known.
  schema.entity = kind: let lib = dungeon.genLib; in {
    options.resolved = lib.mkOption { type = dungeon.genLib.types.raw; default = { }; };
    # instance-own includes/excludes are read for every kind, so they are declared (custom-entity-kinds.mdx:47-49), not freeform.
    options.includes = lib.mkOption { type = dungeon.genLib.types.listOf dungeon.genLib.types.raw; default = [ ]; };
    options.excludes = lib.mkOption { type = dungeon.genLib.types.listOf dungeon.genLib.types.raw; default = [ ]; };
    options.hasAspect = lib.mkOption {
      type = dungeon.genLib.types.raw;
      default = a: builtins.elem (a.name or null) (map (b: if builtins.isAttrs b then b.name or null else null) (kind.includes or [ ]));
    };
  };
  # den.schema.<kind> values are minted gen-schema kinds (view.nix mkSchemaOption), so instances are gen-schema's.
  schema.lib.mkInstanceType =
    {
      extraModules ? [ ],
      strict ? true,
      specialArgs ? { },
    }:
    kind0:
    let
      # a plain kind body (no gen-schema mark, e.g. `mkInstanceType { } { }`) is minted through dungeon's own schema option
      name = kind0.kind or "instance";
      kind = if kind0 ? __mint then kind0 else (dungeon.genLib.evalModules { modules = [ dungeon.view.module { schema.${name} = kind0; } ]; }).config.schema.${name};
    in
    dungeon.gen.schema.mkInstanceType {
      inherit strict;
      specialArgs = { lib = dungeon.genLib; } // specialArgs;
      extraModules = [ (dungeon.schema.entity kind) ] ++ extraModules;
    } kind;
}
