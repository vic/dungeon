# flake-parts perSystem delivery: `flake-parts` scope routes (guides/flake-outputs.mdx:291-340 "Through the perSystem module").
# route with non-empty path = nest: source modules called with adaptArgs(target args) (reference/policies.mdx:93-112, 137-140).
dungeon: {
  flakeParts =
    den: lib:
    let
      sch = den.schema;
      ids = k: map (x: x.__builtin or null) (sch.flake-system.${k} or [ ]);
      # reference/policies.mdx:309-315: opt-in via den.schema.flake-system.includes
      active = builtins.elem "system-to-flake-parts" (ids "includes") && !builtins.elem "system-to-flake-parts" (ids "excludes");
      flat = x: if builtins.isList x then builtins.concatMap flat x else [ x ];
      # reference/policies.mdx:315: `packages` class into perSystem `packages`, collectSubtree
      builtin.packages-to-flake-parts = [ (dungeon.effects.route { fromClass = "packages"; intoClass = "flake-parts"; path = [ "packages" ]; collectSubtree = true; }) ];
      list = r: if builtins.isList r then r else [ r ];
      call = f: list (f (builtins.intersectAttrs (lib.functionArgs f) { }));
      fire = x: if builtins.isAttrs x && x ? __builtin then builtin.${x.__builtin} or [ ] else if x.__isPolicy or false then call x.fn else if dungeon.isPol x || builtins.isFunction x then call x else [ ];
      effs = builtins.concatMap fire (flat (sch.flake-parts.includes or [ ]));
      of = k: builtins.filter (e: (e.__effect or null) == k) effs;
      cl = dungeon.closure den.aspects;
      own = map (a: { args = { }; inherit a; }) (dungeon.schemaCl sch den.aspects true "flake-parts");
      at = args: n: map (a: { inherit args a; }) (if den.aspects ? ${n} then cl den.aspects.${n} else [ ]);
      # resolved host scope: den.default + host closure, then each host user's closure (guides/flake-outputs.mdx:120-124)
      # shortcut: plain include closures, no policy activation inside the subtree; upgrade when a template needs host policies there.
      hostSub = host: at { inherit host; } "default" ++ at { inherit host; } host.name ++ builtins.concatMap (u: at { inherit host; user = host.users.${u}; } u) (builtins.attrNames host.users);
      sub = builtins.concatMap (e: if e.kind == "host" then hostSub e.bindings.host else throw "den: flake-parts scope: resolve.to `${e.kind}` unsupported") (of "resolve");
      srcs = e: builtins.filter (s: s.a.content ? ${e.fromClass}) (own ++ lib.optionals (e.collectSubtree or false) sub);
      pathOf = e: if e ? intoPath then (if builtins.isFunction e.intoPath then e.intoPath { } else e.intoPath) else e.path;
      argsOf = margs: e: if e ? adaptArgs then e.adaptArgs margs else margs.config.allModuleArgs;
      deliver = margs: e: lib.setAttrByPath (pathOf e) (dungeon.flatten (argsOf margs e) (map (s: dungeon.content.classModule s.args s.a s.a.content.${e.fromClass}) (srcs e)));
      routes = builtins.filter (e: e.intoClass == "flake-parts") (of "route");
      keys = lib.unique (builtins.attrNames den.hosts ++ builtins.attrNames den.homes);
    in
    {
      # reference/output.mdx:96-97: den.systems default
      systems = if den.systems != [ ] then den.systems else if keys == [ ] then lib.systems.flakeExposed else keys;
      perSystem = margs: { config = lib.mkMerge (lib.optionals active (map (deliver margs) routes)); };
    };
}
