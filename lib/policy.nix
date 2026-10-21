# Policy scope tree (design-policy.md R1). Fire membership = gen.program model per scope (Q2: one model per depth, tree finite).
# Q1: string atoms "p:<i>" / "x:<builtin>", unary rules (closure.nix:9-13 precedent). Q3: only schema.<kind>.includes fire
# (explanation/policies.mdx:129-130 also lists aspect includes; deferred, fleet uses schema includes only).
dungeon: {
  # the one policy firer: { name; fn; } policies whose required args are bound in `args` (fleet.nix:19-21 resolveArgsSatisfied),
  # each effect tagged with its policy and index (synthetic inline names `<policy>#<i>`).
  firePols =
    args: pols:
    let
      fnArgs = p: dungeon.genLib.functionArgs p.fn;
      ready = p: builtins.all (n: args ? ${n}) (builtins.attrNames (dungeon.genLib.filterAttrs (_: opt: !opt) (fnArgs p)));
      fire = p: let r = p.fn (builtins.intersectAttrs (fnArgs p) args); in if builtins.isList r then r else [ r ];
    in
    builtins.concatMap (p: dungeon.genLib.imap0 (i: e: { inherit p i e; }) (fire p)) (builtins.filter ready pols);
  effectsOf = k: fx: map (x: x.e) (builtins.filter (x: (x.e.__effect or null) == k) fx);
  # kindless policy.resolve enriches the firing scope ctx (explanation/policies.mdx resolve); one stage: enriching policies see the base ctx
  enrich = args: pols: args // builtins.foldl' (acc: e: acc // e.bindings) { } (builtins.filter (e: !(e ? kind)) (dungeon.effectsOf "resolve" (dungeon.firePols args pols)));
  # reference/policies.mdx flake output traversal: builtin policies are named atoms.
  builtinPolicies = [ "flake-to-systems" "system-to-os-outputs" "system-to-hm-outputs" "host-to-users" "packages-to-flake" "system-to-flake-parts" "packages-to-flake-parts" ];
  policy =
    world:
    let
      idOf = p: if builtins.isAttrs p && p ? __builtin then p.__builtin else null;
      model =
        rules:
        dungeon.gen.program.model {
          program = dungeon.gen.program.program [ ] rules;
          interpretation = [ ];
          prior = null;
          complete = true;
        };
      mk =
        kind: ctx: excl0: path:
        let
          sch = world.schema.${kind} or { };
          excl = excl0 ++ builtins.filter (x: x != null) (map idOf (sch.excludes or [ ])) ++ (if kind == "flake" then builtins.filter (x: x != null) (map idOf (world.schema.flake-system.excludes or [ ])) else [ ]);
          incs = sch.includes or [ ];
          # excludes are authoritative: an excluded identity's fire atom is negated (expl:131)
          rules =
            map (x: { head = "x:${x}"; pos = [ ]; neg = [ ]; relata = [ ]; }) excl
            ++ builtins.genList (i: { head = "p:${toString i}"; pos = [ ]; neg = let id = idOf (builtins.elemAt incs i); in if id != null && builtins.elem id excl then [ "x:${id}" ] else [ ]; relata = [ ]; }) (builtins.length incs)
            ++ map (n: { head = "b:${n}"; pos = [ ]; neg = if builtins.elem n excl then [ "x:${n}" ] else [ ]; relata = [ ]; }) builtinNames;
          m = model rules;
          # fire atoms the model includes; builtin atoms are not functions
          fired = builtins.concatMap (i: let p = builtins.elemAt incs i; in if dungeon.isPol p || builtins.isFunction p then (if (m.resolve "p:${toString i}").included then [ (if p.__isPolicy or false then p else { name = "schema.${kind}"; fn = p; }) ] else [ ]) else [ ]) (builtins.genList (i: i) (builtins.length incs));
          eff = k: dungeon.effectsOf k (dungeon.firePols ctx fired);
          key = e: "${e.kind}=${e.bindings.${e.kind}.name or ""}";
        in
        {
          inherit kind ctx;
          # policy.instantiate custom spec at a custom-kind scope (reference/policies.mdx:162-172): class bucket of the
          # kind's includes + the instance's own includes, minus both excludes (custom-entity-kinds.mdx:47-49)
          customInsts =
            let
              inst = ctx.${kind};
              cl = dungeon.schemaCl world.schema world.aspects true kind ++ dungeon.schemaCl { ${kind}.includes = inst.includes; } world.aspects true kind;
              ex = map (b: b.name) (builtins.filter (b: builtins.isAttrs b && b ? name && !dungeon.isPol b) ((sch.excludes or [ ]) ++ inst.excludes));
              modulesOf = cls: map (a: dungeon.content.classModule { ${kind} = inst; } a.content.${cls}) (builtins.filter (a: a.content ? ${cls} && !builtins.elem a.name ex) cl);
              # a custom spec (class + instantiate + intoAttr); an entity (registered host) instantiates through hosts.nix
              custom = v: v ? class && v ? instantiate && v ? intoAttr && !builtins.any (s: world.hosts.${s} ? ${v.name or ""}) (builtins.attrNames world.hosts);
            in
            if builtins.elem kind [ "flake" "host" "user" ] then [ ] else map (e: { path = e.value.intoAttr; value = e.value.instantiate { modules = modulesOf e.value.class; }; }) (builtins.filter (e: custom e.value) (eff "instantiate"));
          on = n: (m.resolve "b:${n}").included;
          instantiated = map (e: e.value.name) (eff "instantiate");
          instEffs = eff "instantiate";
          children = map (e: mk e.kind (ctx // e.bindings) excl (path ++ [ (key e) ])) (builtins.filter (e: e ? kind && !(builtins.elem (key e) path)) (eff "resolve"));
        };
      builtinNames = dungeon.builtinPolicies;
      tree = mk "flake" { } [ ] [ ];
      scopes = s: [ s ] ++ builtins.concatMap scopes s.children;
      all = scopes tree;
      hostScopes = h: builtins.filter (s: s.kind == "host" && s.ctx.host.name == h.name) all;
    in
    {
      inherit tree;
      osOutputs = tree.on "system-to-os-outputs";
      instantiated = builtins.concatMap (s: s.instantiated) all;
      customInsts = builtins.concatMap (s: s.customInsts) all;
      # declared host.users first, then resolved user children of every scope of that host
      usersOf = h: h.users // builtins.listToAttrs (builtins.concatMap (hs: map (u: { name = u.ctx.user.name; value = u.ctx.user; }) (builtins.filter (s: s.kind == "user") (scopes hs))) (hostScopes h));
      # resolution-chain ctx of h's host scope besides `host` (e.g. a parent `environment`); {} when no policy scope resolves h
      chainOf = h: let s = hostScopes h; in if s == [ ] then { } else removeAttrs (builtins.head s).ctx [ "host" ];
      # same parent scope; no scope for h (no fleet) means all hosts
      siblingsOf = h: allNames:
        let p = builtins.filter (s: builtins.any (c: c.kind == "host" && c.ctx.host.name == h.name) s.children) all;
        in if p == [ ] then allNames else map (c: c.ctx.host.name) (builtins.filter (c: c.kind == "host") (builtins.head p).children);
    };
}
