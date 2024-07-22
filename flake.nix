{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.utils.url = "github:numtide/flake-utils";
  inputs.foundry.url = "github:shazow/foundry.nix/monthly"; # Use monthly branch for permanent releases

  outputs = { self, nixpkgs, utils, foundry }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs
          {
            inherit system;
            overlays = [
              foundry.overlay
              (final: prev: {
                # Overlaying nodejs here to ensure nodePackages use the desired
                # version of nodejs use by the upstream CI.
                nodejs = prev.nodejs-18_x;
                pnpm = prev.nodePackages.pnpm;
                yarn = prev.nodePackages.yarn;
              })
            ];
          };
      in
      {
        devShells.default = with pkgs; mkShell {
          buildInputs = [
            foundry-bin
            nodejs
            yarn
          ];
          shellHook = ''
            # Add node executables (incl. hardhat) to PATH
            export PATH=$PWD/node_modules/.bin:$PATH
          '';

        };

      });
}
