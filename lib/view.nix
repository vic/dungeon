# Inner surface: hosts + aspects at ROOT. includes elems must be refs to declared aspects.
dungeon: {
  view =
    let
      inherit (dungeon) gen;
      t = dungeon.genLib.types;
      cat = category: builtins.mapAttrs (_: _: { inherit category; });
      # an entity's freeform key (Den instance-collection-merge): lists concatenate, attrsets merge, functions take the last,
      # anything else must agree across definitions
      denRaw = dungeon.genLib.mkOptionType {
        name = "denRaw";
        merge =
          loc: defs:
          builtins.foldl' (
            acc: v:
            if builtins.isList acc && builtins.isList v then acc ++ v
            else if builtins.isAttrs acc && builtins.isAttrs v then dungeon.genLib.recursiveUpdate acc v
            else if builtins.isFunction acc && builtins.isFunction v then v
            else if acc == v then acc
            else throw "den: conflicting definitions for `${dungeon.genLib.last loc}`"
          ) (builtins.head defs).value (map (d: d.value) (builtins.tail defs));
      };
      # quirk names are channel keys (quirks never depend on aspects: no cycle); output classes: guides/flake-outputs.mdx:25-36.
      cnf0Of = c: {
        keySemantics =
          cat "class" { nixos = null; darwin = null; user = null; homeManager = null; os = null; hjem = null; maid = null; }
          # guides/flake-outputs.mdx:26-35: output classes
          // cat "class" { packages = null; apps = null; checks = null; devShells = null; legacyPackages = null; flake = null; }
          // cat "class" c.classes
          // cat "channel" c.quirks;
      };
      # + unregistered class keys found in aspect values (unregistered.nix, derived from cnf0Of)
      # + the classes flake-scope policy.instantiate specs collect (reference/policies.mdx:162-172): a parametric aspect's
      # class keys are not visible before it is applied, the spec names them. Fired with the empty flake ctx.
      instClasses = c: map (e: e.value.class) (builtins.filter (e: e.value ? class && e.value ? intoAttr) (dungeon.effectsOf "instantiate" (dungeon.firePols { } (builtins.filter (p: p.__isPolicy or false) (c.schema.flake.includes or [ ])))));
      # `provides` is a gen-aspects facet: every child is an aspect whatever its name (reference/aspects.mdx:64)
      cnfOf = c: let cnf = { keySemantics = (cnf0Of c).keySemantics // cat "class" (builtins.listToAttrs (map (name: { inherit name; value = null; }) (c.unregistered ++ instClasses c))) // { provides = { category = "facet"; option = dungeon.genLib.mkOption { type = t.lazyAttrsOf (gen.aspects.aspectType cnf); default = { }; }; }; }; }; in cnf;
      mkAspects =
        decl:
        let
          cnf = cnfOf decl;
          # nested aspects (Den aspects.mdx:19; gen-aspects "A key with no entry is a nested aspect") are
          # addressed by name `<parent>/<key>`; resolved by path so the world's key set never forces aspect bodies.
          kids = e: builtins.filter (k: gen.aspects.keyCategory cnf k == null && builtins.isAttrs e.${k}) (builtins.attrNames e);
          at = n: builtins.foldl' (e: s: e.${s} or { }) decl.aspects (dungeon.aspectPath decl.aspects n);
          isRef = b: (at b.name).key or null == b.key;
          authored =
            name: e: k: _:
            let
              c = gen.aspects.keyCategory cnf k;
            in
            if k == "excludes" then
              false
            else if c == null then
              # nested aspect: own entry, its content lands only if included
              if builtins.isAttrs e.${k} then false else throw "den: aspect `${name}`: key `${k}` is not a declared class and not a nested aspect"
            else
              c == "class" && gen.aspects.hasClassContent e.${k};
          norm =
            name: e:
            let provs = builtins.mapAttrs (c: v: norm "${name}/provides/${c}" v) (e.provides or { }); in
            e
            // builtins.listToAttrs (map (k: { name = k; value = norm "${name}/${k}" e.${k}; }) (kids e))
            # `<aspect>.provides.<n>` is also reachable as `<aspect>.<n>` (reference/aspects.mdx:69); a same-named own key wins.
            # an undefined class/channel option reads null and is not an own key (Den forwards over names the aspect does not define);
            # only those values are forced: forcing `includes` here cycles through refs to this aspect's own children
            // builtins.removeAttrs provs (builtins.filter (k: !(builtins.elem (gen.aspects.keyCategory cnf k) [ "class" "channel" ] && e.${k} == null)) (builtins.attrNames e))
            // {
              # `_` reads as the provides children; included, it bundles the nested children
              # (provides children are included by name, include-children.nix test-include-children-with-provides).
              _ = provs // dungeon.bundle (map (k: norm "${name}/${k}" e.${k}) (kids e));
              # published `provides` = the children only, callable as an aspect including them all (multidef-provides-internals).
              # A namespace root's `_` is added in namespace.nix.
              provides = provs // dungeon.bundle (builtins.attrValues provs);
            }
            // {
              inherit name;
              policyIncs = builtins.filter (p: !builtins.any (x: builtins.isAttrs x && (x.__isPolicy or false) && x.name == p.name) (e.excludes or [ ])) (decl.aspectPolicies.${name} or [ ]);
              includes = gen.prelude.imap0 (
                i: b:
                if isRef b then
                  b
                else
                  throw "den: aspect `${name}`: includes[${toString i}] is not a ref to a declared aspect"
              ) e.includes;
              # policy elements (attrs/functions without an aspect name) are not aspect refs: not closure-excluded here
              excludes = builtins.filter (b: builtins.isAttrs b && b ? name && b ? key && isRef b) (
                gen.prelude.imap0 (
                  i: b:
                  if builtins.isString b then
                    throw "den: aspect `${name}`: excludes[${toString i}] is not of type aspect or function returning aspect (is not of type `aspect or function returning aspect')"
                  else
                    b
                ) (e.excludes or [ ])
              );
              # forces key validation (N2)
              content = gen.prelude.filterAttrs (authored name e) e;
              # unset channel keys surface as null; only authored emissions count
              quirks = gen.prelude.filterAttrs (k: v: v != null && gen.aspects.keyCategory cnf k == "channel") e;
            };
          normed = builtins.mapAttrs norm decl.aspects;
        in
        normed;
    in
    {
      inherit mkAspects cnfOf cnf0Of;
      module =
        { lib, config, ... }:
        let
          instanceOf = kind: extraModules: dungeon.schema.lib.mkInstanceType { strict = kind.isStrict; inherit extraModules; } kind;
        in
        {
          options.hosts = lib.mkOption {
            # system-level submodule so each host sees its parent key (class/intoAttr defaults, schema.mdx:139-171).
            type = t.lazyAttrsOf (t.submodule ({ name, ... }: let system = name; in {
              freeformType =
              t.lazyAttrsOf (
                # den.schema.host is a gen-schema kind: its body and imports compose into every host; mkInstanceType adds
                # `name`, `id_hash` and the open/strict instance mode (entities.mdx:183-192, reference/lib.mdx:238-242).
                instanceOf config.schema.host [
                  # an open host's freeform keys merge as Den's (denRaw), over gen-schema's open `attrsOf anything`
                  (lib.optionalAttrs (!config.schema.host.isStrict) { config._module.freeformType = lib.mkForce (t.lazyAttrsOf denRaw); })
                  ({ name, ... }@hargs:
                  {
                    options.hostName = lib.mkOption { type = t.str; default = name; };
                    options.system = lib.mkOption { type = t.str; default = system; };
                    # schema.mdx:141 `"nixos"` or `"darwin"` based on system; :166-171 intoAttr by class.
                    options.class = lib.mkOption { type = t.str; default = if builtins.match ".*-darwin" system != null then "darwin" else "nixos"; };
                    options.intoAttr = lib.mkOption { type = t.listOf t.str; default = [ "${hargs.config.class}Configurations" name ]; };
                    options.users = lib.mkOption {
                      type = t.lazyAttrsOf (
                        instanceOf config.schema.user [
                          ({ name, ... }:
                          {
                            options.userName = lib.mkOption { type = t.str; default = name; };
                            options.classes = lib.mkOption {
                              type = t.listOf t.str;
                              default = [ ];
                            };
                          })
                        ]
                      );
                      default = { };
                    };
                  })
                ]
              );
            }));
            default = { };
          };
          options.aspects = lib.mkOption {
            type = gen.aspects.aspectsType (cnfOf config);
            default = { };
          };
          # den.default is an aspect: same type as aspects.<n>, then walked as aspects.default.
          options.default = lib.mkOption {
            type = gen.aspects.aspectType (cnfOf config);
            default = { };
          };
          config.aspects.default = config.default;
          # den.schema.<kind> are gen-schema kinds (deferred module bodies); these keys are kind-level data, not instance config.
          options.schema =
            let
              list = { default = [ ]; merge = acc: v: acc ++ v; identity = false; };
              flag = { default = false; merge = acc: v: acc || v; };
            in
            gen.schema.mkSchemaOption {
              specialArgs = { lib = dungeon.genLib; };
              collections = {
                includes = list;
                excludes = list;
                # read from the raw defs by `computed` below (a collection merge sees mkDefault wrappers unresolved)
                classes = { default = [ ]; merge = acc: _: acc; identity = false; };
                isStrict = flag;
                isEntity = flag;
                collisionPolicy = { default = null; merge = _: v: v; identity = false; };
              };
              # schema.user.classes: plain definitions concatenate and win over mkDefault ones (denTest fixture mkDefault [ "homeManager" ]).
              # shortcut: only plain and mkDefault priorities, upgrade if a fleet uses mkForce here.
              computed = _: defs: {
                classes =
                  let
                    vs = builtins.concatMap (d: if builtins.isAttrs d.value && d.value ? classes then [ d.value.classes ] else [ ]) defs;
                    isOv = v: (v._type or null) == "override";
                    plain = builtins.filter (v: !isOv v) vs;
                  in
                  if plain != [ ] then builtins.concatLists plain else builtins.concatMap (v: v.content) vs;
              };
            };
          # consumers read schema.host/user unconditionally
          config.schema.host = { };
          config.schema.user = { };
          # `inherits = [ den.schema.conf ]` names it (custom-entity-kinds.mdx); its instance keys come from schema.entity
          config.schema.conf = { };
          options.policies = lib.mkOption { type = t.lazyAttrsOf t.raw; default = { }; };
          # builtins are named atoms so schema.<kind>.excludes can reference them (reference/policies.mdx:293-297)
          config.policies = lib.genAttrs dungeon.builtinPolicies (n: { __builtin = n; });
          options.aspectPolicies = lib.mkOption { type = t.lazyAttrsOf (t.listOf t.raw); default = { }; };
          options.policyRecs = lib.mkOption { type = t.lazyAttrsOf (t.lazyAttrsOf t.raw); default = { }; };
          options.rawFns = lib.mkOption { type = t.lazyAttrsOf t.raw; default = { }; };
          options.quirks = lib.mkOption { type = t.lazyAttrsOf t.raw; default = { }; };
          options.classes = lib.mkOption { type = t.lazyAttrsOf t.raw; default = { }; };
          options.homes = lib.mkOption { type = t.lazyAttrsOf (t.lazyAttrsOf t.raw); default = { }; };
          options.systems = lib.mkOption { type = t.listOf t.str; default = [ ]; };
          options.unregistered = lib.mkOption { type = t.listOf t.str; default = [ ]; };
          # named inline include sightings by site (normalize.nix sitesAt), across every definition
          options.inlineSites = lib.mkOption { type = t.lazyAttrsOf (t.listOf t.raw); default = { }; };
          # raw aspect definitions (and raw include elements) by aspect name: unregistered classes are read from here on request
          options.rawDefs = lib.mkOption { type = t.lazyAttrsOf (t.listOf t.raw); default = { }; };
          # den.config (Den modules/config.nix); `config` is the module keyword, so the leaf lands here
          options.denConfig = lib.mkOption {
            type = t.submodule { options.classModuleCollisionPolicy = lib.mkOption { type = t.enum [ "error" "class-wins" "den-wins" ]; default = "error"; }; };
            default = { };
          };
        };
    };
}
