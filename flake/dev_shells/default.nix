{ config, ... }:
{
  config = {
    perSystem =
      { lib, ... }:
      {
        config.devenv = {
          modules = [
            {
              containers = lib.mkForce { }; # Workaround to remove containers from flake checks.
              overlays = [ config.flake.overlays.default ];
            }
          ];
          shells.default = _: {
            enterShell = ''printf "\033[0;1;36mDEVSHELL ACTIVATED\033[0m\n"'';

            enterTest = ''
              nix --version
            '';

            git-hooks = {
              default_stages = [ "pre-push" ];
              hooks = {
                actionlint.enable = true;
                check-added-large-files = {
                  enable = true;
                  stages = [ "pre-commit" ];
                };
                check-json.enable = true;
                check-yaml.enable = true;
                detect-private-keys = {
                  enable = true;
                  stages = [ "pre-commit" ];
                };
                end-of-file-fixer.enable = true;
                flake-checker.enable = true;
                fmt = {
                  enable = true;
                  entry = "nix fmt";
                  name = "fmt";
                };
                mixed-line-endings.enable = true;
                nil.enable = true;
                no-commit-to-branch = {
                  enable = true;
                  stages = [ "pre-commit" ];
                };
                ripsecrets = {
                  enable = true;
                  stages = [ "pre-commit" ];
                };
              };
            };

            languages.nix.enable = true;
          };
        };
      };
    touchup.attr.packages.any.attr = {
      # Remove deprecated packages that devenv includes.
      devenv-test.enable = false;
      devenv-up.enable = false;
    };
  };
}
