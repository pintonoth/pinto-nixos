{ pkgs, ... }:

{
  #Add user to group libvirtd
  users.users."jensend".extraGroups = [
    "kvm"
    "libvirtd"
  ];

  # Enable the libvirt daemon
  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
        package = pkgs.qemu_kvm;
      };
    };
    spiceUSBRedirection.enable = true;
  };
  services.spice-vdagentd.enable = true;

  # Install the virt-manager GUI application
  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    # (qemu_full.override { cephSupport = false; })
    virglrenderer
    virt-viewer
    virtio-win
    win-spice
    spice-protocol
    spice-gtk
    spice
    vm-curator
  ];
}
