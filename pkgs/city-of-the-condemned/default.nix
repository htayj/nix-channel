{ lib, stdenv, fetchFromGitHub, cmake, boost, ncurses, coreutils }:

stdenv.mkDerivation (finalAttrs: {
  pname = "city-of-the-condemned";
  version = "1.0-unstable-2013-e9a8989";

  src = fetchFromGitHub {
    owner = "tapio";
    repo = "cotc";
    rev = "e9a8989d34c9d3e0c68e7e42b526e1bee923ac7c";
    hash = "sha256-czcKutTFdjhb7IVaqVi8lHk7tlCy/Qo+POLt4qPmMnM=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ boost ncurses ];

  # Same CMake adaptation as the Guix package: accept CMake 4, take the
  # version from the builder instead of `git describe`, and compile as C++11
  # because current Boost headers require <type_traits>.  Upstream's bin/
  # holds Windows and x86 prebuilt executables, which are not used.
  postPatch = ''
    rm -r bin
    substituteInPlace CMakeLists.txt \
      --replace-fail "cmake_minimum_required(VERSION 2.6)" "cmake_minimum_required(VERSION 3.5)" \
      --replace-fail "cmake_policy(VERSION 2.6)" "" \
      --replace-fail "-std=c++98" "-std=c++11" \
      --replace-fail 'set(VERSION_MINOR "")' 'set(VERSION_MINOR "0+")' \
      --replace-fail 'add_definitions(-DVERSION_STRING="''${VERSION_MAJOR}.''${VERSION_MINOR}")' \
                     'add_definitions(-DVERSION_STRING="${finalAttrs.version}")'
  '';

  # Upstream has no install rule.  The game writes log.log to its working
  # directory, so the launcher runs it from a per-user XDG state directory.
  installPhase = ''
    runHook preInstall
    install -Dm555 CotC $out/libexec/city-of-the-condemned/cotc
    install -Dm644 ../LICENSE ../README.md -t $out/share/doc/city-of-the-condemned
    mkdir -p $out/bin
    cat > $out/bin/city-of-the-condemned <<EOF
    #!${stdenv.shell}
    set -eu
    umask 077
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME must be set}/.local/state}/city-of-the-condemned"
    case "\$state" in
      /*) ;;
      *) echo 'city-of-the-condemned: state directory must be absolute' >&2; exit 1 ;;
    esac
    ${coreutils}/bin/mkdir -p -- "\$state"
    cd -- "\$state"
    exec $out/libexec/city-of-the-condemned/cotc "\$@"
    EOF
    chmod 555 $out/bin/city-of-the-condemned
    runHook postInstall
  '';

  meta = {
    description = "Terminal roguelike set in a city of angels and demons";
    homepage = "https://github.com/tapio/cotc";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "city-of-the-condemned";
  };
})
