{
  lib,
  ...
}:
{
  config.perSystem =
    { pkgs, ... }:
    let
      yaml = pkgs.formats.yaml { };

      nixInstallerConf = lib.concatStringsSep "\n" [
        "allow-import-from-derivation = false"
        "extra-substituters = https://devenv.cachix.org https://nix-community.cachix.org"
        "extra-trusted-public-keys = devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];

      nixInstallerStep = {
        uses = "DeterminateSystems/nix-installer-action@v22";
        "with".extra-conf = nixInstallerConf;
      };

      checkoutStep = {
        uses = "actions/checkout@v7";
      };

      uploadEvalStatsStep = artifactName: {
        name = "Upload Nix evaluation statistics";
        uses = "actions/upload-artifact@v7";
        "with" = {
          name = artifactName;
          path = "nix_eval_stats.json";
        };
      };

      evalStatsEnv = {
        NIX_SHOW_STATS = 1;
        NIX_SHOW_STATS_PATH = "nix_eval_stats.json";
      };

      generated = yaml.generate "ci.yaml" {
        name = "CI";
        "on" = {
          pull_request.branches = [ "*" ];
          push.branches = [ "main" ];
          schedule = [ { cron = "0 06 * * MON"; } ];
          workflow_dispatch = { };
        };
        concurrency = {
          cancel-in-progress = true;
          group = "\${{ github.workflow }}-\${{ github.ref }}";
        };
        env.NIXPKGS_ALLOW_UNFREE = 1;
        jobs = {
          check = {
            name = "Check";
            runs-on = "ubuntu-latest";
            steps = [
              checkoutStep
              nixInstallerStep
              { uses = "DeterminateSystems/flake-checker-action@v13"; }
              {
                name = "Check flake";
                env = evalStatsEnv;
                run = "nix run github:Mic92/nix-fast-build -- --flake .#checks.x86_64-linux --impure --skip-cached --stream-json-lines";
              }
              (uploadEvalStatsStep "nix-eval-stats-check")
            ];
          };
        };
      };
    in
    {
      config.files.file.".github/workflows/ci.yaml".source =
        pkgs.runCommand "ci.yaml" { nativeBuildInputs = [ pkgs.yq-go ]; }
          ''
            yq '
              pick(["name", "on", "concurrency", "env", "jobs"]) |
              .jobs[] |= pick(["name", "strategy", "runs-on", "steps"]) |
              .jobs[].steps[] |= pick(["name", "if", "uses", "with", "env", "run"])
            ' ${generated} > $out
          '';
    };
}
