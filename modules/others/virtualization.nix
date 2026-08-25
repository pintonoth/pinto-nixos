{ pkgs, ... }:

{
  #Add user to group libvirtd
  users.users."jensend".extraGroups = [ "libvirtd" ];

  # Enable the libvirt daemon
  virtualisation.libvirtd.enable = true;

  # Install the virt-manager GUI application
  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    vm-curator
  ];
}
