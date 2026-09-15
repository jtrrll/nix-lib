{
  config.perSystem =
    { pkgs, ... }:
    {
      config.files.file.".github/dependabot.yaml".source =
        let
          yaml = pkgs.formats.yaml { };
          generated = yaml.generate "dependabot.yaml" {
            version = 2;
            updates = [
              {
                package-ecosystem = "github-actions";
                commit-message.prefix = "deps(actions)";
                directory = "/";
                labels = [
                  "automated"
                  "dependencies"
                ];
                schedule.interval = "weekly";
              }
              {
                package-ecosystem = "nix";
                commit-message.prefix = "deps(flake)";
                directory = "/";
                labels = [
                  "automated"
                  "dependencies"
                ];
                schedule = {
                  interval = "weekly";
                  day = "friday";
                };
              }
            ];
          };
        in
        pkgs.runCommand "dependabot.yaml" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
          yq 'pick(["version", "updates"]) | .updates[] |= pick(["package-ecosystem", "commit-message", "directory", "labels", "schedule", "groups"])' ${generated} > $out
        '';
    };
}
