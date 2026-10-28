{ dockerTools, nodejs_22, cacert, runCommand
, bridgeSource ? builtins.fetchGit {
    url = "https://forge.nogroup.group/tay/bridge.git";
    rev = "8b12a0a2c3443965b9ac19481ab5f57433c00f8a";
  }
}:
let
  application = runCommand "donk-messages-source" { } ''
    mkdir -p $out/app
    cp ${bridgeSource}/src/donk/*.ts $out/app/
  '';
in dockerTools.buildLayeredImage {
  name = "localhost/donk-messages";
  tag = "8b12a0a";
  contents = [ application nodejs_22 cacert ];
  config = {
    User = "1000:1000";
    WorkingDir = "/app";
    Cmd = [ "${nodejs_22}/bin/node" "--experimental-strip-types" "--no-warnings" "/app/main.ts" "http" ];
    Env = [
      "NODE_EXTRA_CA_CERTS=${cacert}/etc/ssl/certs/ca-bundle.crt"
      "DONK_STATE_DIR=/data"
      "PORT=8080"
    ];
    ExposedPorts."8080/tcp" = { };
    Labels."org.opencontainers.image.source" = "https://forge.nogroup.group/tay/bridge";
    Labels."org.opencontainers.image.revision" = "8b12a0a2c3443965b9ac19481ab5f57433c00f8a";
  };
}
