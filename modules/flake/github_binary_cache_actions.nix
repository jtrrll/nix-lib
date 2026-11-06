{ flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.githubBinaryCacheActions;
      yaml = pkgs.formats.yaml { };

      actionPath = ".github/actions/nix-binary-cache";

      mkAction =
        name: action:
        let
          generated = yaml.generate "action.yml" action;
        in
        {
          "${actionPath}/${name}/action.yml".source =
            pkgs.runCommand "action.yml" { nativeBuildInputs = [ pkgs.yq-go ]; }
              ''
                yq '
                  pick(["name", "description", "inputs", "outputs", "runs"]) |
                  .runs.steps[] |= pick(["id", "name", "if", "uses", "with", "env", "shell", "run"])
                ' ${generated} > $out
              '';
        };

      pathInput = {
        description = "Directory holding the binary cache";
        required = true;
      };
    in
    {
      options.githubBinaryCacheActions = {
        enable = lib.mkEnableOption "GitHub Actions that restore and save a file-based Nix binary cache";
      };

      config.files.file = lib.mkIf cfg.enable (
        mkAction "restore" {
          name = "Restore Nix binary cache";
          description = "Restores a file-based Nix binary cache from the most recent cache whose key starts with the given prefix";
          inputs = {
            path = pathInput;
            key-prefix = {
              description = "Prefix shared by the keys of caches to restore from";
              required = true;
            };
          };
          runs = {
            using = "composite";
            steps = [
              {
                name = "Restore binary cache";
                uses = "actions/cache/restore@v6";
                "with" = {
                  path = "\${{ inputs.path }}";
                  key = "\${{ inputs.key-prefix }}";
                  restore-keys = "\${{ inputs.key-prefix }}";
                };
              }
            ];
          };
        }
        // mkAction "save" {
          name = "Save Nix binary cache";
          description = "Adds store paths to a file-based Nix binary cache, leaving out paths cache.nixos.org already serves, and saves it";
          inputs = {
            path = pathInput;
            key = {
              description = "Key to save the binary cache under";
              required = true;
            };
            paths = {
              description = "Newline-separated store paths to add to the binary cache";
              required = true;
            };
          };
          runs = {
            using = "composite";
            steps = [
              {
                id = "push";
                name = "Push built outputs to binary cache";
                shell = "bash";
                env = {
                  CACHE_DIR = "\${{ inputs.path }}";
                  STORE_PATHS = "\${{ inputs.paths }}";
                };
                run = ''
                  built_outputs="$RUNNER_TEMP/built_outputs.txt"
                  printf '%s\n' "$STORE_PATHS" | sed '/^$/d' | sort -u > "$built_outputs"
                  echo "count=$(wc -l < "$built_outputs")" >> "$GITHUB_OUTPUT"
                  [ -s "$built_outputs" ] || exit 0

                  # The Nix daemon creates the cache directory as root when it first queries the substituter.
                  mkdir -p "$CACHE_DIR"
                  sudo chown -R "$(id -u):$(id -g)" "$CACHE_DIR"

                  xargs nix copy --to "file://$CACHE_DIR?compression=none" < "$built_outputs"

                  cd "$CACHE_DIR" || exit 1
                  # Drop paths that cache.nixos.org already serves, then the NARs no remaining narinfo uses.
                  find . -maxdepth 1 -name '*.narinfo' -printf '%f\n' | sed 's/\.narinfo$//' \
                    | xargs -P 32 -I{} sh -c 'curl -fsI --retry 2 -o /dev/null https://cache.nixos.org/{}.narinfo && rm {}.narinfo || true'
                  grep -h '^URL:' ./*.narinfo | sed 's/^URL: //' | sort -u > "$RUNNER_TEMP/kept_nars.txt"
                  find nar -type f | sort | comm -23 - "$RUNNER_TEMP/kept_nars.txt" | xargs --no-run-if-empty rm
                '';
              }
              {
                name = "Save binary cache";
                "if" = "steps.push.outputs.count != '0'";
                uses = "actions/cache/save@v6";
                "with" = {
                  path = "\${{ inputs.path }}";
                  key = "\${{ inputs.key }}";
                };
              }
            ];
          };
        }
      );
    }
  );
}
