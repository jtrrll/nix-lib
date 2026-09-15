{
  lib,
  stdenv,
  systemd,
  writeShellApplication,
}:
writeShellApplication rec {
  meta = {
    description = "Prevents system sleep while a command runs";
    homepage = "https://github.com/jtrrll/nix-lib";
    license = lib.licenses.agpl3Plus;
    mainProgram = name;
    maintainers = [
      lib.maintainers.jtrrll
    ];
    platforms = lib.platforms.unix;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
  name = "keep-awake";
  runtimeInputs = lib.optional stdenv.hostPlatform.isLinux systemd;
  text =
    if stdenv.hostPlatform.isDarwin then
      ''
        exec caffeinate -dims "$@"
      ''
    else
      ''
        exec systemd-inhibit --what=idle:sleep --who=keep-awake --why="Running: $*" "$@"
      '';
}
