{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  vtk,
}:

stdenv.mkDerivation {
  pname = "dicom2mesh";
  # Upstream tags no release; debian/changelog of this tree names it 0.823.
  version = "0.823-unstable-c552b4f";

  src = fetchFromGitHub {
    owner = "eidelen";
    repo = "DicomToMesh";
    rev = "c552b4fd6c6776dab7437f83fb06cb6264f5e831";
    hash = "sha256-g5kHa1CeM6XQPKuVVaqFAHO5XqCgPjT9SWIro7yKBCY=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ vtk ];

  # The upstream tests fetch GoogleTest with FetchContent; keep the build
  # offline and build only the command-line program.
  cmakeFlags = [
    "-DBUILD_GUI=OFF"
    "-DUSE_VTK_DICOM=OFF"
    "-DTESTDICOM2MESH=OFF"
    "-DTESTDICOM2MESHLIB=OFF"
    "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
  ];

  # These sources rely on transitive <iostream>/<iomanip> includes that
  # current GCC and VTK no longer provide.
  postPatch = ''
    substituteInPlace lib/src/meshVisualizer.cpp \
      --replace-fail '#include "meshVisualizer.h"' \
                     $'#include "meshVisualizer.h"\n#include <iomanip>\n#include <iostream>'
    substituteInPlace dicom2mesh/src/dicom2mesh.cpp \
      --replace-fail '#include "volumeVisualizer.h"' \
                     $'#include "volumeVisualizer.h"\n#include <iomanip>\n\nusing namespace std;'
  '';

  postInstall = ''
    install -Dm644 -t $out/share/doc/dicom2mesh ../LICENSE.md ../README.md
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/bin/dicom2mesh
    grep -qF "Permission is hereby granted" $out/share/doc/dicom2mesh/LICENSE.md
    runHook postInstallCheck
  '';

  meta = {
    description = "Convert DICOM or PNG image volumes into 3D surface meshes";
    longDescription = ''
      dicom2mesh builds a 3D surface mesh from a DICOM image series or from a
      list of PNG slices.  It extracts an iso surface from the volume and can
      reduce, filter, smooth, and center the mesh before exporting it as OBJ,
      STL, or PLY.  Only the command-line program is built; the Qt interface
      and the vtk-dicom reader are disabled.
    '';
    homepage = "https://github.com/eidelen/DicomToMesh";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "dicom2mesh";
  };
}
