# hjem / nix-maid batteries: OS module imported once when a host user has the class; each such user's
# class content forwarded (guides/home-manager.mdx:197-248, explanation/context-pipeline.mdx:73-76, custom-classes.mdx:25-26).
# host.<env>.module overrides the battery module (issue-254). shortcut: no <env>.enable schema flag; add when a fleet sets it.
dungeon: {
  homeEnv =
    r: inputs: host: envUsers:
    let
      envs = {
        hjem = { module = host.hjem.module or inputs.hjem.nixosModules.default; at = u: [ "hjem" "users" u ]; };
        maid = { module = host.maid.module or inputs.nix-maid.nixosModules.default; at = u: [ "users" "users" u "maid" ]; };
      };
      partsOf = cls: u: builtins.concatMap (a: if a.content ? ${cls} then [ (dungeon.content.classModule (r.argsOf u) a a.content.${cls}) ] else [ ]) (r.defaultCl ++ r.userClosure u);
      nest = path: v: inputs.nixpkgs.lib.setAttrByPath path v;
      one =
        cls: e:
        let
          us = envUsers cls;
        in
        if us == [ ] then [ ]
        else if host.class != "nixos" then throw "den: `${cls}` users need a nixos host, `${host.name}` is ${host.class}"
        # a function definition: a submodule reads an attrset definition as config only (shorthandOnlyDefinesConfig), so `imports` there is an option
        else [ e.module ] ++ map (u: nest (e.at host.users.${u}.userName) (_: { imports = partsOf cls u; })) us;
    in
    builtins.concatLists (builtins.attrValues (builtins.mapAttrs one envs));
}
