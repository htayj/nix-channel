{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  makeWrapper,
  nodejs,
  git,
  koffi,
  node-pty,
}:

let
  # npm installation paths, names, versions and archive hashes recorded by the
  # Guix squad recipe from package-lock.json at the pinned commit. The
  # proprietary @github/copilot CLI packages and Koffi's platform prebuilds are
  # absent; koffi and node-pty come from this channel, built from source.
  npmDeps = [
    [ "node_modules/@alcalzone/ansi-tokenize" "@alcalzone/ansi-tokenize" "0.3.0" "sha256-QJRfFe8rg/U4JK6SLhv8he9DTso95PJpPcfOLsZmKsw=" ]
    [ "node_modules/@alcalzone/ansi-tokenize/node_modules/is-fullwidth-code-point" "is-fullwidth-code-point" "5.1.0" "sha256-8aZRWUwoYKCgB9ulIbr7fLQvwZkRDfV+Sz6w0zbVI8M=" ]
    [ "node_modules/@github/copilot-sdk" "@github/copilot-sdk" "1.0.9" "sha256-iRH9Bt28ks1fDqor7TKgvZSeiuq3E3gAfCQmibtjzXg=" ]
    [ "node_modules/@grpc/grpc-js" "@grpc/grpc-js" "1.14.4" "sha256-9iiJe29VDQMJt2wK4tM0cNW5rIQNcfnaPBDlS51u4IY=" ]
    [ "node_modules/@grpc/proto-loader" "@grpc/proto-loader" "0.8.1" "sha256-wnBVRrIN5jC/DYFUUBLKRgIwLu8HDzxlW98LxVurJPc=" ]
    [ "node_modules/@hono/node-server" "@hono/node-server" "2.1.0" "sha256-DZYnlUauULnv0WSWDGyuCmSYjX3CmITZ9A54KfyGkZw=" ]
    [ "node_modules/@js-sdsl/ordered-map" "@js-sdsl/ordered-map" "4.4.2" "sha256-RFl3VD5iwI2+soWhd7BdSESFvNT9qArVAU0pxFT0dHY=" ]
    [ "node_modules/@modelcontextprotocol/sdk" "@modelcontextprotocol/sdk" "1.30.0" "sha256-LKw/Pjj+woFe2e+vopR/r4xpVzEGhPmXA/PRgPPprxo=" ]
    [ "node_modules/@modelcontextprotocol/sdk/node_modules/ajv" "ajv" "8.20.0" "sha256-svCzqJO7uMxe+2gU8IsUmeGeMdXdc2g/WJM4L0j257M=" ]
    [ "node_modules/@modelcontextprotocol/sdk/node_modules/json-schema-traverse" "json-schema-traverse" "1.0.0" "sha256-AjIiYi3yn8J0veXTWQ5Hqh1Kjjwdbiq6AplI7Xl5myE=" ]
    [ "node_modules/@opentelemetry/api" "@opentelemetry/api" "1.9.1" "sha256-EeKvrkd1rNI+c89KExo5XSGY6uO93e0XciD72rlnPNI=" ]
    [ "node_modules/@opentelemetry/api-logs" "@opentelemetry/api-logs" "0.221.0" "sha256-Mcs7l3uG9LMSrRHE+dEEWu+Fz11cAcWxsRzgKfs86O8=" ]
    [ "node_modules/@opentelemetry/configuration" "@opentelemetry/configuration" "0.221.0" "sha256-0pq3IfdgPhtMmJNvBqvbtkxy1bpDQFx9mgbWS41BG3w=" ]
    [ "node_modules/@opentelemetry/context-async-hooks" "@opentelemetry/context-async-hooks" "2.10.0" "sha256-FBZgKyxEf51qcwUpMJae4pqGlwKd6Af/x6daM5fyDk8=" ]
    [ "node_modules/@opentelemetry/core" "@opentelemetry/core" "2.10.0" "sha256-BE/a3YbB/3Xw+5L1xFsTrjDyKtJor+D5vFDHuGOcDrY=" ]
    [ "node_modules/@opentelemetry/exporter-logs-otlp-grpc" "@opentelemetry/exporter-logs-otlp-grpc" "0.221.0" "sha256-e+FvBupthgw4QncWf+iGOn14C+dXc0HJkU495wYyljc=" ]
    [ "node_modules/@opentelemetry/exporter-logs-otlp-http" "@opentelemetry/exporter-logs-otlp-http" "0.221.0" "sha256-hxc2NLRy7kw+uhqL1IaYE+bLwWneFitGONOX+ALKS9g=" ]
    [ "node_modules/@opentelemetry/exporter-logs-otlp-proto" "@opentelemetry/exporter-logs-otlp-proto" "0.221.0" "sha256-2NTr4WqYad0Jmfop1p/ZznzxRbxOJhrJGQvGh9iudmc=" ]
    [ "node_modules/@opentelemetry/exporter-metrics-otlp-grpc" "@opentelemetry/exporter-metrics-otlp-grpc" "0.221.0" "sha256-T/8fl3C6YcdrATuTY+NF0lWzSYePoaWznZ0jkvyUI8A=" ]
    [ "node_modules/@opentelemetry/exporter-metrics-otlp-http" "@opentelemetry/exporter-metrics-otlp-http" "0.221.0" "sha256-kMUwIGbzadg4ywpcP/zbRxCec04GvWPF4D3heNRLq7U=" ]
    [ "node_modules/@opentelemetry/exporter-metrics-otlp-proto" "@opentelemetry/exporter-metrics-otlp-proto" "0.221.0" "sha256-1j7mgjZaPDR6iz9pW75p5qYYavoAfm++VTP28aZzgUU=" ]
    [ "node_modules/@opentelemetry/exporter-prometheus" "@opentelemetry/exporter-prometheus" "0.221.0" "sha256-kCiOuvwLvj7WU7xOTkkQxGjA9mNx724zhxZlEj12Xxs=" ]
    [ "node_modules/@opentelemetry/exporter-trace-otlp-grpc" "@opentelemetry/exporter-trace-otlp-grpc" "0.221.0" "sha256-Rs7e5/GjIuXFQxHoAbMRrJ9yDzregNczqL0B0Oc81C0=" ]
    [ "node_modules/@opentelemetry/exporter-trace-otlp-http" "@opentelemetry/exporter-trace-otlp-http" "0.221.0" "sha256-xkzoa7rdHA8yuLcxv4ERhtkIaEFo7hxj6m+7qhFmChQ=" ]
    [ "node_modules/@opentelemetry/exporter-trace-otlp-proto" "@opentelemetry/exporter-trace-otlp-proto" "0.221.0" "sha256-uFlxeYblHOD1BGVyovtK886tO/piAn4WlucFh8MxnGc=" ]
    [ "node_modules/@opentelemetry/exporter-zipkin" "@opentelemetry/exporter-zipkin" "2.10.0" "sha256-EbwbvC1CpV8PVBk/xq4ncqjGM93gNu/pAxF5gvfk9kU=" ]
    [ "node_modules/@opentelemetry/instrumentation" "@opentelemetry/instrumentation" "0.221.0" "sha256-LOrDR9eayKjYHgP1zjerucuAKABoBKgt54ykzhCpxrw=" ]
    [ "node_modules/@opentelemetry/otlp-exporter-base" "@opentelemetry/otlp-exporter-base" "0.221.0" "sha256-5C5VFJy46uelv8Ch/C3zDrsVkofaoWOXdxoyDEwkoMk=" ]
    [ "node_modules/@opentelemetry/otlp-grpc-exporter-base" "@opentelemetry/otlp-grpc-exporter-base" "0.221.0" "sha256-tR1LBSZ5fnTsgjvAKNinist9aMOCNSyXmRxziqXKArQ=" ]
    [ "node_modules/@opentelemetry/otlp-transformer" "@opentelemetry/otlp-transformer" "0.221.0" "sha256-WQlb2KKraPyXY100fIgNGQpxZI4JWecVAGmVS9G7Ir4=" ]
    [ "node_modules/@opentelemetry/propagator-b3" "@opentelemetry/propagator-b3" "2.10.0" "sha256-QAYS2TboFQX958ocuMMkg2i5SiXC3Swcb8yOuBfDuBA=" ]
    [ "node_modules/@opentelemetry/propagator-jaeger" "@opentelemetry/propagator-jaeger" "2.10.0" "sha256-sQzUPs5iYoRWspabJJvlOthjrS8D8qq32AQmT4zpYKo=" ]
    [ "node_modules/@opentelemetry/resources" "@opentelemetry/resources" "2.10.0" "sha256-4IVtEmeYuPCmueqXzOTtM7KlGIehQRZPo4+yNvrKn4M=" ]
    [ "node_modules/@opentelemetry/sdk-logs" "@opentelemetry/sdk-logs" "0.221.0" "sha256-MQm7d+1+xdRilgl0Mb5d944nRZorghj8S/Nba8oLQ8Y=" ]
    [ "node_modules/@opentelemetry/sdk-metrics" "@opentelemetry/sdk-metrics" "2.10.0" "sha256-A9RXCZjn6hKBA0QAZNucvAg85/VocGUss3o6yfLZVMk=" ]
    [ "node_modules/@opentelemetry/sdk-node" "@opentelemetry/sdk-node" "0.221.0" "sha256-vctx7d9Tz/u/A7okMG7pYGQCCmigFZa3lsAPa+7T5e8=" ]
    [ "node_modules/@opentelemetry/sdk-trace" "@opentelemetry/sdk-trace" "2.10.0" "sha256-fgTo46ehkvcxkAsP1Pk5KZiZvECc9ZejvsdpoaoYw9o=" ]
    [ "node_modules/@opentelemetry/sdk-trace-base" "@opentelemetry/sdk-trace-base" "2.10.0" "sha256-ZjQxm8oDtEAQPluh5RhxhhobKQfXMPysEWbC4la1oeI=" ]
    [ "node_modules/@opentelemetry/sdk-trace-node" "@opentelemetry/sdk-trace-node" "2.10.0" "sha256-LaItsvfwOyuRXXVeJB11nqlfgEz1rg2qqtA3KxcezTY=" ]
    [ "node_modules/@opentelemetry/semantic-conventions" "@opentelemetry/semantic-conventions" "1.43.0" "sha256-RGWDnfnPJQRurLZON6OOei0DNUY1YzUZAjS61gvYXUI=" ]
    [ "node_modules/@protobufjs/aspromise" "@protobufjs/aspromise" "1.1.2" "sha256-AEGHi4IJ8vpLzF4GZjVevJb/l/NgwwVP/oPbt47hwRk=" ]
    [ "node_modules/@protobufjs/base64" "@protobufjs/base64" "1.1.2" "sha256-1n5u5uFEVRJHjN/DTBIUT1eb3Z8GUp7vPvjYj4QDGmo=" ]
    [ "node_modules/@protobufjs/codegen" "@protobufjs/codegen" "2.0.5" "sha256-ILr+0SIby6I6JFCoQZmO2u+aVrwhAdbjjCEX3VihOgE=" ]
    [ "node_modules/@protobufjs/eventemitter" "@protobufjs/eventemitter" "1.1.1" "sha256-VTa5jLcGLnccHa3Rgo41Lr5AA08UgINvIcd27DcqeXw=" ]
    [ "node_modules/@protobufjs/fetch" "@protobufjs/fetch" "1.1.1" "sha256-VEgdnGLevOHDiwI58jWO6ztz97sboxBb1hI/2BuLcmg=" ]
    [ "node_modules/@protobufjs/float" "@protobufjs/float" "1.0.2" "sha256-ILPWEtUygbdUYC1SqOam4JAyFp1TmeUV9vXot9PecS0=" ]
    [ "node_modules/@protobufjs/path" "@protobufjs/path" "1.1.2" "sha256-zDZO6RAXPDbVc0U1ortTuOfobS0hnychgVirPz3KMow=" ]
    [ "node_modules/@protobufjs/pool" "@protobufjs/pool" "1.1.0" "sha256-9yHb0nKC0sfRwr8a6fegPMPvnPiC/kaaMsFNHa5zJwM=" ]
    [ "node_modules/@protobufjs/utf8" "@protobufjs/utf8" "1.1.2" "sha256-USvOSOW7U9Q1GkFb4hxkMOMxA+zKgxQ55+bPt6o/yn0=" ]
    [ "node_modules/@types/emscripten" "@types/emscripten" "1.41.5" "sha256-vfMd3lwpKtNAcb0h4SaTKARViEAFtVNbF+hiS8yt9qg=" ]
    [ "node_modules/@types/node" "@types/node" "26.2.0" "sha256-ATysqeRVcLEeqPuz+LnjJ0NpNrNiiAZAtZ+f4qz93sk=" ]
    [ "node_modules/@types/react" "@types/react" "19.2.18" "sha256-vVSl/moIPUgKOrA5csu6d0LaTaUDW7W9W1OzdMyXw3Q=" ]
    [ "node_modules/@types/sql.js" "@types/sql.js" "1.4.11" "sha256-Gwv/8H8SstnK0q/5VFNSo0loquYDqce5Cz1uAXXtTQE=" ]
    [ "node_modules/@types/ws" "@types/ws" "8.18.1" "sha256-3CdjlSokvxXckggwotKITCO8zAioU+hVbjR3FAElT6U=" ]
    [ "node_modules/accepts" "accepts" "2.0.0" "sha256-Fz2RX32I34zU2yEpoDDDscnK/Tt67luJRlvzrRg3JUI=" ]
    [ "node_modules/ajv-formats" "ajv-formats" "3.0.1" "sha256-9NaYD9NnOB/SkZkGaRHoY9uNl0lmE7bCxbkVY6FQrMU=" ]
    [ "node_modules/ajv-formats/node_modules/ajv" "ajv" "8.20.0" "sha256-svCzqJO7uMxe+2gU8IsUmeGeMdXdc2g/WJM4L0j257M=" ]
    [ "node_modules/ajv-formats/node_modules/json-schema-traverse" "json-schema-traverse" "1.0.0" "sha256-AjIiYi3yn8J0veXTWQ5Hqh1Kjjwdbiq6AplI7Xl5myE=" ]
    [ "node_modules/ansi-escapes" "ansi-escapes" "7.3.0" "sha256-KtdFB7lX9pnI+XFxFRBLKU2dbZVEwjrtotlJd8DGHOU=" ]
    [ "node_modules/ansi-regex" "ansi-regex" "6.2.2" "sha256-50a7j13YgF3EDDmbkaSiMtt9n5P+LYO3canKzntSMdc=" ]
    [ "node_modules/ansi-styles" "ansi-styles" "6.2.3" "sha256-6TnPUTjXpdTjQQCs0BU1d7KVMwWTEVehz+n6pWODkRs=" ]
    [ "node_modules/auto-bind" "auto-bind" "5.0.1" "sha256-xKF+AUuEsEjNNrVg3o1Ug9B4l6vhYmEALMPP2KL3iVo=" ]
    [ "node_modules/body-parser" "body-parser" "2.3.0" "sha256-Ax1/bFFC4xvpHTakP1QfAqUFlD47hxqkTvX7aTm+JY4=" ]
    [ "node_modules/body-parser/node_modules/content-type" "content-type" "2.0.0" "sha256-otRonUT03iwsUDn1jgEnny1LsTmUpQRt5BPncqWhvAY=" ]
    [ "node_modules/bytes" "bytes" "3.1.2" "sha256-g143rVpA2kXq7W4y2ZhHYnoVsqRnF0EYJSH+SN7jxYE=" ]
    [ "node_modules/call-bind-apply-helpers" "call-bind-apply-helpers" "1.0.2" "sha256-Bz6f+dur7fXBKAIKZ3OB6fkskBiNEYgwswp2VqfDfSw=" ]
    [ "node_modules/call-bound" "call-bound" "1.0.4" "sha256-MghvSS/t8bmzSBHy7lDKLMpT2lx4P3zV+TnT8ehrvTI=" ]
    [ "node_modules/chalk" "chalk" "5.6.2" "sha256-lJV3FaSDqjudtgyPItVJgifYAlxAf5gu74HjTzdXT/0=" ]
    [ "node_modules/cjs-module-lexer" "cjs-module-lexer" "2.2.0" "sha256-SQOf8RnocNdoodzy1kQ4rFzZSHsjWt5km02WCwJSf/k=" ]
    [ "node_modules/cli-boxes" "cli-boxes" "4.0.1" "sha256-ecxd45jHV5yn78jLcFfNOV9IZjfHrE87byheBylYugU=" ]
    [ "node_modules/cli-cursor" "cli-cursor" "4.0.0" "sha256-a9x0UvwLG8v0U0q1+36CKV+V/8if1KwPnyhr4Vi5MKs=" ]
    [ "node_modules/cli-truncate" "cli-truncate" "6.0.0" "sha256-uQtGuN3SkWiz/Ixf6es23+oDmhFR3t+UebW59Tf5ONU=" ]
    [ "node_modules/cli-truncate/node_modules/string-width" "string-width" "8.2.1" "sha256-6VSYsdU9CJYogTlHeEDB+BUQv/8uS2umYz1P9Q2qNew=" ]
    [ "node_modules/cliui" "cliui" "8.0.1" "sha256-3vrR4l6KNJ6pzdEGar9eHnYvf5Cd5yvcpnuzX3dGjI0=" ]
    [ "node_modules/cliui/node_modules/ansi-regex" "ansi-regex" "5.0.1" "sha256-Dg6tzaragF212FtTrVzcoHYLmW7hmeyWWOezSqbI4Nk=" ]
    [ "node_modules/cliui/node_modules/string-width" "string-width" "4.2.3" "sha256-rbtPsbJugGmvma3/AHk2nJPxfPiHuRCGaR1nHdvVKTQ=" ]
    [ "node_modules/cliui/node_modules/strip-ansi" "strip-ansi" "6.0.1" "sha256-m9t10L/0nxVt2MO8sOBrP6lsPYjd1MNCpDRYZqQMCMo=" ]
    [ "node_modules/code-excerpt" "code-excerpt" "4.0.0" "sha256-IBFZViP698majpA6Gfy3CDPuyTp3wwPIbShfem8bQQQ=" ]
    [ "node_modules/color-convert" "color-convert" "2.0.1" "sha256-kg+kNTjAGaCF278Ey29yzDN2JOX1IXUZ8Oey73hOfOE=" ]
    [ "node_modules/color-name" "color-name" "1.1.4" "sha256-UHt8RGHo65QTVa+aWemn4CzQ58YXa0jRgJdmNE8/Fwg=" ]
    [ "node_modules/content-disposition" "content-disposition" "1.1.0" "sha256-L4sZJaixI6hmBsETIvwQqvwd2F8oYP/+Mok+IK70CTw=" ]
    [ "node_modules/content-type" "content-type" "1.0.5" "sha256-rDHQmEBfAkLdcSIY84oUpiAr1OsBBn2wXbdl2am9Esg=" ]
    [ "node_modules/convert-to-spaces" "convert-to-spaces" "2.0.1" "sha256-iFCNGWOAcs7w8o/Z2lZ5rOBhh8YbntJ1QaxTUVsL/kA=" ]
    [ "node_modules/cookie" "cookie" "0.7.2" "sha256-drFg+CUcYwoRai4KzwNVewdYl1ssDfgAYHJI/JquniA=" ]
    [ "node_modules/cookie-signature" "cookie-signature" "1.2.2" "sha256-TSu6rxwpnmDvDX35UrUq+Vsg1Wy8vURo1CEGUAg1U9M=" ]
    [ "node_modules/cors" "cors" "2.8.6" "sha256-MiQhJDlxQIAOEjiiUrTNdGadWMgbZV2dNyF4m1bBwf8=" ]
    [ "node_modules/cross-spawn" "cross-spawn" "7.0.6" "sha256-GIwyDNxBOt/sAwmP2nKvepsCFSuhPTqPh/Fy2TztOOo=" ]
    [ "node_modules/csstype" "csstype" "3.2.3" "sha256-81AfjuHHP3Vo/ssiwRIxFiwEZ+WSYkYdpVeVGTB0J6M=" ]
    [ "node_modules/debug" "debug" "4.4.3" "sha256-icGsnJRu6JBah1g3EUUo6X7q414DvjGQWEsiFq9D5Kc=" ]
    [ "node_modules/depd" "depd" "2.0.0" "sha256-KKWKIFYJNEHx0A1nfZWRjS5LPpi6yGI3FZEByuMV1Kc=" ]
    [ "node_modules/dunder-proto" "dunder-proto" "1.0.1" "sha256-7RNCIoyCwQ35khxZ1oTfUWoM1u0lth5fnWMwiVMmz9s=" ]
    [ "node_modules/ee-first" "ee-first" "1.1.1" "sha256-UUjo634iKyoJEnYYu9tQM9r2Jiz8c10xAeqYYgEouZw=" ]
    [ "node_modules/emoji-regex" "emoji-regex" "8.0.0" "sha256-tczZ+/sICY7vvra2tLQNtts6z5JD4yfgOZJaqGYcsQc=" ]
    [ "node_modules/encodeurl" "encodeurl" "2.0.0" "sha256-my5Bi4hRuPnnoT1a2jvU08XvBCiFhnJh9VY0fUu++yk=" ]
    [ "node_modules/environment" "environment" "1.1.0" "sha256-sssP3ob4DX118kNUVlBf1ot5EqppGKKpZDubgpV2gX8=" ]
    [ "node_modules/es-define-property" "es-define-property" "1.0.1" "sha256-WYa4sTEhNAqLDVx9jw+WGqgO86dFFcqct6eNhu0Dhfc=" ]
    [ "node_modules/es-errors" "es-errors" "1.3.0" "sha256-0U3Rw1tL07isoyGf02J+t/PrSc9rTIp8pYuR/XoZCZM=" ]
    [ "node_modules/es-module-lexer" "es-module-lexer" "2.3.1" "sha256-gpMOxO5NT+WQ/y551NQ57B9BHlbN5Wp//iCe7mZ1SK0=" ]
    [ "node_modules/es-object-atoms" "es-object-atoms" "1.1.2" "sha256-8pXF32dRxltLlJKwPIj6teE0Gd4opR7N8X5pO0pCGvA=" ]
    [ "node_modules/es-toolkit" "es-toolkit" "1.45.1" "sha256-CrEK4YwIU/DJie4YfOzZ1bLdVhvfKzyfMUu8mBqrQn8=" ]
    [ "node_modules/escalade" "escalade" "3.2.0" "sha256-uidVr8DmxnBTJnEf0hjr4QelJ+zL1khRVf3pjtAAvuc=" ]
    [ "node_modules/escape-html" "escape-html" "1.0.3" "sha256-oQEVXDy9+x5PmPL4PIteOS22rM+mBt8OuouHpXYrA2Y=" ]
    [ "node_modules/etag" "etag" "1.8.1" "sha256-9qlseKlz0qtmDJ7+7mqnSjmc2edwYluh7ZXhrKn9D68=" ]
    [ "node_modules/eventsource" "eventsource" "3.0.7" "sha256-fGLUuxluWbOcWveeVQ1v5CYWSadNn15gWwceHaYIHJI=" ]
    [ "node_modules/eventsource-parser" "eventsource-parser" "3.0.8" "sha256-zVZHfTCbJXTS6wU9dai9iXF2FZugY6QGeV6pVPqnXlA=" ]
    [ "node_modules/express" "express" "5.2.1" "sha256-F3OhbAK0QiZTR5ucTSESaPcCK9rA2Be1aYU1u0hd0AU=" ]
    [ "node_modules/express-rate-limit" "express-rate-limit" "8.5.2" "sha256-tTeMUHmME4/AyyqPfzd7akwRypfDXKf+HPLYNNkZOpM=" ]
    [ "node_modules/fast-deep-equal" "fast-deep-equal" "3.1.3" "sha256-sBmgmA8nY43D+Fg2sOR48YjgDXpuWFLAgZ+ob1bke48=" ]
    [ "node_modules/fast-uri" "fast-uri" "3.1.5" "sha256-gqcefjcW3Iw5LKwHYrzoBhTPU57yIABBXibq9cRTzi8=" ]
    [ "node_modules/finalhandler" "finalhandler" "2.1.1" "sha256-IpSb/FGmILNZi75n1lYZqe/XgdUnBKONe6Z14kiouHI=" ]
    [ "node_modules/forwarded" "forwarded" "0.2.0" "sha256-m1pd6V+4X8tY215PzZTOirnwR20CIC4gpSJc7GBDHJk=" ]
    [ "node_modules/fresh" "fresh" "2.0.0" "sha256-rQg5erBfYrK1B2guI6rWmc+Mwzki4AML4MtkCiMnetc=" ]
    [ "node_modules/function-bind" "function-bind" "1.1.2" "sha256-cEQCZRsCoUVPF9RF/H3XFu/CgtBZQHEm1Y7zCkfoB6o=" ]
    [ "node_modules/get-caller-file" "get-caller-file" "2.0.5" "sha256-exPhyBlJ/0wbquSsTjSZBJLV6Khtq347kAJ7H1Emk18=" ]
    [ "node_modules/get-east-asian-width" "get-east-asian-width" "1.5.0" "sha256-6C1npNk+f/zmsSrk6Fi/h8YQ4jv7oce7sfAuU+sYXjg=" ]
    [ "node_modules/get-intrinsic" "get-intrinsic" "1.3.0" "sha256-Zi4n5U4A/kb7sI+fSqywVONpXb5yzBS0NmE/vPt4BUQ=" ]
    [ "node_modules/get-proto" "get-proto" "1.0.1" "sha256-6yzFKvsfH9gsX8KljCOA8PFv3NtWMVOPPGaIdDXXBoE=" ]
    [ "node_modules/gopd" "gopd" "1.2.0" "sha256-1TbQ3k3ShdwUaPu385M0pH7g7snCf5tiam5xRmyf2oI=" ]
    [ "node_modules/has-symbols" "has-symbols" "1.1.0" "sha256-RGDHUy8ouN8t3JoewXgW1Dwk1LlZHcbFk2uC9/hq58U=" ]
    [ "node_modules/hasown" "hasown" "2.0.4" "sha256-6dKwP5VXNgDhwTEkzmGOMULtLFONFkWVvtzUQIuKTkw=" ]
    [ "node_modules/hono" "hono" "4.13.0" "sha256-txsxMpL6n2Ags66rH5TwfONbpJo9NpSK4s4NpNE9g/8=" ]
    [ "node_modules/http-errors" "http-errors" "2.0.1" "sha256-rWK7sRuvB5aZo/Jp7Qie/bWJvhYIPO7ZShEXgB4abGE=" ]
    [ "node_modules/iconv-lite" "iconv-lite" "0.7.2" "sha256-YdRnaecfkjWuTS9WUuV0Ljvrg/sJap2EJHEDYk6NoD4=" ]
    [ "node_modules/import-in-the-middle" "import-in-the-middle" "3.3.2" "sha256-QabEOjfaIqX2InMVuQEidGpHFysnmnLtFmc6jkNwHSc=" ]
    [ "node_modules/indent-string" "indent-string" "5.0.0" "sha256-3USK2uU0LnZIPWnE/3RR6/DhoW8QRFq/RSR8gV6b9+Y=" ]
    [ "node_modules/inherits" "inherits" "2.0.4" "sha256-2U28bBuzxawPsSpzreGHEI/GDeJzobdU9VBE614kr68=" ]
    [ "node_modules/ink" "ink" "7.1.1" "sha256-hFsxR+wHHGeqK6j0KCVBQjGslQUAGBsAXhZ3AWxRs5o=" ]
    [ "node_modules/ink/node_modules/signal-exit" "signal-exit" "3.0.7" "sha256-Q5Yj+mqrkWAGFex1fqoTf8q0DTs13aON90RMFWePIKg=" ]
    [ "node_modules/ink/node_modules/string-width" "string-width" "8.2.0" "sha256-zdRkgalYV+uwzY7aOHVWJwcUUUJnsU0rQZInkGRiaIs=" ]
    [ "node_modules/ink/node_modules/wrap-ansi" "wrap-ansi" "10.0.0" "sha256-RF1Jopam+OmsNFHuIUDn0XcmZv+E8tYum8qLIQRkgso=" ]
    [ "node_modules/ip-address" "ip-address" "10.4.0" "sha256-4fr/oqoZtDgmZP14q55b8Gpt3MUlvZyCvXRSJIe+KTI=" ]
    [ "node_modules/ipaddr.js" "ipaddr.js" "1.9.1" "sha256-dEHZYj9n/kFg7M/YKumkBNzVXh5PG2jgbiN02t5Oj+4=" ]
    [ "node_modules/is-fullwidth-code-point" "is-fullwidth-code-point" "3.0.0" "sha256-b0Fdrl3GBw8bQtruYWXquUGpcQGYIwX6zIuv2vMAvEo=" ]
    [ "node_modules/is-in-ci" "is-in-ci" "2.0.0" "sha256-kEtHk6TM869aeZHydx8dcrkztlHra7qjnCRYb01hEV8=" ]
    [ "node_modules/is-promise" "is-promise" "4.0.0" "sha256-hTiRFzh2+gO4diz2Pn8MDWDlJJR/Tk1YUtlMIqy0Rac=" ]
    [ "node_modules/isexe" "isexe" "2.0.0" "sha256-R8/ocuCI4oxTtzb+8wUyS1fMHPyfcqmw92n5JzHLg1k=" ]
    [ "node_modules/jose" "jose" "6.2.3" "sha256-xESL4J8YRwZlORtqKas+wQjmgwt4rqkwds4zSPt7VaU=" ]
    [ "node_modules/json-schema-typed" "json-schema-typed" "8.0.2" "sha256-59xBJuT89MMHOz9+mVMerchjP3g3sg7Jc1mo163Qa8k=" ]
    [ "node_modules/jsonc-parser" "jsonc-parser" "3.3.1" "sha256-SgMVuGcedGO65698FCzfGemqe6Oes23C3zg7hkjjy8k=" ]
    [ "node_modules/lodash.camelcase" "lodash.camelcase" "4.3.0" "sha256-UGLYNaGeEc9h4lW2R28jLodCONyH2+aM0swt2IvgZ00=" ]
    [ "node_modules/long" "long" "5.3.2" "sha256-aAM+Rmdz331SyeWTQbtynYNxbNkgxWRgOVckRW1kayY=" ]
    [ "node_modules/math-intrinsics" "math-intrinsics" "1.1.0" "sha256-uMLDVXVJPcCG34jPxGip4mUbZhczZICrPwD8+FP0Q6c=" ]
    [ "node_modules/media-typer" "media-typer" "1.1.0" "sha256-tdxTHh0e/JLPtlm+EedOfml8rvk1wjPgUBanspl8Gb4=" ]
    [ "node_modules/merge-descriptors" "merge-descriptors" "2.0.0" "sha256-rogyKl/HGVLTmQrpmaevx6S/fLoIa5zMHJSCQysQHc4=" ]
    [ "node_modules/mime-db" "mime-db" "1.54.0" "sha256-KyEFTmXQ6r1YxQAtJxPpaN1HsVcAv+1LcoGjRN7RxCA=" ]
    [ "node_modules/mime-types" "mime-types" "3.0.2" "sha256-L53Sg1PDA/+HUPv2jkdHVbAcVKmJiD0ifWBfe/o90qw=" ]
    [ "node_modules/mimic-fn" "mimic-fn" "2.1.0" "sha256-6nBcJhSGxO8qjJNrFZyGrR10Udevx7f5fMLRgFwEZr8=" ]
    [ "node_modules/module-details-from-path" "module-details-from-path" "1.0.4" "sha256-8evIfa7xSFb/w5OV+KqPkJcnedryOFn1sDjZvLH3pfU=" ]
    [ "node_modules/ms" "ms" "2.1.3" "sha256-9mFuFeUw7VUvnaotPOcZY5R8a8fJjJtk/T5nP9AmIsY=" ]
    [ "node_modules/negotiator" "negotiator" "1.0.0" "sha256-taLf7h3ArFLGI81cAwS+WopBz61A4J8aE2BpcsstvAQ=" ]
    [ "node_modules/node-addon-api" "node-addon-api" "7.1.1" "sha256-sQRV0VqXfAzRehyw62eeA9k5+O+NQwLrM+H3jazHH4I=" ]
    [ "node_modules/object-assign" "object-assign" "4.1.1" "sha256-eC1yaiY7p7JsztYSr5e4ADVRbfSwzXiFJOeyzrxOKe0=" ]
    [ "node_modules/object-inspect" "object-inspect" "1.13.4" "sha256-gySWejr9ikWwQB41VK68GEP0k77EaomnzozwcuYukL8=" ]
    [ "node_modules/on-finished" "on-finished" "2.4.1" "sha256-9k1C8QScOGzaxSBHN+CVZCcWObK30gOj6gfsB9XdvQo=" ]
    [ "node_modules/once" "once" "1.4.0" "sha256-z1FGC6Nwxpj2i5duUU0RNJczm6AYtgA+jo61acb8z88=" ]
    [ "node_modules/onetime" "onetime" "5.1.2" "sha256-8Fmy6oAct7JTxGE/Q9ls1Wro3aVvqgmZU5qheVclqs0=" ]
    [ "node_modules/parseurl" "parseurl" "1.3.3" "sha256-Vu9L+hHgl86BlrJvoEtC1gkcMkmPyrRHjm3SmENfAho=" ]
    [ "node_modules/patch-console" "patch-console" "2.0.0" "sha256-oW2LMZHl5dCWdmjolMWSx54vPjMHhuNhhmhDMLo8t2c=" ]
    [ "node_modules/path-key" "path-key" "3.1.1" "sha256-S4mZrLkUgw7c08W4/sYysyxrx1msPtyGM29angi6e5I=" ]
    [ "node_modules/path-to-regexp" "path-to-regexp" "8.4.2" "sha256-6HEqnFOwoqJ8/sx7gMVN+Sr7RkPAE1Hisuu3eEvKvXg=" ]
    [ "node_modules/pkce-challenge" "pkce-challenge" "5.0.1" "sha256-0fy7rlvAVWLRPefFIMKVFpnoJiqDF/psi7zY3P876nA=" ]
    [ "node_modules/protobufjs" "protobufjs" "7.6.5" "sha256-1msI0TarB+UmlBgKc53t4x2Q5VG56W/Yg4+cSvp/+G8=" ]
    [ "node_modules/proxy-addr" "proxy-addr" "2.0.7" "sha256-oNG2809tTnM0KbqV9623gzyM6rkWuldKk/ioR2vuRtk=" ]
    [ "node_modules/qrcode-terminal" "qrcode-terminal" "0.12.0" "sha256-OmJgxODYC9Uno/kw6Q6iNIwDZGYh8lqgvZYO4gWgpwY=" ]
    [ "node_modules/qs" "qs" "6.15.2" "sha256-5pnUs6xiGB9bzSnB0VIkBUwg2BqrZ/ey51t/eiGFuJc=" ]
    [ "node_modules/range-parser" "range-parser" "1.2.1" "sha256-kFJm4mYlkLAJ443AltTk4QOq/anLZ+ZYyphbLQrS+SY=" ]
    [ "node_modules/raw-body" "raw-body" "3.0.2" "sha256-Zt4qAlA23li75Qqx1Cok7G0z7aM4uBFaPr+ULa6EGds=" ]
    [ "node_modules/react" "react" "19.2.8" "sha256-lMa54HhYVNLl2WKM7AXDPtAXtqkAKvXod41BNOmtphE=" ]
    [ "node_modules/react-reconciler" "react-reconciler" "0.33.0" "sha256-PKpc9JP6wt3OTOGp300rOPUiOkkFXI+2cpiMOaCHVgI=" ]
    [ "node_modules/require-directory" "require-directory" "2.1.1" "sha256-cDvuCEQ2A4P+SoeS1KWlYmR0JqBT51l6HScqxVTzhsg=" ]
    [ "node_modules/require-from-string" "require-from-string" "2.0.2" "sha256-y2lKSWWQj3d1oMdX8Az05iTRk81x13mI+8yg9Ze4jYI=" ]
    [ "node_modules/require-in-the-middle" "require-in-the-middle" "8.0.1" "sha256-hAclJWSEF58J7wamtoNcvDnwqVzWbC9GUMscpN7ADDQ=" ]
    [ "node_modules/restore-cursor" "restore-cursor" "4.0.0" "sha256-2ZrWWneY0u4PocgNPEtFAsEcdSFRgDkMNF3DhZiK9gc=" ]
    [ "node_modules/restore-cursor/node_modules/signal-exit" "signal-exit" "3.0.7" "sha256-Q5Yj+mqrkWAGFex1fqoTf8q0DTs13aON90RMFWePIKg=" ]
    [ "node_modules/router" "router" "2.2.0" "sha256-sUSvN7OalRf3qJ8dhn6cLPKfE/QUfT6AxJn+b/q2lGE=" ]
    [ "node_modules/safer-buffer" "safer-buffer" "2.1.2" "sha256-eIEvZa47mAcc4cm6y+Bmb0Ig0LJ1PCoRUw6yffRAo7M=" ]
    [ "node_modules/scheduler" "scheduler" "0.27.0" "sha256-qybONc5AMvBLeM/Fu7TP4TNY6f56VDOoqmMVw968UJU=" ]
    [ "node_modules/send" "send" "1.2.1" "sha256-+iVPsxbdI93LK+69UzsjeIrsTPaj26WK80FQFwQ1xHI=" ]
    [ "node_modules/serve-static" "serve-static" "2.2.1" "sha256-NtT3K7WTcusYIC/uJf89i/RmVfASGDD74y4yy9xiX0M=" ]
    [ "node_modules/setprototypeof" "setprototypeof" "1.2.0" "sha256-yDvMbqYyVn4/aSioOhwMcHNRmqypuIuEejtARBfq3+I=" ]
    [ "node_modules/shebang-command" "shebang-command" "2.0.0" "sha256-msulvRilHpzfWJg4Dk32P4A+GETe9krhpG+Iz/htVW4=" ]
    [ "node_modules/shebang-regex" "shebang-regex" "3.0.0" "sha256-/turqm2ybGvgGD+Cd336hS1Zpi+Ihd6TvTLrwodYlY8=" ]
    [ "node_modules/side-channel" "side-channel" "1.1.0" "sha256-hJPne5kLJC7+vYJNCRLfFhv2QPx1Bx1byETODXcGpIU=" ]
    [ "node_modules/side-channel-list" "side-channel-list" "1.0.1" "sha256-eTyUrCFb53J1cEX4gEQGV4uMvBvafhzeIwEfkUWvdPc=" ]
    [ "node_modules/side-channel-map" "side-channel-map" "1.0.1" "sha256-OyVrZCEwC8yWLYkbFYj9S2ToTjObnCn3jGG3LypxFtY=" ]
    [ "node_modules/side-channel-weakmap" "side-channel-weakmap" "1.0.2" "sha256-OypU8MXnrYmMjw/9oqaAX7LMXWj1Ot3wtKnsDbnQ0G4=" ]
    [ "node_modules/slice-ansi" "slice-ansi" "9.0.0" "sha256-vVOX3ywlaK5Y0niontxFqprBvW041oYvCXLQdHITybc=" ]
    [ "node_modules/slice-ansi/node_modules/is-fullwidth-code-point" "is-fullwidth-code-point" "5.1.0" "sha256-8aZRWUwoYKCgB9ulIbr7fLQvwZkRDfV+Sz6w0zbVI8M=" ]
    [ "node_modules/sql.js" "sql.js" "1.14.1" "sha256-qC50wHOtZR0gzTYXdsxP/Shjx/cPe7yxdA2GVxQHPfE=" ]
    [ "node_modules/stack-utils" "stack-utils" "2.0.6" "sha256-6zKoUas4DqCU1HLYBOhBbN8KQ8exJDzSdCLI0BEpLv8=" ]
    [ "node_modules/stack-utils/node_modules/escape-string-regexp" "escape-string-regexp" "2.0.0" "sha256-ddjbwfaX9R2LDbTUgOjbToJUhlMTZcAdCYJ587TTOxY=" ]
    [ "node_modules/statuses" "statuses" "2.0.2" "sha256-yoAKJHEEiLVo9Oc+j1cN1rkRwSLL9CsGkw3ufCWUn+A=" ]
    [ "node_modules/string-width" "string-width" "8.1.0" "sha256-BGHZoW6iTrUVAuLYbsbpMCqbl2c9LZ2g0O+NZR8DFFs=" ]
    [ "node_modules/strip-ansi" "strip-ansi" "7.2.0" "sha256-L6Ad6GpQIu8ydzq7xOhKU6HF0x9aXL8D7SV18QQIVD8=" ]
    [ "node_modules/tagged-tag" "tagged-tag" "1.0.0" "sha256-faYCqWC8F9CdN1KoVGbPckG0vEoJCdJSU2Mru8UE62Y=" ]
    [ "node_modules/terminal-size" "terminal-size" "4.0.1" "sha256-dEatzdgsgjlxwigIDCqcnJVceFSMtkbVLDrTLY2yukM=" ]
    [ "node_modules/toidentifier" "toidentifier" "1.0.1" "sha256-GG/Md0iN4yfa+RHTYtTnc7q5kJ8d8qXwwguHUgW5Lgg=" ]
    [ "node_modules/type-fest" "type-fest" "5.5.0" "sha256-AyQV5EIf9T0RFzTLuchTwY1S6fQkxujao1XyXUYETL8=" ]
    [ "node_modules/type-is" "type-is" "2.1.0" "sha256-mlMIjWnNSI4MLLT87lqYMInA1JJATPISFhx3UB+zAvw=" ]
    [ "node_modules/type-is/node_modules/content-type" "content-type" "2.0.0" "sha256-otRonUT03iwsUDn1jgEnny1LsTmUpQRt5BPncqWhvAY=" ]
    [ "node_modules/typescript" "typescript" "6.0.3" "sha256-M80O4b6qjJ6dFanag2xi3epMNKQtfC00nbyA2UFl0io=" ]
    [ "node_modules/undici-types" "undici-types" "8.3.0" "sha256-B6chyyzQ3XmMJHV9400U6LZA/4/d74XWYuALOSViofI=" ]
    [ "node_modules/unpipe" "unpipe" "1.0.0" "sha256-LfteBtHUvx/p8Pp/YzxKL94E2LQc8Lm9JJpCVh1e37Y=" ]
    [ "node_modules/vary" "vary" "1.1.2" "sha256-c3iGBnE3ejXnpEPs/coHRc/QZvWVyQ1YG4J97+okbnE=" ]
    [ "node_modules/vscode-jsonrpc" "vscode-jsonrpc" "8.2.1" "sha256-kZj5Y+i4k/GJfe4PnavMzPB3MiXMNsq9amPPZ63hL7w=" ]
    [ "node_modules/which" "which" "2.0.2" "sha256-oTrfX93rdpZV7c5VHoH7sRkEucm+dtleQdqMTEmdTtw=" ]
    [ "node_modules/widest-line" "widest-line" "6.0.0" "sha256-JEVdtyylMK3ENa77lXt01NZ6FpMxR3EvIns9wfoUR8U=" ]
    [ "node_modules/wrap-ansi" "wrap-ansi" "7.0.0" "sha256-B5WzUQvS6Tj2pBU5bePU9Y/XbvH4JJoHGWRE6vhcpC8=" ]
    [ "node_modules/wrap-ansi/node_modules/ansi-regex" "ansi-regex" "5.0.1" "sha256-Dg6tzaragF212FtTrVzcoHYLmW7hmeyWWOezSqbI4Nk=" ]
    [ "node_modules/wrap-ansi/node_modules/ansi-styles" "ansi-styles" "4.3.0" "sha256-LFOaRthatgMxg5l0NNLZpcos7vwStNuQIvVkeEzXmH8=" ]
    [ "node_modules/wrap-ansi/node_modules/string-width" "string-width" "4.2.3" "sha256-rbtPsbJugGmvma3/AHk2nJPxfPiHuRCGaR1nHdvVKTQ=" ]
    [ "node_modules/wrap-ansi/node_modules/strip-ansi" "strip-ansi" "6.0.1" "sha256-m9t10L/0nxVt2MO8sOBrP6lsPYjd1MNCpDRYZqQMCMo=" ]
    [ "node_modules/wrappy" "wrappy" "1.0.2" "sha256-r/NzDZG3seFDgilW0UYI9WMWPPEbnQrmAt8f4eQw/fs=" ]
    [ "node_modules/ws" "ws" "8.21.0" "sha256-0ItyazquOg/tUhig2aSyrI111K1FOpJx21X+OOlOtM8=" ]
    [ "node_modules/y18n" "y18n" "5.0.8" "sha256-1DdDutOnyzr107a/cP0y/jkj6obkFIEJxt0BJt6tp2k=" ]
    [ "node_modules/yaml" "yaml" "2.9.0" "sha256-AI+iBMsbpwDgJyugRau/Cab/5jRW6BRrqXysbCrR75E=" ]
    [ "node_modules/yargs" "yargs" "17.7.3" "sha256-dqwwg0Z08NjanHv+2xdfatomBCDmR17f3MVRxgH4cX4=" ]
    [ "node_modules/yargs-parser" "yargs-parser" "21.1.1" "sha256-NCt9Un1KciZbZPJ3EVFzScPAXuMCqzuMdFLwv75wkVE=" ]
    [ "node_modules/yargs/node_modules/ansi-regex" "ansi-regex" "5.0.1" "sha256-Dg6tzaragF212FtTrVzcoHYLmW7hmeyWWOezSqbI4Nk=" ]
    [ "node_modules/yargs/node_modules/string-width" "string-width" "4.2.3" "sha256-rbtPsbJugGmvma3/AHk2nJPxfPiHuRCGaR1nHdvVKTQ=" ]
    [ "node_modules/yargs/node_modules/strip-ansi" "strip-ansi" "6.0.1" "sha256-m9t10L/0nxVt2MO8sOBrP6lsPYjd1MNCpDRYZqQMCMo=" ]
    [ "node_modules/yoga-layout" "yoga-layout" "3.2.1" "sha256-SLx3YYpzanUrpqP4OIYuVHw44LIr6fXcAwrExFV+f/8=" ]
    [ "node_modules/zod" "zod" "4.3.6" "sha256-Ke5NJBjA+23cVFwowD7IC3AeNFo/d55QriPNoHALFoI=" ]
    [ "node_modules/zod-to-json-schema" "zod-to-json-schema" "3.25.2" "sha256-pJGataMq/0/WwRnJ8Yfw3UtMSQ0wxMT9r3xf9vONk/Q=" ]
    [ "packages/squad-cli/node_modules/vscode-jsonrpc" "vscode-jsonrpc" "9.0.1" "sha256-fx0X/AZjxfp48edD+M0OGIt9Vp014HqnJTOK9kVUicI=" ]
    [ "packages/squad-sdk/node_modules/vscode-jsonrpc" "vscode-jsonrpc" "9.0.1" "sha256-fx0X/AZjxfp48edD+M0OGIt9Vp014HqnJTOK9kVUicI=" ]
    [ "packages/squad-sdk/node_modules/ws" "ws" "8.21.3" "sha256-3zRU7yBXkc5QtbkkF2Lc+b/hqp9/AdMFcim+fawMLcM=" ]
  ];

  # Build-only paths that stay out of the installed tree.
  buildOnly = [
    "node_modules/typescript"
    "node_modules/@types/ws"
    "node_modules/@types/sql.js"
    "node_modules/@types/emscripten"
  ];

  fetchNpm =
    name: version: hash:
    fetchurl {
      url = "https://registry.npmjs.org/${name}/-/${lib.last (lib.splitString "/" name)}-${version}.tgz";
      inherit hash;
    };

  # Two MIT notices the published archives omit.
  notices = {
    "node_modules/@github/copilot-sdk/LICENSE" = fetchurl {
      url = "https://raw.githubusercontent.com/github/copilot-sdk/cc8c7f28ea9f1894fe91a2cf161e2e6f8a52ff51/LICENSE";
      hash = "sha256-JRC0RrwfDPlwJFMHXSDNiGMeIOVkJljttzJdnB61NPc=";
    };
    "node_modules/yoga-layout/LICENSE" = fetchurl {
      url = "https://raw.githubusercontent.com/react/yoga/042f5013152eb81c1552dec945b88f7b95ca350f/LICENSE";
      hash = "sha256-UkEte8fOQVfqYou6rLiCngqcs8WPV/mRdhJryM8r/IU=";
    };
  };

  unpackDeps = lib.concatMapStrings (
    dep:
    let
      path = builtins.elemAt dep 0;
      src = fetchNpm (builtins.elemAt dep 1) (builtins.elemAt dep 2) (builtins.elemAt dep 3);
    in
    ''
      mkdir -p ${path}
      tar xzf ${src} -C ${path} --strip-components=1
    ''
  ) npmDeps;

  # Workspace-local modules install below their @bradygaster package.
  installPath =
    path:
    if lib.hasPrefix "packages/" path then
      "lib/node_modules/@bradygaster/${lib.removePrefix "packages/" path}"
    else
      "lib/${path}";

  runtimePaths =
    builtins.filter (path: !(builtins.elem path buildOnly)) (map builtins.head npmDeps)
    ++ [
      "node_modules/koffi"
      "node_modules/node-pty"
    ];
