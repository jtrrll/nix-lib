{
  lib,
  cargo,
  git,
  installShellFiles,
  makeWrapper,
  rustPlatform,
  stdenv,
  writeShellApplication,
  zellij,
}:
let
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
in
rustPlatform.buildRustPackage (_finalAttrs: {
  pname = cargoToml.package.name;
  inherit (cargoToml.package) version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ];

  # git and zellij are invoked at runtime; make them available regardless of
  # the user's PATH.
  postInstall = ''
    wrapProgram $out/bin/session \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          zellij
        ]
      }
  ''
  # Generate completions by running the built binary (native builds only).
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd session \
      --bash <($out/bin/session completions bash) \
      --fish <($out/bin/session completions fish) \
      --zsh <($out/bin/session completions zsh)
  '';

  meta = {
    description = "Manage development sessions as git worktrees and a zellij session";
    homepage = "https://github.com/jtrrll/nix-lib";
    license = lib.licenses.agpl3Plus;
    mainProgram = "session";
    maintainers = [
      lib.maintainers.jtrrll
    ];
    platforms = lib.platforms.all;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };

  passthru.updateScript = writeShellApplication {
    name = "update-session";
    runtimeInputs = [
      cargo
      git
    ];
    text = ''
      root=$(git rev-parse --show-toplevel)
      cd "$root/pkgs/session"
      cargo update
    '';
  };
})
