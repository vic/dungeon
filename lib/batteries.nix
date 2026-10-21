# Inner module pre-declaring battery aspects (design-gen.md §4; content ASSUMED from Den docs).
dungeon:
let
  # reference/batteries.mdx:137-157, 347-360: `<battery> names` sets `<opt>.packages`; the predicate builder (den.default) declares
  # the option per class and turns it into nixpkgs.config.<cfg>. Den: modules/aspects/batteries/{unfree,insecure}/*-predicate-builder.nix
  # shortcut: user-included names are not lifted onto the host OS config (batteries.mdx:349); add with user->host routing.
  names = opt: ns: let m = { ${opt}.packages = ns; }; in { nixos = m; darwin = m; homeManager = m; };
  builder =
    { battery, opt, value }:
    let
      module =
        { config, lib, ... }@args:
        {
          key = "den/${battery}-predicate";
          options.${opt}.packages = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
          # home-manager refuses nixpkgs.config under useGlobalPkgs: the host's predicate covers it there
          config.nixpkgs = lib.mkIf (config.${opt}.packages != [ ] && !(args.osConfig.home-manager.useGlobalPkgs or false)) {
            config = value lib config.${opt}.packages;
          };
        };
    in
    {
      # entity-keyed children `<battery>-predicate/{os,user,home}` (Den shipped-battery-chain identities); class content selects the entity
      includes = [
        { name = "os"; nixos.imports = [ module ]; darwin.imports = [ module ]; }
        { name = "user"; homeManager.imports = [ module ]; }
        { name = "home"; homeManager.imports = [ module ]; }
      ];
    };
in
{
  batteries.unfree = names "unfree";
  batteries.insecure = names "permittedInsecurePackages";
  batteries.predicates = {
    unfree-predicate = builder { battery = "unfree"; opt = "unfree"; value = lib: ps: { allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ps; }; };
    insecure-predicate = builder { battery = "insecure"; opt = "permittedInsecurePackages"; value = _: ps: { permittedInsecurePackages = ps; }; };
  };
  batteries.module = { config, ... }: let withSystem = config._module.args.withSystem; homeOf = sys: n: if builtins.match ".*-darwin" sys != null then "/Users/${n}" else "/home/${n}"; in {
    # reference/batteries.mdx:88: NixOS wheel+networkmanager; Darwin system.primaryUser.
    aspects.primary-user.user =
      { host, ... }:
      if host.class == "nixos" then { isNormalUser = true; extraGroups = [ "wheel" "networkmanager" ]; } else { };
    aspects.primary-user.darwin = { user, ... }: { system.primaryUser = user.userName; };
    # `user` class = users.users.<user> (route.userPart flattens it with {host,user}).
    # reference/batteries.mdx:27: home /Users/<n> on Darwin, /home/<n> elsewhere; isNormalUser on NixOS only.
    aspects.define-user.user =
      { host, user, ... }:
      {
        name = user.userName;
        home = homeOf host.system user.userName;
      } // (if host.class == "nixos" then { isNormalUser = true; } else { });
    aspects.define-user.homeManager =
      { user, ... }:
      let n = user.userName or user.name; in
      {
        home.username = n;
        home.homeDirectory = homeOf (user.system or user.host.system) n;
      };
    # marker: route.hm gives users whose closure holds it the host closure's homeManager content
    aspects.host-aspects.description = "Project the host aspect closure's homeManager content onto the including user";
    # reference/batteries.mdx:41: NixOS and Darwin.
    aspects.hostname.nixos = { host, ... }: { networking.hostName = host.hostName; };
    aspects.hostname.darwin = { host, ... }: { networking.hostName = host.hostName; };
    # inputs'/self' via flake-parts withSystem; system from the bound host/user/home entity.
    aspects."inputs'".homeManager = { user, ... }: { _module.args."inputs'" = withSystem (user.system or user.host.system) (ps: ps."inputs'"); };
    aspects."inputs'".nixos = { host, ... }: { _module.args."inputs'" = withSystem host.system (ps: ps."inputs'"); };
    aspects."self'".homeManager = { user, ... }: { _module.args."self'" = withSystem (user.system or user.host.system) (ps: ps."self'"); };
    aspects."self'".nixos = { host, ... }: { _module.args."self'" = withSystem host.system (ps: ps."self'"); };
  };
}