in
stdenv.mkDerivation {
  pname = "squad";
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "bradygaster";
    repo = "squad";
    rev = "92ff24ef3d5b597b85192d1100ab4106578bbaf3";
    hash = "sha256-F5FMk2HEQq/cfgD6HJP/WpuMZeeSSvIddXC61YDcv00=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
  ];

  postPatch = ''
    # Node's copyFile keeps the read-only store mode; make fresh copies of
    # templates user-writable while preserving an existing destination's mode.
    substituteInPlace packages/squad-sdk/src/storage/fs-storage-provider.ts \
      --replace-fail "copyFile } from 'fs/promises'" "copyFile, chmod as fsChmod } from 'fs/promises'" \
      --replace-fail "copyFileSync, rmSync } from 'fs'" "copyFileSync, rmSync, chmodSync as fsChmodSync } from 'fs'" \
      --replace-fail "      await copyFile(safeSrc, safeDest);" \
        "      const mode = fsExistsSync(safeDest) ? (await fsStat(safeDest)).mode : undefined;
          await copyFile(safeSrc, safeDest);
          await fsChmod(safeDest, mode ?? ((await fsStat(safeDest)).mode | 0o200));" \
      --replace-fail "      copyFileSync(safeSrc, safeDest);" \
        "      const mode = fsExistsSync(safeDest) ? statSync(safeDest).mode : undefined;
          copyFileSync(safeSrc, safeDest);
          fsChmodSync(safeDest, mode ?? (statSync(safeDest).mode | 0o200));"
  '';

  configurePhase = ''
    runHook preConfigure
    ${unpackDeps}
    ${lib.concatStrings (lib.mapAttrsToList (path: src: "cp ${src} ${path}\n") notices)}
    cp -r ${koffi}/lib/node_modules/koffi ${node-pty}/lib/node_modules/node-pty node_modules/
    chmod -R u+w node_modules/koffi node_modules/node-pty
    mkdir -p node_modules/@bradygaster
    ln -s ../../packages/squad-sdk node_modules/@bradygaster/squad-sdk
    ln -s ../../packages/squad-cli node_modules/@bradygaster/squad-cli
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR SKIP_BUILD_BUMP=1
    # The reviewed source transformations from npm's prebuild, without hooks.
    node scripts/sync-skill-templates.mjs
    node scripts/sync-templates.mjs --sync
    node packages/squad-cli/scripts/patch-esm-imports.mjs
    node packages/squad-cli/scripts/patch-ink-rendering.mjs
    node node_modules/typescript/bin/tsc -p packages/squad-sdk/tsconfig.json
    cp -r packages/squad-sdk/src/presets/builtin packages/squad-sdk/dist/presets/
    find packages/squad-sdk/dist/presets/builtin -name '*.ts' -delete
    node node_modules/typescript/bin/tsc -p packages/squad-cli/tsconfig.json
    cp -r packages/squad-cli/src/remote-ui packages/squad-cli/dist/
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    ${lib.concatMapStrings (path: ''
      mkdir -p $out/${dirOf (installPath path)}
      cp -r ${path} $out/${installPath path}
    '') runtimePaths}
    for workspace in squad-sdk squad-cli; do
      dest=$out/lib/node_modules/@bradygaster/$workspace
      mkdir -p $dest
      cp -r packages/$workspace/dist packages/$workspace/templates packages/$workspace/package.json $dest/
      cp LICENSE $dest/
    done
    install -Dm644 -t $out/share/doc/squad LICENSE README.md
    # Standalone mode writes a local MCP launcher instead of an npx spec.
    makeWrapper ${lib.getExe nodejs} $out/bin/squad \
      --add-flags $out/lib/node_modules/@bradygaster/squad-cli/dist/cli-entry.js \
      --prefix PATH : ${lib.makeBinPath [ git nodejs ]} \
      --set SQUAD_STANDALONE_HOME $out/bin
    ln -s ${lib.getExe nodejs} $out/bin/squad-node
    runHook postInstall
  '';

  doInstallCheck = true;
  # Offline project initialization outside the source tree.
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/check-home NO_COLOR=1
    mkdir -p $HOME $TMPDIR/check
    cd $TMPDIR/check
    ${lib.getExe git} init -q
    $out/bin/squad --version | grep -F 0.13.0
    $out/bin/squad --help > /dev/null
    $out/bin/squad init --preset default
    test -f .squad/team.md
    cd -
    runHook postInstallCheck
  '';

  meta = {
    description = "Multi-agent development team runtime and CLI for GitHub Copilot";
    homepage = "https://github.com/bradygaster/squad";
    license = lib.licenses.mit;
    mainProgram = "squad";
    platforms = [ "x86_64-linux" ];
  };
}
