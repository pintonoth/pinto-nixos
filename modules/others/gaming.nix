{ config, pkgs, ... }:

{
  # 1. Enable Steam natively (enables hardware acceleration and firewall ports)
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  # 2. Gaming Performance Tweaks (Gamemode)
  # Optimizes CPU governors, process priorities, and GPU clocks when running games
  programs.gamemode.enable = true;

  # 3. Graphics & 32-bit Libraries (Moved from main config to keep it organized)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
