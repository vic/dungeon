# den.namespace name sources -> module (guides/namespaces.mdx): `name` module arg + `name.<x>` definitions are aspects under `den.aspects.<name>.provides`.
# sources: upstream flakes' `denful.<name>` merged in; `true` exports `flake.denful.<name>`.
dungeon: {
  namespace =
    name: sources:
    { lib, config, ... }:
    let
      srcs = if builtins.isList sources then sources else [ sources ];
      up = map (s: s.denful.${name} or { }) (builtins.filter builtins.isAttrs srcs);
      # fn-valued definitions stay callable on the typed aspect (Den `__functor` on merged aspects, reference/aspects.mdx:75-76):
      # `ns.x arg` applies the raw fn, `lib.functionArgs ns.x` reflects it. Raw `_` reaches the typed `provides` (normalize.nix unalias).
      callable =
        view: raw:
        if builtins.isFunction raw then view // { __functor = _: raw; }
        else if builtins.isAttrs raw then view // lib.concatMapAttrs (k: r: let t = if k == "_" then "provides" else k; in lib.optionalAttrs (builtins.isAttrs (view.${t} or null)) { ${t} = callable view.${t} r; }) raw
        else view;
    in
    {
      options.${name} = lib.mkOption {
        default = { };
        type = lib.mkOptionType {
          name = "dungeonNamespace";
          merge = _: defs: builtins.foldl' (a: d: lib.recursiveUpdate a d.value) { } defs;
        };
      };
      config = {
        ${name} = builtins.foldl' lib.recursiveUpdate { } up;
        den.aspects.${name}.provides = config.${name};
        # a namespace root's `_` bundles every aspect in it and shows its `includes` (issue-588)
        _module.args.${name} =
          let
            pv = config._module.args.den.aspects.${name}.provides;
            b = dungeon.bundle (builtins.attrValues (removeAttrs pv [ "__functor" ]));
          in
          callable pv config.${name} // { _ = removeAttrs pv [ "__functor" ] // b // { inherit (b.__functor b { }) includes; }; };
        # static condition: a `mkIf` would sit unmerged inside the freeform `flake` leaf
        flake = lib.optionalAttrs (builtins.elem true srcs) { denful.${name} = config.${name}; };
      };
    };
}
