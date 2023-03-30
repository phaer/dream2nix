# TODO replace former manualSetupDeps with PEP 518 impl
{
  config,
  lib,
  drv-parts,
  ...
}: let
  l = lib // builtins;
  python = config.deps.python;
  cfg = config.mach-nix;
  packageName = config.name;
  metadata = config.eval-cache.content.mach-nix.metadata;

  dependencyTree =
    (l.flip l.mapAttrs) metadata
    (
      name: info:
        buildPackage {
          inherit name;
          inherit (info) version;
        }
    );

  # For a given name, return the path of the downloaded file
  getDistFile = name: "${cfg.pythonSources}/dist/${metadata.${name}.file}";

  commonModule = {config, ...}: {
    imports = [
      drv-parts.modules.drv-parts.mkDerivation
      ../buildPythonPackage
    ];
    config = {
      deps = {nixpkgs, ...}:
        l.mapAttrs (_: l.mkDefault) {
          inherit python;
          inherit
            (nixpkgs)
            autoPatchelfHook
            stdenv
            ;
          manylinuxPackages = with nixpkgs.pythonManylinuxPackages; [
            manylinux1
            manylinux2010
            manylinux2014
          ];
        };
      buildPythonPackage = {
        format = l.mkDefault (
          if l.hasSuffix ".whl" config.mkDerivation.src
          then "wheel"
          else "setuptools"
        );
      };
      mkDerivation = {
        src = l.mkDefault (getDistFile config.name);
        doCheck = l.mkDefault false;

        nativeBuildInputs = [config.deps.autoPatchelfHook];
        buildInputs = config.deps.manylinuxPackages;
        propagatedBuildInputs =
          l.map (name: cfg.drvs.${name}.public.out)
          metadata.${config.name}.dependencies;
        # ensure build inputs are propagated for autopPatchelfHook
        postFixup = "ln -s $out $dist/out";
      };
    };
  };

  buildPackage = {
    name,
    version,
  }: {config, ...}: {
    imports = [
      commonModule
    ];
    config = {
      inherit name version;
    };
  };

  # Validate Substitutions. Allow only names that we actually depend on.
  unknownSubstitutions = l.attrNames (l.removeAttrs cfg.substitutions (l.attrNames metadata));
  substitutions =
    if unknownSubstitutions == []
    then cfg.substitutions
    else
      throw ''
        ${"\n"}The following substitutions for python derivation '${packageName}' will not have any effect. There are no dependencies with such names:
        - ${lib.concatStringsSep "\n  - " unknownSubstitutions}
      '';
  # Usually references to buildInputs would get lost in the dist output.
  # Patch wheels to ensure build inputs remain dependencies of the `dist` output
  # Those references are needed for the final autoPatchelfHook to find the required deps.
  patchedSubstitutions = l.mapAttrs (name: drv:
    drv-parts.lib.makeModule {
      packageFunc = drv.overridePythonAttrs (old: {postFixup = "ln -s $out $dist/out";});
      # TODO: if `overridePythonAttrs` is used here, the .dist output is missing
      #   Maybe a bug in drv-parts?
      #      overrideFuncName = "overrideAttrs";
      modules = [
        {deps = {inherit (config.deps) stdenv;};}
      ];
    })
  substitutions;
in {
  imports = [
    commonModule
    ./interface.nix
    ../eval-cache
    ../lock
  ];

  config = {
    # use lock file to manage hash for fetchPip
    lock.fields.fetchPipHash = {
      script =
        config.lock.lib.computeFODHash
        config.mach-nix.pythonSources;
      default = l.fakeSha256;
    };

    mach-nix.metadata = l.fromJSON (l.readFile "${cfg.pythonSources}/metadata.json");
    mach-nix.drvs =
      dependencyTree // patchedSubstitutions;

    mach-nix.pythonSources = {
      imports = [../../drv-parts/fetch-pip];
      deps.python = config.deps.python;
      fetch-pip = {
        hash = config.lock.content.fetchPipHash;
      };
    };

    deps = {nixpkgs, ...}:
      l.mapAttrs (_: l.mkDefault) {
        fetchPip = nixpkgs.callPackage ../../../pkgs/fetchPip {};

        runCommand = nixpkgs.runCommand;
        pip = nixpkgs.python3Packages.pip;
        setuptools = nixpkgs.python3Packages.setuptools;
      };

    eval-cache.fields = {
      mach-nix.metadata = true;
    };
    eval-cache.invalidationFields = {
      mach-nix.pythonSources = true;
    };

    mkDerivation = {
      dontPatchELF = l.mkDefault true;
      dontStrip = l.mkDefault true;

      passthru = {
        inherit (config.mach-nix) pythonSources;
        # The final dists we want to install.
        # A mix of:
        #   - downloaded wheels
        #   - downloaded sdists built into wheels (see above)
        #   - substitutions from nixpkgs patched for compat with autoPatchelfHook
        dists = l.mapAttrs (_: drv: drv.public.out.dist) config.mach-nix.drvs;
      };
    };
  };
}
