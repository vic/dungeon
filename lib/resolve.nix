# den.lib.aspects.resolve class aspect -> { imports } (reference/lib.mdx:24-27): the class content of the aspect's include tree.
# Context: values pinned by parametric.fixedTo (reference/lib-deprecated.mdx:41-49) + `class`/`aspect-chain` for provider fns
# (guides/custom-classes.mdx `{ class, aspect-chain }:`). Provider fns whose required args are not in scope do not fire.
dungeon: {
  resolve =
    world: class: root:
    if root.__entityKind or null == "host" then dungeon.resolveEntityModule world class root.ctx.host else
    let
      lib = dungeon.genLib;
      ctx = root.__ctx or { };
      scope = ctx // { inherit class; aspect-chain = [ root ]; };
      required = f: builtins.attrNames (lib.filterAttrs (_: opt: !opt) (lib.functionArgs f));
      call = s: f: f (builtins.intersectAttrs (lib.functionArgs f) s);
      # world aspects carry normalized content (view.nix norm); inline ones are raw attrsets
      isWorld = a: builtins.isAttrs a && a ? content && a ? policyIncs;
      # class content asking only for pinned ctx is applied here; module args stay for the module system.
      # shortcut: content mixing ctx and module args is passed unbound; upgrade with gen.bind.wrap when a template needs it.
      # Gen class content is `{ imports = [ .. ]; }` (as content.nix walks it)
      bind =
        m:
        if lib.isFunction m && required m != [ ] && builtins.all (k: ctx ? ${k}) (required m) then call ctx m
        else if builtins.isAttrs m && builtins.isList (m.imports or null) then m // { imports = map bind m.imports; }
        else m;
      # The requested class is a class key whatever the registry says (deadbugs-issue-261, issue-645). A class Gen does not
      # declare never reaches typed `content`, so it is read by name from the raw definitions of each closure member.
      rawClass = m: map bind (dungeon.rawClassOf world class scope m);
      expand =
        a:
        if isWorld a then
          # fn aspects: their result's includes are live (normalize.nix fnIncs); shortcut: top-level fn aspects only (rawFns)
          builtins.concatMap (m: lib.optional (m.content ? ${class}) (bind m.content.${class}) ++ rawClass m ++ (if world.rawFns ? ${m.name} && builtins.all (k: scope ? ${k}) (required world.rawFns.${m.name}) then expand { includes = (call scope world.rawFns.${m.name}).includes or [ ]; } else [ ])) (dungeon.closure world.rawAspects a)
        else if lib.isFunction a then
          if builtins.all (k: scope ? ${k}) (required a) then expand (call scope a) else [ ]
        else if builtins.isAttrs a then
          lib.optional (a ? ${class}) (bind a.${class}) ++ builtins.concatMap expand (a.includes or [ ])
        else
          throw "den.lib.aspects.resolve: include is not an aspect or function";
    in
    { imports = expand root; };
  # The requested class is a class key whatever the registry says (deadbugs-issue-261, issue-645). A class Gen does not
  # declare never reaches typed `content`, so it is read by name from the raw definitions of aspect `m` (and the inline
  # includes of a fn result, as a static leaf's forward returns them). Unbound: the caller binds its own ctx.
  rawClassOf =
    world: class: scope: m:
    let
      lib = dungeon.genLib;
      required = f: builtins.attrNames (lib.filterAttrs (_: opt: !opt) (lib.functionArgs f));
      rawAt = n: if (world.rawDefs or { }) ? ${n} then world.rawDefs.${n} else
        let ps = builtins.filter builtins.isString (builtins.split "/" n); in
        builtins.foldl' (vs: s: builtins.concatMap (v: if builtins.isAttrs v && v ? ${s} then [ v.${s} ] else if builtins.isAttrs v && s == "provides" && v ? _ then [ v._ ] else [ ]) vs) ((world.rawDefs or { }).${builtins.head ps} or [ ]) (builtins.tail ps);
      of = v:
        let r = if lib.isFunction v then (if builtins.all (k: scope ? ${k}) (required v) then v (builtins.intersectAttrs (lib.functionArgs v) scope) else { }) else v; in
        if !builtins.isAttrs r then [ ]
        # inline includes of a raw attrset are anon aspects in the closure already; only a fn result's are walked here
        else lib.optional (r ? ${class}) r.${class} ++ (if lib.isFunction v then builtins.concatMap of (builtins.filter dungeon.inlineAttrs (r.includes or [ ])) else [ ]);
    in
    if dungeon.gen.aspects.keyCategory (dungeon.view.cnfOf world) class == "class" then [ ] else builtins.concatMap of (rawAt m.name);
  # den.lib.resolveEntity "host" result: the host pipeline's modules (tutorials/microvm.mdx stage 3, reference/lib.mdx:62-83);
  # any other class: that class bucket of the host scope subtree, host then users (route.nix classModules; static leaf chain head, configure-aspects.mdx:134-139).
  # shortcut: users' hm/homeEnv + quirk channels are not wired for a resolved entity; quirks throw.
  resolveEntityModule =
    world: class: h:
    let r = dungeon.route world.schema world.rawAspects h (builtins.attrNames (h.users or { })); in
    if world.quirks != { } then throw "den.lib.aspects.resolve: quirks unsupported for resolved entity `${h.name}`"
    else { imports = if h.class == class then r.modules else r.classModulesWith (a: dungeon.rawClassOf world class { inherit class; aspect-chain = [ { __entityKind = "host"; ctx.host = h; inherit (h) name; } ]; } a) class; };
}
