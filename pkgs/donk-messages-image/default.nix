{ dockerTools, nodejs_22, cacert, runCommand
, bridgeSource ? builtins.fetchGit {
    url = "ssh://git@192.168.7.121/tay/bridge.git";
    rev = "286cb5447d94755a52c5ddf7cec5dcbfeda9f8f2";
  }
}:
let
  application = runCommand "donk-messages-source" { } ''
    mkdir -p $out/app
    cp ${bridgeSource}/src/donk/*.ts $out/app/
  '';
in dockerTools.buildLayeredImage {
  name = "localhost/donk-messages";
  tag = "286cb54";
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
    Labels."org.opencontainers.image.revision" = "286cb5447d94755a52c5ddf7cec5dcbfeda9f8f2";
  };
}
