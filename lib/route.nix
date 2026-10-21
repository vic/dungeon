# Per-host nixos module list: host closure first, then users, each aspect's user part before its nixos part (design-gen.md §3.8-9).
# `host` is the host entity (view.nix); users' entities come from host.users.
dungeon: {
  # schema.<kind>.includes elements join a closure: refs via their closure, inline attrs as anon aspects (policy elements fire separately).
  # a named element missing from the registry is skipped (host: builtin atoms live there) unless `strict`.
  # shortcut: inline attrs carry no includes of their own; elements do not enter activation membership (hasAspect).
  schemaCl =
    sch: aspects: strict: kind:
    let
      cl = dungeon.closure aspects;
      flat = x: if builtins.isList x then builtins.concatMap flat x else [ x ];
      # nested/namespace aspects are named `<parent>/<key>/...` and live inside their parent (closure.nix `at`)
      lookup = n: builtins.foldl' (e: s: if builtins.isAttrs e && e ? ${s} then e.${s} else null) aspects (dungeon.aspectPath aspects n);
      one = i: x:
        if !builtins.isAttrs x || dungeon.isPol x || x ? __builtin then [ ]
        else if x ? name then (let r = lookup x.name; in if r != null then cl r else if strict then throw "den: schema.${kind}.includes: unknown aspect `${x.name}`" else [ ])
        else if dungeon.inlineAttrs x then [ { name = "schema.${kind}#${toString i}"; content = x; includes = [ ]; quirks = { }; policyIncs = [ ]; } ]
        else [ ];
    in
    builtins.concatLists (dungeon.genLib.imap0 one (flat (sch.${kind}.includes or [ ])));
  # policy.route: fromClass content of the scope closure re-delivered as intoClass content (reference/policies.mdx route).
  # shortcut: only user/home scope fires routes; path != [] needs attrset (non-function) content.
  routes = defaultCl: hostBase: args: scope: dungeon.routesOf (dungeon.effectsOf "route" (dungeon.firePols args (dungeon.uniqPols (builtins.concatMap (a: a.policyIncs) (defaultCl ++ hostBase ++ scope))))) scope;
  uniqPols = ps: builtins.attrValues (builtins.listToAttrs (map (p: { name = p.name; value = p; }) ps));
  routesOf =
    effs: scope:
    let
      wrap = path: c: builtins.foldl' (v: i: { ${builtins.elemAt path (builtins.length path - 1 - i)} = v; }) c (builtins.genList (i: i) (builtins.length path));
      # guard (reference/policies.mdx:137-140) reads the target module args: gate `config`, so option declarations never depend on it
      guarded = e: m: if !(e ? guard) then m else if builtins.isAttrs m && !(m ? imports) && !(m ? config) && !(m ? options) then (margs: { config = if e.guard margs then m else { }; }) else throw "den: policy.route guard over ${e.fromClass} module functions/imports: not built yet";
      one = e: {
        name = "route#${e.fromClass}->${e.intoClass}";
        content.${e.intoClass} = { imports = map (a: guarded e (wrap (if e ? intoPath then (if builtins.isFunction e.intoPath then e.intoPath { } else e.intoPath) else e.path) a.content.${e.fromClass})) (builtins.filter (a: a.content ? ${e.fromClass}) scope); };
        includes = [ ]; quirks = { }; policyIncs = [ ];
      };
    in
    map one effs;
  route =
    sch: aspects: host: users:
    let
      cl = dungeon.closure aspects;
      # a host with no declared aspect contributes nothing (users are treated the same below)
      schemaCl = dungeon.schemaCl sch aspects;
      schemaRefs = schemaCl false "host";
      # schema.hm-host.includes (batteries.mdx): only on hosts with an HM user, applied in `hm`
      hmHostCl = schemaCl true "hm-host";
      # instance-own includes join the host scope like schema.host.includes (custom-entity-kinds.mdx:47-49)
      hostBase = schemaRefs ++ dungeon.schemaCl { host = { inherit (host) includes; }; } aspects true "host" ++ (if aspects ? ${host.name} then cl aspects.${host.name} else [ ]);
      # schema.<kind>.includes policies (possibly nested in `includes` lists); non-policy elements are skipped
      schemaPols =
        kind:
        let
          go = x:
            if builtins.isList x then builtins.concatMap go x
            else if (dungeon.classifyInc x).policy || builtins.isFunction x then [ (if x.__isPolicy or false then x else { name = "schema.${kind}"; fn = x; }) ]
            else if builtins.isAttrs x && builtins.isList (x.includes or null) then go x.includes
            else [ ];
        in
        go (sch.${kind}.includes or [ ]);
      # hasAspect over the policy-free closure (policy-added aspects excluded, else it would cycle)
      hostProv = (aspects.${host.name} or { }).provides or { };
      provCl = k: if builtins.isAttrs (hostProv.${k} or null) then cl hostProv.${k} else [ ];
      # provides.<k> of one aspect as a closure (where-config-lands.mdx:68-72)
      provOf = k: a: let p = (a.provides or { }).${k} or null; in if builtins.isAttrs p then cl p else [ ];
      # to-users of the host aspect and of every aspect in its closure reach every user (where-config-lands.mdx:70)
      tuCl = builtins.concatMap (provOf "to-users") hostBase;
      # to-users of an aspect in a user's own closure / provides.<user> reach that user
      relayCl = u: builtins.concatMap (provOf "to-users") (userCl u ++ provCl u);
      # hasAspect reads membership m (scope -> names) of the previous activation pass (design-activation.md R2, PM ruling Q3c)
      hasFn = f: { __functor = _: f; forAnyClass = f; };
      names = map (b: b.name);
      hostE = m: host // { hasAspect = hasFn (a: builtins.elem a.name (m host.name)); };
      # static enrichers: schema.host + aspect policies of the policy-free host scope (membership-read would cycle)
      enrichPols = schemaPols "host" ++ builtins.concatMap (a: a.policyIncs) (defaultCl ++ hostBase);
      hostArgs = m: dungeon.enrich { host = hostE m; } enrichPols;
      # policy.exclude of host-closure/schema policies drops those aspects from the scope subtree (names; shortcut: not the excluder's exclusive subtree).
      excludedAt = args: pols: map (e: e.value.name) (builtins.filter (e: e.value ? name) (dungeon.effectsOf "exclude" (dungeon.firePols args pols)));
      # schema.<kind>.excludes aspect refs: authoritative over includes (reference/schema.mdx, policies.mdx:245)
      exNames = xs: map (b: b.name) (builtins.filter (b: builtins.isAttrs b && b ? name && !(b.__isPolicy or false) && !(b ? __builtin)) xs);
      schemaEx = kind: exNames (sch.${kind}.excludes or [ ]);
      # instance-own excludes are as authoritative as the kind's (custom-entity-kinds.mdx:47-49)
      # the host aspect's own excludes cover the whole host scope, schema-included aspects too (deadbugs schema-included-parametric-exclude)
      hostEx = m: schemaEx "host" ++ exNames host.excludes ++ exNames ((aspects.${host.name} or { }).excludes or [ ]) ++ excludedAt (hostArgs m) (builtins.concatMap (a: a.policyIncs) hostBase ++ schemaPols "host");
      hostCl = act.members host.name;
      userScope = u: "${u}@${host.name}";
      allUsers = users ++ builtins.attrNames host.users;
      scopeNames = [ host.name ] ++ map userScope allUsers;
      # hasAspect view of a scope: default + host members (+ the user scope's own); excluded aspects are absent
      memOf = a: s: names defaultCl ++ names (a.members host.name) ++ (if s == host.name then [ ] else names (a.members s));
      # pass -1: policy-free static closures
      # user aspect (`u@host` wins) + host child named after the user (where-config-lands.mdx:72, per user: the every-user reach is a v1 defect, L79-85)
      # `tux.provides.igloo`: tux home + igloo OS, only on igloo (where-config-lands.mdx:77-78)
      userCl = u: (let r = aspects."${u}@${host.name}" or aspects.${u} or null; in if r == null then [ ] else cl r ++ provOf host.name r) ++ (let c = (aspects.${host.name} or { }).${u} or null; in if builtins.isAttrs c && c ? name then cl c else [ ]);
      userStatic = u: defaultCl ++ hostBase ++ tuCl ++ provCl u ++ userCl u ++ relayCl u;
      m0 = s: (builtins.listToAttrs (map (u: { name = userScope u; value = names (userStatic u); }) allUsers) // { ${host.name} = names (defaultCl ++ hostBase ++ tuCl); }).${s};
      # pass k fires policies with hasAspect reading pass k-1 membership, until membership is unchanged; oscillation throws
      passBound = builtins.length (builtins.attrNames aspects) + 1;
      fix =
        k: m:
        let
          a = dungeon.mkActivation (scopesOf m);
          m' = memOf a;
          same = builtins.all (s: builtins.sort builtins.lessThan (m s) == builtins.sort builtins.lessThan (m' s)) scopeNames;
        in
        if same then a else if k >= passBound then throw "den: policy activation did not converge" else fix (k + 1) m';
      act = fix 1 m0;
      mF = memOf act;
      # one model per host tree: host scope + one scope per user
      # policies of every aspect in scope s's previous-pass membership (policy-added ones included); synthetic names have none
      memPols = m: s: builtins.concatMap (n: if aspects ? ${n} then builtins.concatMap (b: if b.name == n then b.policyIncs else [ ]) (cl aspects.${n}) else [ ]) (m s);
      scopesOf =
        m:
        { ${host.name} = { cands = hostBase ++ tuCl ++ adds (hostArgs m) (schemaPols "host" ++ memPols m host.name); ex = hostEx m; }; }
        // builtins.listToAttrs (map (u: { name = userScope u; value = userCands m u; }) allUsers);
      userEnt = m: u: host.users.${u} // { host = hostE m; hasAspect = hasFn (a: builtins.elem a.name (m (userScope u))); };
      argsOf' = m: u: dungeon.enrich { host = hostE m; user = userEnt m u; } enrichPols;
      argsOf = argsOf' mF;
      # OS class content: host class (schema.mdx:141: nixos or darwin) + `os` class (reference/batteries.mdx:53-57)
      os = host.class;
      nixosOf = nixosOver [ ];
      # `keys` of args shadow same-named module-system args (pipe.to data, content.nix classModuleOver)
      nixosOver = keys: args: a: builtins.concatMap (k: if a.content ? ${k} then [ (dungeon.content.classModuleOver keys args a.content.${k}) ] else [ ]) [ os "os" ];
      userCands =
        m: u:
        let
          pols = schemaPols "user" ++ memPols m (userScope u);
        in
        {
          cands = userCl u ++ tuCl ++ provCl u ++ relayCl u ++ adds (argsOf' m u) pols;
          ex = hostEx m ++ schemaEx "user" ++ excludedAt (argsOf' m u) pols;
        };
      userClosure =
        u:
        let
          base = act.members (userScope u) ++ schemaCl true "user";
        in
        base ++ routes (argsOf u) (defaultCl ++ base);
      # Aspect policies of the host closure fire at user scope; include effects add aspects (inline class attrs -> synthetic "<policy>#<i>").
      # shortcut: no gen.program stratification (R1), policies of policy-included aspects and per-scope dedup come later.
      adds =
        args: pols:
        let
          eff = dungeon.firePols args pols;
          declared = n: let r = builtins.foldl' (e: s: if builtins.isAttrs e && e ? ${s} then e.${s} else null) aspects (dungeon.aspectPath aspects n); in if r == null then throw "den: aspect ${n} not declared" else r;
          inc = x:
            if (x.e.__effect or null) != "include" then [ ]
            # parametric include `{ host }: { <class> = ...; }` binds the scope ctx (tutorials/microvm.mdx stage 1)
            else if builtins.isFunction x.e.value then [ { name = "${x.p.name}#${toString x.i}"; content = x.e.value (builtins.intersectAttrs (dungeon.genLib.functionArgs x.e.value) args); includes = [ ]; quirks = { }; policyIncs = [ ]; } ]
            else if x.e.value ? name then cl (declared x.e.value.name)
            else if x.e.value ? includes then builtins.concatMap (b: cl (declared b.name)) x.e.value.includes
            else [ { name = "${x.p.name}#${toString x.i}"; content = x.e.value; includes = [ ]; quirks = { }; policyIncs = [ ]; } ];
        in
        builtins.concatMap inc eff;
      # one firer per scope: schema.user policies + aspect policies of the routed scope (D1)
      routes = args: scope: dungeon.routesOf (dungeon.effectsOf "route" (dungeon.firePols args (schemaPols "user" ++ dungeon.uniqPols (builtins.concatMap (a: a.policyIncs) (defaultCl ++ hostBase ++ scope))))) scope;
      userVal = u: a: dungeon.flatten (argsOf u) [ a.content.user ];
      userPart = u: a: { users.users.${u} = userVal u a; };
      # fn aspects project every class key; an empty projection must not declare users.users.<u>
      isEmpty = v: if v._type or null == "merge" then builtins.all isEmpty v.contents else v == { };
      hasUser = u: a: a.content ? user && !isEmpty (userVal u a);
      # den.default is walked in both scopes, first (docs silent on order); its nixos lands once, in the host list.
      defaultCl = cl aspects.default;
      defaultUser = u: map (userPart u) (builtins.filter (hasUser u) defaultCl);
      userModules = u: defaultUser u ++ map (userPart u) (builtins.filter (hasUser u) (userClosure u));
      # default/host-closure parts whose fn needs `user` bind per user scope (fan out, land on the host) and are skipped at host scope (issue-609, where-config-lands.mdx:55)
      needsUser =
        a:
        let
          fnNeeds = v: (builtins.isFunction v || (builtins.isAttrs v && v ? __functor)) && (dungeon.genLib.functionArgs v) ? user;
          go = v: fnNeeds v || (builtins.isAttrs v && builtins.isList (v.imports or null) && builtins.any go v.imports);
        in
        a.content ? ${os} && go a.content.${os};
      # provides.to-hosts of every aspect in a user's closure (incl. policy-added) runs once per user, landing in the host's nixos (where-config-lands.mdx)
      toHosts =
        u:
        let
          # an aspect reached through to-hosts brings its own to-hosts along (late-registered-to-hosts projection-chain); seen cuts cycles
          th = seen: a: builtins.concatMap (b: if builtins.elem b.name seen then [ ] else [ b ] ++ th (seen ++ [ b.name ]) b) (provOf "to-hosts" a);
        in
        builtins.concatMap (nixosOf (quirkArgs u)) (builtins.concatMap (th [ ]) (userClosure u));
      # user-scope class modules read the user scope's own quirk pool, not the host's (reference/quirks.mdx:97-104); bound per module, so it never leaks to host-scope modules
      # shortcut: only keys the user closure emits are bound and a config-reading user thunk throws; upgrade with the user HM config ctx (channels.nix userCtx).
      quirkArgs = u: quirkArgsOf u (argsOf u) (userClosure u);
      # quirk thunks are called with `ctx`; the bound args stay argsOf u + the pools of `cl`
      quirkArgsOf =
        u: ctx: cl:
        let
          val = k: x: if !builtins.isFunction x then x else if builtins.all (n: ctx ? ${n}) (builtins.attrNames (dungeon.genLib.filterAttrs (_: o: !o) (builtins.functionArgs x))) then x (builtins.intersectAttrs (builtins.functionArgs x) ctx) else throw "den: quirk `${k}` thunk at user `${u}` reads args beyond the user scope ctx (config): not built yet";
          pool = k: builtins.concatMap (a: if a.quirks ? ${k} then (let r = val k a.quirks.${k}; in if builtins.isList r then r else [ r ]) else [ ]) cl;
        in
        argsOf u // builtins.listToAttrs (map (k: { name = k; value = pool k; }) (builtins.concatMap (a: builtins.attrNames a.quirks) cl));
      # OS content lands once per host: a user-closure aspect whose minted identity is already in the host scope is not re-delivered (cross-scope dedup by id_hash; synthetic records carry none)
      hostIds = builtins.listToAttrs (map (a: { name = a.id_hash; value = true; }) (builtins.filter (a: a ? id_hash) (defaultCl ++ hostCl ++ tuCl)));
      # every host user gets users.users.<u> even with no user-class content
      forUser =
        u:
        [ { users.users.${u} = { }; } ]
        ++ toHosts u
        ++ defaultUser u
        ++ builtins.concatMap (nixosOf (argsOf u)) (builtins.filter needsUser (defaultCl ++ hostCl))
        ++ builtins.concatMap (
          a: (if hasUser u a then [ (userPart u a) ] else [ ]) ++ (if builtins.elem a.name (map (b: b.name) tuCl) || hostIds ? ${a.id_hash or ""} then [ ] else nixosOf (argsOf u) a)
        ) (userClosure u);
      # `targeted` (channels.nix of): aspect name -> pipe.to quirk data, bound into that aspect's host-scope OS modules.
      # shortcut: user-scope (forUser) OS modules of a targeted aspect see the unmodified pool; upgrade when a fleet targets one.
      modulesFor = targeted: let hostScopeCl = builtins.filter (a: !needsUser a) (defaultCl ++ hostCl); hostRoutes = dungeon.routesOf (dungeon.effectsOf "route" (dungeon.firePols (hostArgs mF) (schemaPols "host" ++ dungeon.uniqPols (builtins.concatMap (a: a.policyIncs) hostScopeCl)))) hostScopeCl;
          hostOf' = a: let t = targeted.${a.name} or { }; in nixosOver (builtins.attrNames t) ({ inherit host; } // t) a;
        in builtins.concatMap hostOf' (hostScopeCl ++ hostRoutes) ++ builtins.concatMap forUser users
        # policy.provide effects of the host scope and its custom child scopes (scopes.nix, gen-scope nta)
        ++ dungeon.scopes.delivered sch host (hostArgs mF) (schemaPols "host" ++ memPols mF host.name);
    in
    rec {
      inherit userModules argsOf userClosure defaultCl modulesFor hostCl;
      # home-manager.users.<u> gets default's then the user closure's homeManager parts; HM nixos module once, only if some user opts in.
      hm =
        inputs: hmUsers: chain:
        let
          # host-aspects re-resolves the host tree at the user scope: its quirk emissions join the user pool, thunks called with the
          # host scope's resolution-chain ctx (`chain`, e.g. a parent `environment`) besides { host, user } (reference/quirks.mdx:97-104)
          hmArgs = u: quirkArgsOf u (chain // argsOf u) (userClosure u ++ viaHost u);
          hmOf = u: a: if a.content ? homeManager then [ (dungeon.content.classModule (hmArgs u) a.content.homeManager) ] else [ ];
          # host-aspects opt-in: host closure parts not already in the user's closure
          viaHost = u: let uc = userClosure u; seen = map (b: b.name) (defaultCl ++ uc); in
            if builtins.elem "host-aspects" (map (b: b.name) uc) then builtins.filter (a: !(builtins.elem a.name seen)) hostBase else [ ];
        in
        if hmUsers == [ ] then
          [ ]
        else
          # schema.mdx:150: inputs.home-manager.<class>Modules.home-manager
          [ inputs.home-manager."${os}Modules".home-manager ]
          ++ builtins.concatMap (nixosOf { inherit host; }) hmHostCl
          ++ map (u: { home-manager.users.${u}.imports = builtins.concatMap (hmOf u) (defaultCl ++ hmHostCl ++ userClosure u ++ viaHost u ++ routes (argsOf u) (viaHost u)); }) hmUsers;
      # host scope fires routes too (schema.host + aspect policies of the host closure), over the host scope content
      # shortcut: a den.default route also fires per user scope; default fromClass content then lands twice, dedup with minted identity (D4).
      modules = modulesFor { };
      # policy.instantiate custom spec (reference/policies.mdx:162-172): class bucket of the host scope subtree (host, then users)
      classModules = classModulesWith (_: [ ]);
      # `raw a`: class content the typed aspect does not carry (an undeclared class requested by name, resolve.nix rawClassOf)
      classModulesWith =
        raw: cls:
        let
          of = args: a: map (dungeon.content.classModule args) ((if a.content ? ${cls} then [ a.content.${cls} ] else [ ]) ++ raw a);
        in
        builtins.concatMap (of { inherit host; }) (defaultCl ++ hostCl)
        ++ builtins.concatMap (u: builtins.concatMap (of (argsOf u)) (builtins.filter (a: !builtins.elem a.name (names tuCl)) (userClosure u))) users;
      # one user's bucket of `cls`: host scope content bound with that user's args (per-user fan, issue-644), then the user's own closure
      userClassModulesWith =
        raw: u: cls:
        let
          of = a: map (dungeon.content.classModule (argsOf u)) ((if a.content ? ${cls} then [ a.content.${cls} ] else [ ]) ++ raw a);
          hostScope = defaultCl ++ hostCl;
        in
        builtins.concatMap of (hostScope ++ builtins.filter (a: !builtins.elem a.name (names hostScope)) (userClosure u));
      # instantiate effects of schema.host.includes policies (tutorials/terranix-demo.mdx:44-61)
      instantiates = builtins.filter (e: e.value ? class) (dungeon.effectsOf "instantiate" (dungeon.firePols (hostArgs mF) (schemaPols "host")));
    };
}
