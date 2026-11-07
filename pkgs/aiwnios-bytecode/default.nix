{ aiwnios }:

# The channel aiwnios built with the upstream portable bytecode backend, as in
# Guix's aiwnios-bytecode variant.  All patches, the HolyC runtime bootstrap
# and the build and install checks are inherited from the native package.
aiwnios.overrideAttrs (old: {
  pname = "aiwnios-bytecode";

  cmakeFlags = old.cmakeFlags ++ [ "-DUSE_BYTECODE=ON" ];

  # Fail early unless CMake selected the bytecode backend for the executable
  # (c/CMakeLists.txt adds the definition USE_BYTECODE=21 only then).
  postBuild = ''
    grep -rqs -- '-DUSE_BYTECODE=21' --include=flags.make .
  '' + old.postBuild;

  meta = old.meta // {
    description = "HolyC compiler and host environment using the bytecode backend";
    longDescription = ''
      Aiwnios compiles and executes HolyC on a host operating system.  Its
      self-hosted runtime includes the TempleOS-style DolDoc desktop, editor,
      graphics, help and example applications, plus command-line and terminal
      modes.  The installed boot template is copied to a writable directory
      (~/.local/share/aiwnios/T) on first launch; -t selects another boot
      directory.  This variant uses the upstream portable bytecode backend:
      HolyC is compiled to bytecode and interpreted instead of being compiled
      to native machine code.  HolyC runs with the user's authority and is not
      a sandbox.
    '';
  };
})
