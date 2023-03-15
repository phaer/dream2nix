{
  config,
  lib,
  ...
}: let
  l = lib // builtins;
  python = config.deps.python;
in {
  imports = [
    ../../drv-parts/mach-nix-xs
    ../../drv-parts/lock
  ];

  lock.fields.mach-nix.pythonSources = config.lock.lib.updateFODHash config.mach-nix.pythonSources;
  deps = {nixpkgs, ...}: {
    python = nixpkgs.python39;
    inherit (nixpkgs.writers) writePython3;
  };

  public = {
    name = "ansible";
    version = "2.7.1";
  };

  mkDerivation = {
    preUnpack = ''
      export src=$(ls ${config.mach-nix.pythonSources}/names/${config.public.name}/*);
    '';
  };

  buildPythonPackage = {
    format = "setuptools";

    pythonImportsCheck = [
      config.public.name
    ];
  };

  mach-nix.pythonSources = config.deps.fetchPythonRequirements {
    inherit python;
    name = config.public.name;
    requirementsList = ["${config.public.name}==${config.public.version}"];
    hash = config.lock.content.mach-nix.pythonSources;
    maxDate = "2023-01-01";
  };
}
