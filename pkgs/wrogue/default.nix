{ lib, stdenv, fetchFromGitHub, makeWrapper, SDL }:

stdenv.mkDerivation {
  pname = "wrogue";
  version = "0.8.0";

  # Recovery of the last original release; later commits only port the Mac
  # build to SDL2.
  src = fetchFromGitHub {
    owner = "anthonycicc";
    repo = "warp_rogue";
    rev = "675bb5db48434469582367c420b907b129bd6543";
    hash = "sha256-zOBQfBCAFPeh7h7ICbC271ObPc5jObUxodThS5RHm84=";
  };

  sourceRoot = "source/src";
  # The release target copies its binary and notes to the parent directory.
  postUnpack = "chmod u+w source";

  # Print the preformatted fatal message as data, not as a format string.
  postPatch = ''
    substituteInPlace program_manager/program_manager.c \
      --replace-fail 'fprintf(stderr, buffer);' 'fputs(buffer, stderr);'
  '';

  nativeBuildInputs = [ makeWrapper SDL ];
  buildInputs = [ SDL ];

  makefile = "unix.mak";
  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];
  buildFlags = [ "release" ];

  # Data files are read relative to the working directory; saved games and
  # settings go to $HOME/.wrogue.
  installPhase = ''
    runHook preInstall
    install -Dm755 wrogue $out/libexec/wrogue/wrogue
    mkdir -p $out/share/wrogue
    cp -r ../data $out/share/wrogue/data
    makeWrapper $out/libexec/wrogue/wrogue $out/bin/wrogue \
      --chdir $out/share/wrogue
    install -Dm644 -t $out/share/doc/wrogue \
      ../license.txt ../changes.txt ../compile_guide.txt ../scenario_guide.txt \
      platform/unix/readme.txt platform/sdl/sdl.txt ../data/info/credits.txt
    # Complete MT19937 BSD notice required for binary distribution.
    install -Dm644 -t $out/share/doc/wrogue/third-party lib/tt.c
    runHook postInstall
  '';

  meta = {
    description = "Gothic science fantasy roguelike with recruitable companions";
    longDescription = ''
      Warp Rogue is a turn-based science fantasy roguelike with character
      careers, psychic powers, tactical combat and recruitable companions.
      This is the recovered original 0.8.0 C release built with SDL 1.2,
      including its scenario, bitmap font, graphics, help and scripts.
      Saved games and settings are stored in ~/.wrogue.
    '';
    homepage = "https://github.com/anthonycicc/warp_rogue";
    license = with lib.licenses; [ gpl3Only bsd3 ];
    platforms = lib.platforms.linux;
    mainProgram = "wrogue";
  };
}
