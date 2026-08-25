{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../../hosts/common.nix
    ../../modules/desktop/cosmic.nix
  ];
}
