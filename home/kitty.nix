{ lib, ... }:

{
  # Noctalia updates Kitty's generated theme at runtime, so this configuration
  # must be a writable file rather than a symlink into the Nix store.
  home.activation.installKittyConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD install -D -m 0644 \
      ${./config/kitty/kitty.conf} \
      "$HOME/.config/kitty/kitty.conf"
  '';
}
