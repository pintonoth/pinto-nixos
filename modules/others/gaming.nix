{ ... }:

{
  # Gaming Performance Tweaks (Gamemode)
  # Optimizes CPU governors, process priorities, and GPU clocks when running games
  programs.gamemode.enable = true;

  # raphics & 32-bit Libraries (Moved from main config to keep it organized)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
