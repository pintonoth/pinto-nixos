{ inputs }:

_final: prev:

let
  system = prev.stdenv.hostPlatform.system;
  xwayland-satellite = inputs.xwayland-satellite.packages.${system}.default;
in
{
  inherit xwayland-satellite;

  umbriel = inputs.umbriel.packages.${system}.default.override {
    inherit xwayland-satellite;
  };
}
