# entity.aspects (explanation/structural-introspection.mdx:127-160): flat list of every resolved aspect node of the entity's tree
# (host: host scope + its user scopes), deduped by Gen's minted identity (dungeon.aspectIdOf = gen-aspects aspectId, types.nix:1028);
# the entity root is not listed. Membership = route.nix scope closures (closure.nix gen.program model, activation.nix), no new walker.
dungeon: {
  entityAspects =
    world: cfg: host:
    let
      inherit (world) aspects;
      id = dungeon.aspectIdOf;
      users = builtins.attrNames host.users;
      r = dungeon.route world.schema aspects host users;
      segs = n: builtins.filter builtins.isString (builtins.split "/" n);
      # nested aspects `<parent>/<key>` live inside their parent (closure.nix `at`)
      at = n: builtins.foldl' (e: s: e.${s}) aspects (dungeon.aspectPath aspects n);
      # host scope = route's activated host members (policy adds/excludes applied), not a second walk.
      hostScope = r.hostCl;
      rootId = if aspects ? ${host.name} then id aspects.${host.name} else null;
      members = builtins.filter (a: id a != rootId) (r.defaultCl ++ hostScope ++ builtins.concatMap r.userClosure users);
      uniq = (builtins.foldl' (acc: a: if acc.seen ? ${id a} then acc else { seen = acc.seen // { ${id a} = true; }; out = acc.out ++ [ a ]; }) { seen = { }; out = [ ]; } members).out;
      # include elements are hoisted to registry key `<parent>/<i>` (normalize.nix anon); their authored name survives on the typed record
      isAnon = n: let s = segs n; in builtins.length s > 1 && builtins.match "[0-9]+" (dungeon.genLib.last s) != null;
      typed = n: builtins.foldl' (e: s: e.${s} or { }) cfg.aspects (dungeon.aspectPath cfg.aspects n);
      typedName = n: (typed n).name or n;
      # identity = fq name, ctx-stripped: parent identity + the authored name, which outranks the position; unnamed: key (`<anon>:<i>` for include elements)
      identityOf =
        n:
        let
          s = segs n;
          last = dungeon.genLib.last s;
          tn = typedName n;
          # an authored name outranks the position; sentinels (`<anon>`, ...) are not authored (gen-aspects identity.nix:83 isMeaningfulName)
          label = if tn != n && tn != last && dungeon.gen.aspects.isMeaningfulName tn then tn else if isAnon n then "<anon>:${last}" else last;
        in
        if builtins.length s == 1 then label else "${identityOf (builtins.concatStringsSep "/" (dungeon.genLib.init s))}/${label}";
      # synthetic route.nix records (policy/route/schema) carry no id_hash: not declarations
      registered = a: a ? id_hash;
      node = a: {
        name = if registered a then typedName a.name else a.name;
        meta = a.meta or { };
        identity = if registered a then identityOf a.name else a.name;
        identityKey = id a;
        isNamed = registered a && dungeon.gen.aspects.isMeaningfulName (typedName a.name) && (!isAnon a.name || typedName a.name != a.name);
        includes = map (b: nodeOf.${id b}) (builtins.filter (b: nodeOf ? ${id b}) (map (b: at b.name) (a.includes or [ ])));
      };
      nodeOf = builtins.listToAttrs (map (a: { name = id a; value = node a; }) uniq);
    in
    map (a: nodeOf.${id a}) uniq;
}
