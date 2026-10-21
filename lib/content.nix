dungeon:
let
  denArgs = [ "host" "user" "home" ];
  # lowered inline includes (entry.nix) are setFunctionArgs functors, not lambdas
  isFn = v: builtins.isFunction v || (builtins.isAttrs v && v ? __functor && v ? __functionArgs);
  # only den ctx args (and quirk pools the caller binds) trigger binding; nixpkgs-style module fns pass through untouched
  isDen = args: f: builtins.any (n: builtins.elem n denArgs || args ? ${n}) (builtins.attrNames (dungeon.genLib.functionArgs f));
  # collision policy per arg name (reference/aspects.mdx:178-207): aspect
  # meta.collisionPolicy, else the entity bound under that name (entity, then kind level: folded in eval.nix), else the
  # global den.config.classModuleCollisionPolicy (stamped on entities in eval.nix), else "error".
  # shortcut: only host/user/home are read as entities; a custom-kind entity falls through to the global.
  entityAt = args: k: if builtins.elem k denArgs && builtins.isAttrs (args.${k} or null) then args.${k} else { };
  globalOf = args: builtins.foldl' (p: k: if p != null then p else (entityAt args k).__classModuleCollisionPolicy or null) null denArgs;
  policyOf =
    aspect: args: name:
    let
      ap = aspect.meta.collisionPolicy or null;
      ep = (entityAt args name).collisionPolicy or null;
      g = globalOf args;
    in
    if ap != null then ap else if ep != null then ep else if g != null then g else "error";
  strategy = { error = "error"; den-wins = "bind-wins"; class-wins = "system-wins"; };
  # gen-bind's collision report, in den's vocabulary
  denMsg = builtins.replaceStrings [ "gen-bind: binding" "bind-wins" "system-wins" ] [ "den: class module arg" "den-wins" "class-wins" ];
  # gen-bind's merge validator (gen-bind merge-strategy.nix mkMergeValidator, returned by wrap.nix) defines `warnings`;
  # a target without a `warnings` option gets no data: den-wins/class-wins trace, error still throws when the config is forced.
  validatorModule = validator: margs:
    let
      has = (margs.options or { }) ? warnings;
      # `_module.args` read through its option, not `config`: under a freeformType `config` itself waits on this definition
      ws = map denMsg (validator (margs // { config._module.args = margs.options._module.args.value or { }; })).warnings;
    in
    { config.warnings = { _type = "if"; condition = if has then true else builtins.foldl' (acc: w: builtins.trace "evaluation warning: ${w}" acc) false ws; content = ws; }; };
  bind =
    ms: aspect: args: v:
    let
      w = dungeon.gen.bind.wrap { bindings = args; mergeStrategies = builtins.mapAttrs (n: _: strategy.${policyOf aspect args n}) args // ms; defaultMergeStrategy = "error"; } v;
      # full application (every arg a den arg) never reaches the module system: no collision (class-modules.mdx:166)
      partial = builtins.any (n: !(args ? ${n})) (builtins.attrNames (dungeon.genLib.functionArgs v));
    in
    if partial && w.validator != null then { imports = [ w.module (validatorModule w.validator) ]; } else w.module;
  walk =
    ms: aspect: args: v:
    if isFn v then
      (if isDen args v then bind ms aspect args v else v)
    else if builtins.isAttrs v && v ? imports && builtins.isList v.imports then
      v // { imports = map (walk ms aspect args) v.imports; }
    else
      v;
in
{
  # `classModule args aspect module`: `aspect` supplies meta.collisionPolicy
  content.classModule = args: aspect: walk { } aspect args;
  # `keys` are bound over a module-system arg of the same name (bind-wins): pipe.to data shadows the unmodified pool
  content.classModuleOver = keys: args: aspect: walk (builtins.listToAttrs (map (name: { inherit name; value = "bind-wins"; }) keys)) aspect args;
}
