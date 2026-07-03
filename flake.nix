{
  description = "Nix flake for ZedG, the Zed Globalization Chinese build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = [
      "x86_64-linux"
    ];

    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        zedg = pkgs.callPackage ./package.nix {};
        default = self.packages.${system}.zedg;
      }
    );

    apps = forAllSystems (
      system: {
        zedg = {
          type = "app";
          program = "${self.packages.${system}.zedg}/bin/zedg";
        };

        default = self.apps.${system}.zedg;
      }
    );

    overlays.default = final: prev: {
      zedg = final.callPackage ./package.nix {};
    };
  };
}
