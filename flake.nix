{
  description = "Cangjie language support for neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";

    tree-sitter-cangjie = {
      url = "github:ide4cj/tree-sitter-cangjie";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        let
          ts-cangjie-src = inputs.tree-sitter-cangjie;

          cangjie-nvim = pkgs.vimUtils.buildVimPlugin {
            pname = "cangjie.nvim";
            version = "0.1.0";
            src = ./.;

            postInstall = ''
              mkdir -p $out/queries/cangjie
              cp ${ts-cangjie-src}/queries/* $out/queries/cangjie/
            '';
          };

          tree-sitter-cangjie = pkgs.tree-sitter.buildGrammar {
            language = "cangjie";
            version = "0.1.0";
            src = ts-cangjie-src;
          };
        in
        {
          packages = rec {
            inherit tree-sitter-cangjie cangjie-nvim;
            default = cangjie-nvim;
          };
        };
      flake = { };
    };
}
