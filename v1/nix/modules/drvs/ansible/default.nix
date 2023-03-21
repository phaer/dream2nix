{
  config,
  lib,
  ...
}: let
  l = lib // builtins;
in {
  imports = [
    ../../drv-parts/mach-nix-xs
    ../../drv-parts/lock
  ];

  deps = {nixpkgs, ...}: {
    python = nixpkgs.python39;
  };

  name = "ansible";
  version = "2.7.1";

  buildPythonPackage.pythonImportsCheck = [config.name];

  mach-nix.pythonSources.fetch-pip = {
    pypiSnapshotDate = "2023-01-01";
    requirementsList = ["${config.name}==${config.version}"];
  };
}
