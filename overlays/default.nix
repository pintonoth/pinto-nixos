{ inputs }:

_final: prev:

let
  system = prev.stdenv.hostPlatform.system;
in
{
  umbriel = inputs.umbriel.packages.${system}.default.override {
    inherit (prev) xwayland-satellite;
  };
}
