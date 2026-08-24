{ ... }:

{
  fileSystems."/media/storage" = {
    device = "/dev/disk/by-uuid/328E4DA48E4D6209";
    fsType = "ntfs3";
    options = [
      "nofail"
      "uid=1000"
      "gid=100"
      "umask=0022"
    ];
  };

  fileSystems."/media/bigfaststorage" = {
    device = "/dev/disk/by-uuid/C6AEA278AEA26123";
    fsType = "ntfs3";
    options = [
      "nofail"
      "gid=67"
      "umask=0022"
    ];
  };
}
