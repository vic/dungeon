# Includes closure: gen.program model = membership authority, DFS = order only (design-gen.md §3.6-7). Adapted from ren/lib/activation.nix.
dungeon: {
  # Aspect identity = Gen's one mint: the typed aspect's `id_hash` (gen-aspects lib/types.nix:1481, minted by `aspectId`
  # over origin + declared path, types.nix:1028-1048 via gen-identity `hashIdentity`); a record the type never stamped
  # (route.nix synthetic policy/route/schema records) mints through the same `aspectId`, which for a record with no declared
  # path is its name (gen-aspects identity.nix:11): not a real identity, so activation.nix never dedups those.
  aspectIdOf = a: a.id_hash or (dungeon.gen.aspects.aspectId [ ] a);
  closure =
    aspects: root:
    let
      id = dungeon.aspectIdOf;
      # nested aspects are named `<parent>/<key>` and live inside their parent (view.nix); top-level names (incl. anons `n/i`) win.
      at = n: builtins.foldl' (e: s: e.${s}) aspects (dungeon.aspectPath aspects n);
      kids = a: map (b: at b.name) a.includes;
      dfs =
        seen: a:
        if seen ? ${id a} then
          seen
        else
          builtins.foldl' dfs (seen // { ${id a} = a; order = (seen.order or [ ]) ++ [ a ]; }) (kids a);
      order = (dfs { } root).order;
      # only aspects reachable from root can be members, so rules are built from them
      rules =
        [ { head = id root; pos = [ ]; neg = [ ]; relata = [ ]; } ]
        ++ builtins.concatMap (
          a:
          map (b: { head = id (at b.name); pos = [ (id a) ]; neg = [ "x:${id (at b.name)}" ]; relata = [ ]; }) a.includes
          ++ map (b: { head = "x:${id (at b.name)}"; pos = [ (id a) ]; neg = [ ]; relata = [ ]; }) (a.excludes or [ ])
        ) order;
      model = dungeon.gen.program.model {
        program = dungeon.gen.program.program [ ] rules;
        interpretation = [ ];
        prior = null;
        complete = true;
      };
      member = a: (model.resolve (id a)).included;
      checked = model.undefinedAtoms == [ ] || throw "den: aspects not stratified: ${toString model.undefinedAtoms}";
    in
    assert checked;
    builtins.filter member order;
}
