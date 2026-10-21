# One lowering pass: normAspect (value), classifyKey (aspect key), classifyInc (include element).
dungeon: {
  # policy record or functor-with-args; den.policies values are records from capture (entry.nix), so refs compare by name
  isPol = e: builtins.isAttrs e && ((e.__isPolicy or false) || (e ? __functor && e ? __functionArgs));
  inlineAttrs = e: builtins.isAttrs e && !(e ? key) && !dungeon.isPol e;
  # `<aspect>._`: a zero-arg functor whose result is the include (include-children tests), so attrNames stay the children
  bundle = kids: { __functor = _: _: { includes = kids; }; };
  isBundle = e: builtins.isAttrs e && e ? __functor && !(e ? __functionArgs) && !(e ? key);
  # registry path of `<a>/<b>/...`: the longest registered top-level prefix, then nested keys (anons nest their own inline includes)
  aspectPath =
    aspects: n:
    let
      s = builtins.filter builtins.isString (builtins.split "/" n);
      l = builtins.length s;
      go = i: if i == 0 then s else let h = builtins.concatStringsSep "/" (builtins.genList (builtins.elemAt s) i); in if aspects ? ${h} then [ h ] ++ builtins.genList (j: builtins.elemAt s (i + j)) (l - i) else go (i - 1);
    in
    go l;
  classifyInc = e: {
    policy = dungeon.isPol e;
    slot = if dungeon.isPol e then null else if builtins.isFunction e || dungeon.inlineAttrs e then "anon" else "ref";
  };
  normalize =
    lib: leaf: cnf: raw:
    let
      # fn aspects/includes are class content: each declared class key projects its own part of the fn result
      classes = builtins.filter (k: dungeon.gen.aspects.keyCategory cnf k == "class") (builtins.attrNames cnf.keySemantics);
      bare = f: lib.genAttrs classes (cls: lib.setFunctionArgs (args: { imports = [ ((f (builtins.intersectAttrs (lib.functionArgs f) args)).${cls} or { }) ]; }) (lib.functionArgs f));
      # structural keys are never nested aspects; other keys go through Gen keyCategory (class/channel keys hold content)
      skip = [ "provides" "_" "includes" "excludes" "policies" "meta" ];
      # mkForce/mkIf/mkOrder on an aspect: lower its content, keep the wrapper (gen-aspects projects through it, priority kept)
      prop = v: builtins.isAttrs v && builtins.elem (v._type or null) [ "override" "if" "order" ];
      un = v: if prop v then un v.content else v;
      under = f: path: v: if prop v then v // { content = under f path v.content; } else f path v;
      classifyKey =
        a: k:
        if builtins.elem k [ "provides" "_" ] then
          if builtins.isAttrs (a.${k} or null) then "provides" else null
        else if !builtins.elem k skip && dungeon.gen.aspects.keyCategory cnf k == null && (builtins.isFunction (un a.${k}) || builtins.isAttrs (un a.${k}) && !(un a.${k} ? _type)) then
          "nested"
        else
          null;
      keysOf = a: kind: builtins.filter (k: classifyKey a k == kind) (builtins.attrNames a);
      mapKids =
        f: path: a:
        a
        // lib.genAttrs (keysOf a "provides") (k: builtins.mapAttrs (c: v: under f "${path}/${c}" v) a.${k})
        // lib.genAttrs (keysOf a "nested") (k: under f "${path}/${k}" a.${k});
      kidList =
        path: a:
        lib.concatMap (k: lib.mapAttrsToList (c: v: { p = "${path}/${c}"; v = un v; }) a.${k}) (keysOf a "provides")
        ++ map (k: { p = "${path}/${k}"; v = un a.${k}; }) (keysOf a "nested");
      # `_` is an alias of `provides` (reference/aspects.mdx:69): one key reaches Gen, so both spellings are one sub-aspect.
      unalias =
        path: a:
        if !builtins.isAttrs (a._ or null) then a
        else
          let both = builtins.attrNames (builtins.intersectAttrs a._ (a.provides or { })); in
          if both != [ ] then throw "den: aspect `${path}`: `_.${builtins.head both}` and `provides.${builtins.head both}` both defined in one definition"
          else removeAttrs a [ "_" ] // { provides = (a.provides or { }) // a._; };
      normAspect =
        path: a:
        if builtins.isFunction a then
          bare a
        else if builtins.isAttrs a then
          mapKids normAspect path (unalias path a)
        else
          a;
      inl = a: lib.imap0 (i: e: { inherit i e; inc = dungeon.classifyInc e; }) (if builtins.isAttrs a && builtins.isList (a.includes or null) then a.includes else [ ]);
      anon = n: i: "${n}/${toString i}";
      # an inline element is walked through its `includes` only: its other keys are content, and may be cyclic (a let-bound `v` holding `v`)
      inlOnly = e: { includes = e.includes or [ ]; };
      # Den: one named value at one `name` position is one node; a factory gives several values one position, so `==` splits them.
      # The site is the relata gen-aspects keys a named include element by (lib/types.nix `includeSite`: name + position of `name`).
      siteOf = e: let p = builtins.unsafeGetAttrPos "name" e; in if dungeon.inlineAttrs e && builtins.isString (e.name or null) && p != null then "${e.name}@${toString p.line}:${toString p.column}:${p.file}" else null;
      sitesAt =
        n: a:
        lib.concatMap (x: let s = siteOf x.e; in lib.optional (s != null) { ${s} = [ { at = anon n x.i; v = x.e; } ]; } ++ lib.optionals (dungeon.inlineAttrs x.e) (sitesAt (anon n x.i) (inlOnly x.e))) (inl a)
        ++ lib.concatMap (k: sitesAt k.p k.v) (if builtins.isAttrs a then kidList n a else [ ]);
      # first sighting at the site whose value is `==` (a failing comparison is not equal), else the slot's own anon
      canon = sites: n: x: let s = siteOf x.e; same = c: let r = builtins.tryEval (c.v == x.e); in r.success && r.value; in if s == null then anon n x.i else (lib.findFirst same { at = anon n x.i; } sites.${s}).at;
      # configure-aspects.mdx:134-139: a fn taking no named args is a positional `ctx:` include; `{ class, aspect-chain }` is a static leaf
      positional = e: builtins.isFunction e && lib.functionArgs e == { };
      staticLeaf = e: builtins.isFunction e && (lib.functionArgs e) ? class && (lib.functionArgs e) ? aspect-chain;
      # Static leaf content per class: a den-arg module (content.nix binds `host` via gen.bind.wrap), so `class` + `aspect-chain`
      # are supplied where the class is resolved. Chain head = the scope's entity (resolve.nix): the user entity for a user-scope
      # class (bound per user by route.nix argsOf), else the host entity.
      # shortcut: user-scope classes are the builtin ones; a class added to schema.user.classes keeps the host head.
      userScoped = [ "user" "homeManager" "hjem" "maid" ];
      leafOf =
        cls: chain: r:
        {
          imports = lib.optional (r ? ${cls}) r.${cls} ++ map (
            i:
            if staticLeaf i then leafOf cls chain (i { class = cls; aspect-chain = chain; })
            else if dungeon.inlineAttrs i then leafOf cls chain i
            else throw "den: static leaf result include (ref or parametric) is not supported"
          ) (r.includes or [ ]);
        };
      leafAspect = f: lib.genAttrs classes (cls: {
        __functor = _: { host, user ? null }: let chain = [ (if user == null then { __entityKind = "host"; ctx.host = host; inherit (host) name; } else { __entityKind = "user"; ctx = { inherit host user; }; inherit (user) name; }) ]; in leafOf cls chain (f { class = cls; aspect-chain = chain; });
        # `user` is advertised only where every consumer binds it: the module system would otherwise be asked for it
        __functionArgs = { host = false; } // lib.optionalAttrs (builtins.elem cls userScoped) { user = false; };
      });
      tree = if builtins.isAttrs raw then builtins.mapAttrs (under normAspect) raw else raw;
      # Keys exist for every include slot (elements stay unforced: they may reference `den`, which would cycle).
      anonVal = fixA: p: e: if dungeon.isBundle e then e.__functor e { } else if positional e then { } else if staticLeaf e then leafAspect e else if builtins.isFunction e then bare e else if dungeon.inlineAttrs e then fixA p e else { };
      anonsAt =
        fixA: n: a:
        builtins.listToAttrs (map (x: { name = anon n x.i; value = anonVal fixA (anon n x.i) x.e; }) (inl a))
        // lib.foldl' (acc: k: acc // anonsAt fixA k.p k.v) { } (if builtins.isAttrs a then kidList n a else [ ]);
      # Aspect policy delivering the `includes` a fn aspect/include returns (Den parity: fn results' includes are live).
      # declared quirks are always bound ([] when nothing is emitted), so a fn include needing only them is ready at any scope
      # shortcut: pipe-fed quirk values are not seen when deciding includes; upgrade when an include depends on a quirk value
      chan = lib.genAttrs (builtins.filter (k: dungeon.gen.aspects.keyCategory cnf k == "channel") (builtins.attrNames cnf.keySemantics)) (_: [ ]);
      # Fn elements whose required args are not yet in scope fire later at the user scope (member policies fire per scope).
      fnIncs =
        n: f:
        let
          content = e: removeAttrs e [ "name" "includes" "excludes" "provides" "_" "policies" "meta" "description" ];
          expand =
            scope: es:
            let args = chan // scope; in
            lib.concatMap (
              e:
              let
                c = dungeon.classifyInc e;
                inline = r: lib.optional (content r != { }) (dungeon.effects.include (content r)) ++ expand scope (r.includes or [ ]);
              in
              if c.policy then [ ]
              else if c.slot == "ref" then [ (dungeon.effects.include e) ]
              # configure-aspects.mdx:134-139 kind (2): class + aspect-chain are bound where a class is resolved, not at a scope
              else if staticLeaf e then [ (dungeon.effects.include (leafAspect e)) ]
              # positional `ctx:` include: the whole scope ctx (deadbugs nixpkgs-forward-positional)
              else if positional e then expand scope [ (e scope) ]
              else if builtins.isFunction e then
                lib.optionals (builtins.all (k: args ? ${k}) (builtins.attrNames (lib.filterAttrs (_: opt: !opt) (lib.functionArgs e)))) (inline (e (builtins.intersectAttrs (lib.functionArgs e) args)))
              else inline e
            ) es;
        in
        {
          name = "${n}.fnIncs";
          fn = lib.setFunctionArgs (
            scope:
            if positional f then expand scope [ (f scope) ]
            else
              let r = f (builtins.intersectAttrs (lib.functionArgs f) (chan // scope)); in
              # a fn result's excludes are live too: exclude effects, read by route.nix excludedAt over the scope
              expand scope (r.includes or [ ]) ++ map dungeon.effects.exclude (builtins.filter (x: builtins.isAttrs x && x ? name) (r.excludes or [ ]))
          # host/user are advertised optional so nested fn includes see them when the scope has them (content.nix denArgs)
          ) ({ host = true; user = true; } // builtins.mapAttrs (k: opt: opt || chan ? ${k}) (lib.functionArgs f));
        };
      polsAt =
        n: a:
        if builtins.isFunction a then { ${n} = [ (fnIncs n a) ]; } else
        {
          ${n} =
            map (x: if x.e ? __isPolicy then x.e else { fn = x.e; name = "${n}.when${toString x.i}"; }) (builtins.filter (x: x.inc.policy) (inl a));
        }
        // lib.foldl' (acc: x: acc // { ${anon n x.i} = [ (fnIncs (anon n x.i) x.e) ]; }) { } (builtins.filter (x: builtins.isFunction x.e && !staticLeaf x.e) (inl a))
        // lib.foldl' (acc: x: acc // polsAt (anon n x.i) (inlOnly x.e)) { } (builtins.filter (x: dungeon.inlineAttrs x.e) (inl a))
        // lib.foldl' (acc: k: acc // polsAt k.p k.v) { } (kidList n a);
    in
    {
      inherit tree;
      # the include element as written, per anon slot: an unregistered class is read from it by name (resolve.nix)
      rawAnons = lib.concatMapAttrs (n: a: let at = n: a: builtins.listToAttrs (map (x: { name = anon n x.i; value = x.e; }) (inl a)) // lib.foldl' (acc: k: acc // at k.p k.v) { } (if builtins.isAttrs a then kidList n a else [ ]); in at n (un a)) tree;
      # site -> sightings, merged across definitions by the `inlineSites` option (view.nix)
      sites = lib.zipAttrsWith (_: lib.concatLists) (lib.concatLists (lib.mapAttrsToList (n: a: sitesAt n (un a)) tree));
      polIncs = lib.concatMapAttrs (n: a: polsAt n (un a)) (lib.filterAttrs (_: v: builtins.isAttrs v || builtins.isFunction v) (if builtins.isAttrs raw then raw else { }));
      # include slots become refs to the hoisted anons; `policies` is stripped (policy records live in the `policies` field)
      fixed =
        den: sites:
        let
          reg = den.rawAspects or den.aspects;
          fix = n: a: a // { includes = map (x: if x.inc.slot == "anon" then lib.getAttrFromPath (dungeon.aspectPath reg (canon sites n x)) reg else if x.inc.slot == "ref" && builtins.isAttrs x.e then removeAttrs x.e [ "__functor" ] else x.e) (builtins.filter (x: x.inc.slot != null) (inl a)); };
          fixTree = n: a: if builtins.isAttrs a then mapKids fixTree n (if builtins.isList (a.includes or null) then fix n a else a) else a;
          strip = a: if builtins.isAttrs a then removeAttrs a [ "policies" ] else a;
          # an inline element's own inline includes are its nested keys `<i>` (registry `<anon>/<i>`, resolved by aspectPath)
          fixA = p: e: strip (fixTree p e) // builtins.listToAttrs (map (x: { name = toString x.i; value = anonVal fixA (anon p x.i) x.e; }) (inl e));
        in
        builtins.mapAttrs (under (n: a: strip (fixTree n a))) tree // { __anons = lib.concatMapAttrs (n: a: anonsAt fixA n (un a)) tree; };
      recs = lib.concatMapAttrs (n: a: lib.optionalAttrs (builtins.isAttrs (un a) && builtins.isAttrs ((un a).policies or null)) { ${n} = builtins.mapAttrs (p: fn: { __isPolicy = true; inherit fn; name = "${n}.${p}"; }) (un a).policies; }) tree;
    };
}
