{ lib, ... }:

{
  xdg.mimeApps.defaultApplications."inode/directory" =
    lib.mkForce [ "org.kde.dolphin.desktop" ];
}
