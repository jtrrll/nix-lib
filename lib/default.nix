{
  overlay = libFinal: libPrev: {
    # keep-sorted start block=yes
    maintainers = (libPrev.maintainers or { }) // (import ./maintainers.nix);
    modules = (libPrev.modules or { }) // (import ./modules.nix { lib = libFinal; });
    strings = (libPrev.strings or { }) // (import ./strings.nix { lib = libFinal; });
    # keep-sorted end
  };

  tests = { lib }: {
    # keep-sorted start block=yes
    strings = import ./strings_tests.nix { inherit lib; };
    # keep-sorted end
  };
}
