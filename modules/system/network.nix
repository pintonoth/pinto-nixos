{ ... }:

{
  services.openssh.enable = true;
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
  networking.firewall.checkReversePath = "loose";
  networking.nameservers = [
    "1.1.1.1"
    "1.0.0.1"
  ];
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (
        subject.user == "nordvpn"
        && (
          action.id == "org.freedesktop.resolve1.set-dns-servers"
          || action.id == "org.freedesktop.resolve1.set-domains"
          || action.id == "org.freedesktop.resolve1.set-default-route"
          || action.id == "org.freedesktop.resolve1.set-dnssec"
          || action.id == "org.freedesktop.resolve1.flush-caches"
          || action.id == "org.freedesktop.resolve1.revert"
        )
      ) {
        return polkit.Result.YES;
      }
    });
  '';
}
