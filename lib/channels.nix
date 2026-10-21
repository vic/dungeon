# Quirk channels: pipe policies mark consumer hosts; emissions are aspect quirk keys read per host (G1: lazy cross-config).
dungeon: {
  channels = {
    # shortcut: inert effect descriptors (docs explanation/policies.mdx s resolve); no routing yet, upgrade when policies fire.
    lib.policy.resolve = {
      __functor = _: bindings: { __effect = "resolve"; inherit bindings; };
      to = kind: bindings: { __effect = "resolve"; inherit kind bindings; };
    };
    lib.policy.include = dungeon.effects.include;
    # reference/policies.mdx:142-151: module straight into `class`; at the root (`path` = []) that is an include of `{ <class> = module; }`.
    # non-empty `path` (nest mode): a provide effect delivered by scopes.nix (tutorials/microvm.mdx stage 3).
    lib.policy.provide = { class, module, path ? [ ] }@spec: if path != [ ] then dungeon.effects.provide spec else dungeon.effects.include { ${class} = module; };
    lib.policy.exclude = dungeon.effects.exclude;
    lib.policy.route = dungeon.effects.route;
    # when pred inner: guard over scope ctx only. hasAspect (closure membership) is NOT provided: reading it from a policy would cycle through the closure.
    lib.policy.when =
      pred: inner:
      let
        run = ctx: x:
          if builtins.isList x then builtins.concatMap (run ctx) x
          else if builtins.isAttrs x && x ? fn then run ctx x.fn
          else if builtins.isFunction x then run ctx (x (builtins.intersectAttrs (builtins.functionArgs x) ctx))
          else if builtins.isAttrs x && x ? __effect then [ x ]
          else [ (dungeon.effects.include x) ];
      in
      {
        __functionArgs = builtins.functionArgs pred;
        __functor = _: ctx: if pred (builtins.intersectAttrs (builtins.functionArgs pred) ctx) then run ctx inner else [ ];
      };
    lib.policy.mkPolicy = name: fn: { __isPolicy = true; inherit name fn; };
    lib.policy.instantiate = x: { __effect = "instantiate"; value = x; };
    # reference/quirks.mdx:109-318 pipe builder: `pipe.from` is a policy effect; stages are inert records read by `modules`.
    lib.policy.pipe =
      let
        st = kind: extra: { __stage = kind; } // extra;
      in
      {
        from = key: stages: { __effect = "pipe"; key = if builtins.isAttrs key then key.name else key; inherit stages; };
        filter = f: st "filter" { inherit f; };
        transform = f: st "transform" { inherit f; };
        fold = f: init: st "fold" { inherit f init; };
        append = value: st "append" { inherit value; };
        for = f: st "for" { inherit f; };
        withProvenance = st "withProvenance" { };
        as = target: st "as" { target = if builtins.isAttrs target then target.name else target; };
        expose = st "expose" { };
        collect = pred: st "collect" { inherit pred; };
        collectAll = pred: st "collectAll" { inherit pred; };
        broadcast = pred: st "broadcast" { inherit pred; };
        to = aspects: st "to" { inherit aspects; };
      };
    # `_module.args` per quirk for host h's OS eval; allHosts = name -> { host; config (lazy final OS config) }.
    # A quirk pool is a gen-view channel (gen-view compositions.nix:111) over the scope graph `den:fleet` <-parent- scopes,
    # data authored only at the gathered scopes (authoring is the declaration: gen-view README "The data component");
    # value stages are gen-view transforms (gen-view transform.nix: map :69, over :124), applied in list order.
    # `targeted` = aspect name -> { <quirk> = pipe output } for `pipe.to` pipes (reference/quirks.mdx:297-301): no gen-view
    # facility delivers per consumer, so route.nix binds it into those aspects' class modules (gen-bind wrap).
    modules = world: allHosts: h: sibs: (dungeon.channels.of world allHosts h sibs).modules;
    of =
      world: allHosts: h: sibs:
      let
        v = dungeon.gen.view;
        sc = dungeon.gen.scope;
        root = "den:fleet";
        labels = v.edgeLabels { letters = [ "parent" ]; };
        relations = v.relations { names = [ "quirk" ]; };
        admission = sc.wellFormed { alphabet = labels.letters; expression = "parent"; };
        order = sc.labelOrder { alphabet = labels.letters; layers = [ [ "parent" ] ]; endOfPath = -1; };
        identityMark = sc.labelOrder { alphabet = labels.letters; layers = [ [ "parent" ] ]; endOfPath = 0; };
        # relation of quirk k over `data` = [ { scope; datum = [ value ]; } ]; authored order is kept
        relationOf =
          k: data:
          let
            carrier = v.carrier {
              inherit labels relations;
              relatumLabels = v.relatumLabels { names = [ ]; };
              labelWellFormedness = admission;
              labelOrder = order;
              dataOrder = v.dataOrder { channel = k; keyOf = _: k; };
            };
          in
          v.viewRelation {
            engine = sc;
            definition = v.compositions.channel {
              channel = k;
              relation = "quirk";
              inherit root admission order;
              direction = "inbound";
              wellFormed = _: true;
              tieSet = v.tieSets.union;
              empty = [ ];
              combine = v.combines.listAppend;
              dedup = v.dedups.none;
            };
            graph = v.scopeGraph {
              inherit carrier;
              scopes = [ root ] ++ map (d: d.scope) data;
              edges.parent = id: if id == root then [ ] else [ root ];
              data = map (d: { inherit (d) scope datum; relation = "quirk"; }) data;
            };
            marks = _: [ ];
            orderMark = identityMark;
          };
        # one value stage over a relation; merged contributions (append/fold/for) land at the consuming scope `self`
        valueStage =
          self: ctxOf: r: s:
          let
            name = "${r.name}>${s.__stage}";
            each = f: v.transform.map { relation = r; inherit name f; };
            whole = f: v.transform.over { relation = r; inherit name; f = cs: f cs; };
            all = cs: builtins.concatMap (c: c.datum) cs;
            at = datum: { scope = self; inherit datum; };
            fns = {
              filter = each (c: builtins.filter s.f c.datum);
              transform = each (c: map s.f c.datum);
              withProvenance = each (c: map (x: { value = x; source = ctxOf c.scope; }) c.datum);
              append = whole (cs: cs ++ [ (at [ s.value ]) ]);
              fold = whole (cs: [ (at [ (builtins.foldl' s.f s.init (all cs)) ]) ]);
              for = whole (cs: let o = s.f (all cs); in if builtins.isList o then [ (at o) ] else throw "den: pipe.for must return a list (got ${builtins.typeOf o}); wrap it as [ x ]");
            };
          in
          if fns ? ${s.__stage} then fns.${s.__stage} else r;
        known = [ "filter" "transform" "withProvenance" "append" "fold" "for" "as" "expose" "collect" "collectAll" "to" ];
        checkStages =
          where: p:
          let
            kinds = map (s: s.__stage or (throw "den: pipe `${p.key}` at ${where}: a stage is not a pipe stage")) p.stages;
            bad = builtins.filter (k: !builtins.elem k known) kinds;
            count = k: builtins.length (builtins.filter (x: x == k) kinds);
          in
          if bad != [ ] then throw "den: pipe `${p.key}` at ${where}: stage pipe.${builtins.head bad} is not supported (needs per-aspect/per-scope delivery)"
          else if count "for" > 1 then throw "den: pipe `${p.key}` at ${where}: at most one pipe.for per pipe per scope (reference/quirks.mdx:184)"
          else if count "collect" + count "collectAll" > 1 then throw "den: pipe `${p.key}` at ${where}: more than one collect stage"
          else p;
        # the one policy firer (policy.nix:7)
        pipesAt =
          where: ctx: pols:
          map (checkStages where) (
            dungeon.effectsOf "pipe" (
              dungeon.firePols ctx pols
            )
          );
        # a raw fn in schema includes is a policy named by its slot (policy.nix fired).
        # shortcut: `policy.when` functors are not fired here: their guard reads route.nix's projected `host.hasAspect` (route.nix hostE), which this ctx lacks; fire them once channels reads route's scope ctx.
        polsOf =
          kind: cl:
          builtins.concatMap (p: if p.__isPolicy or false then [ p ] else if builtins.isFunction p then [ { name = "schema.${kind}"; fn = p; } ] else [ ]) (world.schema.${kind}.includes or [ ])
          ++ dungeon.uniqPols (builtins.concatMap (a: a.policyIncs) cl);
        clOf = n: if world.aspects ? ${n} then dungeon.closure world.aspects world.aspects.${n} else [ ];
        # policy.exclude of the host scope policies drops those aspects (by name, as route.nix excludedAt).
        # shortcut: re-fires host policies beside route.nix; read route's host membership (act.members) once hosts.nix threads it.
        hostCl =
          n:
          let
            # the host scope as route.nix hostBase: default + schema.host.includes refs + instance includes + host aspect
            cl = dungeon.closure world.aspects world.aspects.default ++ dungeon.schemaCl world.schema world.aspects false "host" ++ dungeon.schemaCl { host.includes = (hostOf n).includes or [ ]; } world.aspects true "host" ++ clOf n;
            ex = map (e: e.value.name) (builtins.filter (e: e.value ? name) (dungeon.effectsOf "exclude" (dungeon.firePols { host = hostOf n; } (polsOf "host" cl))));
          in
          builtins.filter (a: !builtins.elem a.name ex) cl;
        # reference/quirks.mdx:69-79: lists auto-flatten; a fn is called with the scope ctx (a config thunk gets the producer config)
        emits =
          cl: ctx: k:
          builtins.concatMap (
            a:
            if a.quirks ? ${k} then
              let
                x = a.quirks.${k};
                r = if builtins.isFunction x then x (builtins.intersectAttrs (builtins.functionArgs x) ctx) else x;
              in
              if builtins.isList r then r else [ r ]
            else
              [ ]
          ) cl;
        hostOf = n: if n == h.name then h else allHosts.${n}.host;
        hostCtx = n: { host = hostOf n; inherit (allHosts.${n}) config; };
        # user producer config = its home-manager config, host config as osConfig (reference/quirks.mdx:327-333)
        userCtx = n: u: {
          host = hostOf n;
          user = (hostOf n).users.${u};
          osConfig = allHosts.${n}.config;
          config = allHosts.${n}.config.home-manager.users.${u} or (throw "den: quirk thunk of user `${u}`@`${n}` reads `config`, but the user has no home-manager config");
        };
        has = st: p: builtins.any (s: s.__stage == st) p.stages;
        runValue = self: ctxOf: r: p: builtins.foldl' (valueStage self ctxOf) r p.stages;
        # pipe.expose (reference/quirks.mdx:218-232): each user's pool after its value stages, lifted into the host pool
        exposed =
          n: k:
          builtins.concatMap (
            u:
            let
              cl = clOf u;
              ctx = userCtx n u;
              sid = "${u}@${n}";
              scopeCtx = { inherit (ctx) host user; };
              ps = builtins.filter (p: p.key == k && has "expose" p) (pipesAt "schema.user" scopeCtx (polsOf "user" cl));
            in
            builtins.concatMap (p: (runValue sid (_: scopeCtx) (relationOf k [ { scope = sid; datum = emits cl ctx k; } ]) p).value) ps
          ) (builtins.attrNames (hostOf n).users);
        local = n: k: emits (hostCl n) (hostCtx n) k ++ exposed n k;
        # self first, then sibling scopes (same parent) in attrName order (fleet.mdx:101-102); collectAll: every host
        sibOrder = [ h.name ] ++ builtins.filter (n: n != h.name && allHosts ? ${n}) sibs;
        allOrder = [ h.name ] ++ builtins.filter (n: n != h.name) (builtins.attrNames allHosts);
        # entity kind filtering (reference/quirks.mdx:244-248): a host scope is gathered only by a predicate requiring `host`
        matches = pred: n: (builtins.functionArgs pred) ? host && pred { host = hostOf n; } == true;
        gathered =
          p:
          let
            c = builtins.filter (s: s.__stage == "collect" || s.__stage == "collectAll") p.stages;
            pick = s: builtins.filter (matches s.pred) (if s.__stage == "collectAll" then allOrder else sibOrder);
            scopes = if c == [ ] then [ h.name ] else pick (builtins.head c);
          in
          relationOf p.key (map (n: { scope = n; datum = local n p.key; }) scopes);
        target =
          p:
          let
            a = builtins.filter (s: s.__stage == "as") p.stages;
            t = (builtins.head a).target;
          in
          if a == [ ] then p.key else if t == p.key then throw "den: pipe.as `${p.key}`: target must be a different pipe" else t;
        pipes = builtins.filter (p: !has "expose" p) (pipesAt "schema.host" { host = h; } (polsOf "host" (hostCl h.name)));
        out = p: { key = target p; value = (runValue h.name (n: { host = hostOf n; }) (gathered p) p).value; };
        toOf = p: builtins.filter (s: s.__stage == "to") p.stages;
        delivered = builtins.groupBy (o: o.key) (map out (builtins.filter (p: toOf p == [ ]) pipes));
        one = k: os: if builtins.length os == 1 then (builtins.head os).value else throw "den: ${toString (builtins.length os)} pipes deliver quirk `${k}` at host `${h.name}`";
        # only the named aspects receive a pipe.to pipe's data; other consumers see the unmodified pool (reference/quirks.mdx:299-300)
        toPairs = builtins.concatMap (p: let o = out p; in builtins.concatMap (s: map (a: { aspect = a.name or (throw "den: pipe.to `${p.key}`: target is not an aspect"); inherit (o) key value; }) s.aspects) (toOf p)) pipes;
      in
      {
        # a declared quirk is always bound; without a pipe it is the host scope's own pool (reference/quirks.mdx:97-104)
        modules = [ { _module.args = builtins.mapAttrs (k: _: local h.name k) (world.quirks or { }) // builtins.mapAttrs one delivered; } ];
        targeted = builtins.mapAttrs (a: ps: builtins.mapAttrs one (builtins.groupBy (o: o.key) ps)) (builtins.groupBy (o: o.aspect) toPairs);
      };
  };
}
