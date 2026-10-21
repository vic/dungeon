# evalDen: Gen-side eval of the captured `den` leaf modules -> world (design-gen.md §3 steps 2-4). No routing yet (R2+).
dungeon: {
  evalDen =
    denModules:
    let
      inner = dungeon.genLib.evalModules {
        modules = [
          dungeon.view.module
          dungeon.batteries.module
          { _module.args.withSystem = dungeon.genLib.mkDefault (_: throw "den: inputs'/self' need flake-parts withSystem"); }
          { _module.args.den = world; }
        ] ++ denModules;
      };
      cfg = inner.config;
      aspects = builtins.mapAttrs (n: a: if cfg.policyRecs ? ${n} then a // { policies = cfg.policyRecs.${n}; } else a) (dungeon.view.mkAspects cfg);
      # callable aspects: `den.aspects.f arg` = the raw fn applied, as an inline aspect (rawFns are the inner, unwrapped eval)
      wrapped = builtins.mapAttrs (n: a: a // { __functor = _: arg: if cfg.rawFns ? ${n} then cfg.rawFns.${n} arg else dungeon.parametric.fixedTo arg a; }) aspects;
      world = {
        aspects = wrapped;
        rawAspects = aspects;
        inherit (cfg) schema policies quirks classes unregistered systems rawFns rawDefs;
        # home entity (reference/schema.mdx:219-235): name = registry key, userName/hostName parsed at `@`;
        # identity = gen-identity's one mint (gen-identity lib/default.nix:411) over registry key + system (entities.mdx:93).
        homes = builtins.mapAttrs (system: builtins.mapAttrs (name: h:
          let at = builtins.match "([^@]*)@(.*)" name; in
          { inherit name system; userName = if at == null then name else builtins.elemAt at 0; hostName = if at == null then null else builtins.elemAt at 1; class = "homeManager"; collisionPolicy = cfg.schema.home.collisionPolicy or null; }
          // h // { id_hash = dungeon.gen.identity.hashIdentity "home" [ "name" "system" ] (l: { inherit name system; }.${l}); })) cfg.homes;
        # entity `aspect` = den.aspects.<name> (reference/schema.mdx:139,141); lazy: throws only when read
        # user aspect (reference/schema.mdx:185) applies where it exists; none = empty aspect. shortcut: `<user>@<host>` qualified aspect not merged yet.
        # collisionPolicy: entity value, else the kind level (reference/aspects.mdx:186-193)
        hosts = builtins.mapAttrs (system: builtins.mapAttrs (n: h: h // { aspects = dungeon.entityAspects world cfg (h // { inherit system; }); collisionPolicy = h.collisionPolicy or cfg.schema.host.collisionPolicy or null; aspect = aspects.${n} or (throw "den: host `${n}` has no aspect"); users = builtins.mapAttrs (u: v: v // { collisionPolicy = v.collisionPolicy or cfg.schema.user.collisionPolicy or null; aspect = aspects.${u} or { name = u; provides = { }; includes = [ ]; }; }) (h.users or { }); })) cfg.hosts;
        batteries.primary-user = aspects.primary-user;
        batteries.define-user = aspects.define-user;
        batteries.hostname = aspects.hostname;
        batteries.host-aspects = aspects.host-aspects;
        # reference/batteries.mdx:116-127: inert compatibility shim, produces no effects
        batteries.mutual-provider = { };
        batteries."inputs'" = aspects."inputs'";
        batteries."self'" = aspects."self'";
        batteries.user-shell = dungeon.batteryFns.user-shell;
        batteries.tty-autologin = dungeon.batteryFns.tty-autologin;
        batteries.unfree = dungeon.batteries.unfree;
        batteries.insecure = dungeon.batteries.insecure;
        provides = world.batteries;
        _ = world.provides;
        lib.parametric = dungeon.parametric;
        # reference/lib-deprecated.mdx:101-104: plain helper `_unused: used: used`.
        lib.take.unused = _unused: used: used;
        lib.__findFile = dungeon.angle world;
        lib.nh = dungeon.nh cfg.hosts cfg.homes;
        lib.policy = dungeon.channels.lib.policy;
        lib.aspects.resolve = dungeon.resolve world;
        # reference/lib.mdx:62-83: "host" runs the host pipeline (route.nix, resolve.nix); other kinds are the aspect-like
        # record over den.schema.<kind> (name, meta, includes, excludes, __entityKind) with ctx pinned as fixedTo does.
        lib.resolveEntity = kind: ctx: if kind == "host" then { __entityKind = "host"; inherit ctx; } else { name = kind; meta = { }; includes = cfg.schema.${kind}.includes or [ ]; excludes = cfg.schema.${kind}.excludes or [ ]; __entityKind = kind; __ctx = ctx; };
        batteries.forward = dungeon.forward world;
        lib.schema = dungeon.schema.lib;
        # den-diagram capture (reference/diag.mdx:321-332) is out of scope (vic 2026-10-20): explicit throw, catchable by tryEval.
        lib.capture.captureFleet = _: throw "dungeon: den.lib.capture.captureFleet not implemented (den-diagram out of scope)";
        lib.closure = dungeon.closure aspects;
        # host entity by name (system = its attr-path key)
        host = name: builtins.head (builtins.concatLists (builtins.attrValues (builtins.mapAttrs (system: hs: if hs ? ${name} then [ (hs.${name} // { inherit system; }) ] else [ ]) cfg.hosts)));
        lib.userModules = h: u: (dungeon.route cfg.schema aspects (world.host h) [ ]).userModules u;
      };
    in
    world;
}
