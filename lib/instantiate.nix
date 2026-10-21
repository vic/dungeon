# policy.instantiate custom spec: `instantiate { modules }` of the spec's class bucket lands at flake.<intoAttr> (reference/policies.mdx:162-172).
dungeon: {
  instantiates =
    world: lib:
    let
      pol = dungeon.policy world;
      hosts = builtins.concatMap builtins.attrValues (builtins.attrValues world.hosts);
      routeOf = h0: let us = pol.usersOf h0; in dungeon.route world.schema world.aspects (h0 // { users = us; }) (builtins.attrNames us);
      one =
        h0:
        let
          r = routeOf h0;
        in
        map (e: lib.setAttrByPath e.value.intoAttr (e.value.instantiate { modules = r.classModules e.value.class; })) r.instantiates;
      # den.schema.flake.includes policies: a custom spec at flake scope collects its class from every host's scope subtree
      flakeOne = e: lib.setAttrByPath e.value.intoAttr (e.value.instantiate { modules = builtins.concatMap (h0: (routeOf h0).classModules e.value.class) hosts; });
      flakeSpecs = builtins.filter (e: e.value ? class && e.value ? instantiate && e.value ? intoAttr) pol.tree.instEffs;
    in
    # one value per path: flake freeform leaves are `raw` (single definition)
    builtins.foldl' lib.recursiveUpdate { } (builtins.concatMap one hosts ++ map flakeOne flakeSpecs);
}
