{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nix-update-script,
}:
buildGoModule (finalAttrs: {
  pname = "snekcheck";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "jtrrll";
    repo = "snekcheck";
    rev = "cff1b32efb10a9a44bad8e02db60145e2a67bbb4";
    hash = "sha256-7rNX5+DeWH/L7E8Rl7qfhWXqpynUIzlj991dLaTTPuI=";
  };
  sourceRoot = "${finalAttrs.src.name}/go";

  vendorHash = "sha256-eeipkAobSq4Nh8zClL5HBRN5wXc2oxkjeqYVh04Zf3c=";
  subPackages = [ "cmd/snekcheck" ];

  passthru.updateScript = nix-update-script {
    attrPath = "snekcheck";
    extraArgs = [
      "--flake"
      "--version=branch"
    ];
  };

  meta = {
    description = "An opinionated filename linter that loves snake case";
    homepage = "https://github.com/jtrrll/snekcheck";
    license = lib.licenses.mit;
    mainProgram = "snekcheck";
    maintainers = [ lib.maintainers.jtrrll ];
    platforms = lib.platforms.unix;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
