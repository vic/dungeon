dungeon:
let
  # Only these leaves are captured; `den.users` etc. stay free for user-declared outer options.
  leaves = [ "hosts" "aspects" "schema" "policies" "quirks" "classes" "homes" "default" "systems" "config" ];
  # Each outer definition becomes one Gen module rooted at the leaf (design-den-option.md option A).
  toModules = lib: leaf: map (d: if leaf == "aspects" || leaf == "default" then lower lib leaf d else { _file = d.file; ${if leaf == "config" then "denConfig" else leaf} = if leaf == "policies" && builtins.isAttrs d.value then builtins.mapAttrs (name: v: if v.__isPolicy or false then v else { __isPolicy = true; inherit name; fn = v; }) d.value else d.value; });
  # `config.den.<leaf>` reads back the world value (deadbugs 216 reads `ev.config.den.aspects.foo`); evalDen takes
  # the leaf's definitionsWithLocations (toModules), so the readback never feeds its own input.
  # definitionsWithLocations is reverse module order (nixpkgs); reversed back so Gen's merge sees the authored module order
  # and class content keeps the order nixpkgs deferredModule would give (deadbugs 216 [ "foo" "bar" ]).
  capture =
    lib: w: leaf:
    lib.mkOption {
      type = lib.mkOptionType {
        name = "dungeonLeaf";
        merge = _loc: _defs: if leaf == "default" then w.aspects.default else w.${leaf};
      };
    };
  # Flat hosts `den.hosts.<name> = { system; ... }` are grouped under their system (flat-hosts tests);
  # `system` may sit in another definition than the content, so it is gathered across all of them first.
  flatHosts =
    lib: defs:
    let
      isSystem = k: builtins.elem k lib.systems.flakeExposed;
      flat = d: lib.filterAttrs (k: _: !isSystem k) d.value;
      systemOf = name: let ss = lib.concatMap (d: lib.optional ((flat d).${name} ? system) (flat d).${name}.system) defs; in
        if ss == [ ] then throw "den: flat host '${name}' must specify 'system' (e.g. system = \"x86_64-linux\")" else builtins.head ss;
    in
    map (d: d // { value = lib.foldlAttrs (acc: n: v: let s = systemOf n; in acc // { ${s} = (acc.${s} or { }) // { ${n} = removeAttrs v [ "system" ]; }; }) (lib.filterAttrs (k: _: isSystem k) d.value) (flat d); }) defs;
  # Lowering lives in normalize.nix; this only shapes the Gen module (inline includes -> anon aspects, design-fleet G3 arm a).
  lower =
    lib: leaf: d:
    if leaf != "default" && !builtins.isAttrs d.value then
      { _file = d.file; ${leaf} = d.value; }
    else
      { den, config, ... }:
      let
        n = dungeon.normalize lib leaf (dungeon.view.cnfOf den) (if leaf == "default" then { default = d.value; } else d.value);
        fixed = n.fixed den config.inlineSites;
      in
      {
        _file = d.file;
        aspects = fixed.__anons // lib.optionalAttrs (leaf == "aspects") (removeAttrs fixed [ "__anons" ]);
        default = lib.optionalAttrs (leaf == "default") fixed.default;
        policyRecs = lib.optionalAttrs (leaf == "aspects") n.recs;
        rawFns = lib.optionalAttrs (leaf == "aspects") (lib.filterAttrs (_: builtins.isFunction) d.value);
        aspectPolicies = lib.optionalAttrs (leaf == "aspects" || leaf == "default") n.polIncs;
        inlineSites = n.sites;
        rawDefs = builtins.mapAttrs (_: v: [ v ]) ((if leaf == "default" then { default = d.value; } else d.value) // n.rawAnons);
        unregistered = dungeon.unregistered (dungeon.view.cnf0Of den) (if leaf == "default" then { default = d.value; } else d.value);
      };
  # built hosts whose intoAttr head is `o`
  # `[ ]` builds the host but places nothing (reference/output.mdx:43,78)
  hostsAt = den: inputs: o: dungeon.genLib.filterAttrs (n: _: (den.host n).intoAttr != [ ] && builtins.head (den.host n).intoAttr == o) (dungeon.hosts den inputs);
  # hosts with any other intoAttr land at flake.<intoAttr> (schema.mdx:166-171)
  hostsElsewhere = den: inputs: lib: lib.mkMerge (lib.mapAttrsToList (n: s: lib.setAttrByPath (den.host n).intoAttr s) (lib.filterAttrs (n: _: (den.host n).intoAttr != [ ] && !builtins.elem (builtins.head (den.host n).intoAttr) [ "nixosConfigurations" "darwinConfigurations" ]) (dungeon.hosts den inputs)));
  # flake-parts already declares `flake`, so only the plain-evalModules host adds it.
  mk =
    declareFlake:
    { lib, config, options, inputs, ... }@margs:
    let
      # hosts keep nixpkgs' (reverse) order: gen-merge reverses it back, so instance lists concatenate in declaration order
      w = dungeon.evalDen (lib.concatMap (l: lib.optionals options.den.${l}.isDefined (toModules lib l ((if l == "hosts" then flatHosts lib else lib.reverseList) options.den.${l}.definitionsWithLocations))) leaves ++ lib.optional (margs ? withSystem) { _module.args.withSystem = margs.withSystem; });
    in
    {
      # freeform `flake` (keyed: dedups with a user flakeOutputs.flake import) + typed outputs dungeon writes.
      # docs reference/output.mdx:61: own `flake` outputs only when `inputs.flake-parts` is absent.
      imports = (if declareFlake && !(inputs ? flake-parts) then (
        map (n: dungeon.ciSurface.flakeOutputs.${n}) [ "flake" "nixosConfigurations" "darwinConfigurations" "homeConfigurations" ]) else [ ]
      # flake-parts-lib: specialArg of a running mkFlake (perSystem/systems exist only there)
      ) ++ lib.optional (margs ? flake-parts-lib) ({ den, ... }: dungeon.flakeParts den lib)
      # predicate builders ship in den.default (reference/batteries.mdx:349), as registry aspects so their identity stays a root
      ++ [ ({ den, ... }: { config.den.aspects = dungeon.batteries.predicates; config.den.default.includes = map (n: den.aspects.${n}) (builtins.attrNames dungeon.batteries.predicates); }) ]
      ++ [ ({ den, ... }: { flake = dungeon.instantiates den lib; }) ({ options, ... }: { config.flake = dungeon.outputs config._module.args.den inputs options; }) ({ den, ... }: { config.flake = hostsElsewhere den inputs lib; }) ];
      # config.den.lib is the builtin lib with user definitions deep-merged over it (both `den.lib` and `config.den.lib` read it).
      options.den = lib.genAttrs leaves (capture lib w) // { lib = lib.mkOption { default = { }; type = lib.mkOptionType { name = "denLib"; merge = _: defs: builtins.foldl' lib.recursiveUpdate w.lib (map (d: d.value) defs); }; }; };
      config._module.args.den = w // { lib = config.den.lib; };
      # schema.mdx:166-171: each host lands at its intoAttr (nixosConfigurations / darwinConfigurations)
      config.flake.nixosConfigurations = hostsAt config._module.args.den inputs "nixosConfigurations";
      config.flake.darwinConfigurations = hostsAt config._module.args.den inputs "darwinConfigurations";
      # standalone homes: aspect named by the home (guides/standalone-home-manager.mdx), its homeManager parts
      config.flake.homeConfigurations =
        let
          den = config._module.args.den;
          cl = dungeon.closure den.aspects;
          # guides/standalone-home-manager.mdx:96-110: default intoAttr [ "homeConfigurations" name ]; a name defaulted on two systems gets `@<system>`.
          defaulted = lib.concatLists (lib.mapAttrsToList (_: hs: builtins.attrNames (lib.filterAttrs (_: h: !(h ? intoAttr)) hs)) den.homes);
          outName = system: name: h:
            if !(h ? intoAttr) then (if lib.count (n: n == name) defaulted > 1 then "${name}@${system}" else name)
            else if builtins.length h.intoAttr == 2 && builtins.head h.intoAttr == "homeConfigurations" then builtins.elemAt h.intoAttr 1
            else throw "den: home `${name}`: intoAttr ${builtins.toJSON h.intoAttr} outside homeConfigurations is unsupported";
        in
        lib.concatMapAttrs (
          system: hs:
          lib.mapAttrs' (
            name: h:
            lib.nameValuePair (outName system name h) (inputs.home-manager.lib.homeManagerConfiguration {
              pkgs = inputs.nixpkgs.legacyPackages.${system};
              modules =
                let
                  base = lib.head (lib.splitString "@" name);
                  # standalone-home-host-context: `user@host` binds `host`, the declared host or a synthetic `{ name }` one (no class: nothing instantiated)
                  declaredHost = lib.concatLists (lib.mapAttrsToList (_: hs: lib.optional (hs ? ${h.hostName}) hs.${h.hostName}) den.hosts);
                  hostArg = lib.optionalAttrs (h.hostName != null) { host = if declaredHost != [ ] then lib.head declaredHost else { name = h.hostName; hostName = h.hostName; }; };
                  args = { home = h // { inherit name system; }; user = h // { inherit system; name = base; userName = base; }; } // hostArg;
                  dcl = cl den.aspects.default;
                  # aspect policies of the home scope fire with its ctx; their include effects join the scope
                  scope = scope0 ++ dungeon.addsOf den.aspects args (dungeon.uniqPols (lib.concatMap (a: a.policyIncs) (dcl ++ scope0)));
                  scope0 = dungeon.schemaCl den.schema den.aspects true "home" ++ lib.concatMap (n: lib.optionals (den.aspects ? ${n}) (cl den.aspects.${n})) (lib.unique [ name base ])
                    # standalone-home-manager.mdx:184-186: `provides.<host>` on the user aspect, only this home's host
                    ++ lib.optionals (h.hostName != null && den.aspects ? ${base} && (den.aspects.${base}.provides or { }) ? ${h.hostName}) (cl den.aspects.${base}.provides.${h.hostName});
                in
                lib.concatMap (a: lib.optional (a.content ? homeManager) (dungeon.content.classModule args a a.content.homeManager)) (
                  dcl ++ scope ++ dungeon.routes dcl [ ] args (dcl ++ scope)
                );
            })
          ) hs
        ) den.homes;
    };
in
{
  lowerDef = lower;
  # key: a test importing den.flakeModule again must dedupe, not redeclare `flake`
  flakeModule = { key = "dungeon:flakeModule"; imports = [ (mk true) ]; };
  # plain lib.evalModules host: `inputs` is bound here, not a specialArg (mk reads it inside `imports`).
  nixModule = inputs: { key = "dungeon:nixModule"; imports = [ ({ lib, config, options, ... }@m: mk true (m // { inherit inputs; })) ]; };
  # docs tutorials/default.mdx:184-192: dendritic.nix imports den.flakeModules.dendritic as the den wiring.
  flakeModules = rec { default = { key = "dungeon:flakeModules.default"; imports = [ (mk false) ]; }; dendritic = default; };
}
