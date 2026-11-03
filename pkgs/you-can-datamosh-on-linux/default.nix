{ lib, stdenvNoCC, fetchFromGitHub, python3, ffmpeg-headless, makeWrapper }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "you-can-datamosh-on-linux";
  # Upstream publishes no releases; pin the only upstream commit series HEAD.
  version = "0-unstable-2017-02-09";

  src = fetchFromGitHub {
    owner = "happyhorseskull";
    repo = "you-can-datamosh-on-linux";
    rev = "bc4df09891139649d7848540d32c0b2216aa748f";
    hash = "sha256-D/LAvKOoil4a3hU8Pio1/++/BQXpjIoZ28zuQvONBcY=";
  };

  nativeBuildInputs = [ makeWrapper python3 ];

  dontConfigure = true;
  dontBuild = true;

  # Upstream builds FFmpeg command lines as shell strings.  Pass every FFmpeg
  # invocation as an argument list instead, so file names containing spaces or
  # shell metacharacters stay single arguments.  Also import the
  # ArgumentTypeError that video_to_gif.py raises for a missing input file.
  postPatch = ''
    python3 - <<'EOF'
    import re

    def harden(path, calls):
        with open(path) as f:
            text = f.read()
        pattern = re.compile(r"subprocess\.call\(.*?, shell=True\)", re.S)
        found = pattern.findall(text)
        assert len(found) == len(calls), (path, len(found))
        for old, new in zip(found, calls):
            text = text.replace(old, "subprocess.call(" + new + ")", 1)
        assert "shell=True" not in text, path
        return text

    mosh = harden("do_the_mosh.py", [
        "['ffmpeg', '-loglevel', 'error', '-y', '-i', input_video, "
        "'-crf', '0', '-pix_fmt', 'yuv420p', '-r', str(fps), "
        "'-ss', str(start_sec), '-to', str(end_sec), input_avi]",
        "['ffmpeg', '-loglevel', 'error', '-y', '-i', output_avi, "
        "'-crf', '18', '-pix_fmt', 'yuv420p', '-vcodec', 'libx264', "
        "'-acodec', 'aac', '-r', str(fps), "
        "'-vf', 'scale=' + str(output_width) + ':-2:flags=lanczos', "
        "output_video]",
    ])
    with open("do_the_mosh.py", "w") as f:
        f.write(mosh)

    gif = harden("video_to_gif.py", [
        "['ffmpeg', '-v', 'error', '-ss', str(start_time), "
        "'-t', str(duration), '-i', video, "
        "'-vf', filters + ',palettegen=stats_mode=diff', '-y', palette]",
        "['ffmpeg', '-v', 'error', '-ss', str(start_time), "
        "'-t', str(duration), '-i', video, '-i', palette, "
        "'-lavfi', filters + '[x]; [x][1:v] paletteuse', '-y', gif_file]",
    ])
    old_import = "from argparse import ArgumentParser\n"
    assert old_import in gif
    gif = gif.replace(old_import,
                      "from argparse import ArgumentParser, ArgumentTypeError\n", 1)
    with open("video_to_gif.py", "w") as f:
        f.write(gif)
    EOF
  '';

  installPhase = ''
    runHook preInstall
    for pair in do_the_mosh.py:do-the-mosh video_to_gif.py:video-to-gif; do
      script=''${pair%%:*}
      program=''${pair##*:}
      install -Dm644 $script $out/libexec/you-can-datamosh-on-linux/$script
      makeWrapper ${python3.interpreter} $out/bin/$program \
        --add-flags $out/libexec/you-can-datamosh-on-linux/$script \
        --prefix PATH : ${lib.makeBinPath [ ffmpeg-headless ]}
    done
    install -Dm644 -t $out/share/doc/you-can-datamosh-on-linux README.md LICENSE.md
    runHook postInstall
  '';

  # Real round trip on a generated clip whose name contains a space and a
  # shell metacharacter: datamosh it to MP4, then convert a video to a GIF.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export PYTHONDONTWRITEBYTECODE=1
    mkdir check && cd check
    ${lib.getExe ffmpeg-headless} -loglevel error -f lavfi \
      -i testsrc=duration=4:size=160x120:rate=25 -c:v libx264 'clip one;x.mp4'
    $out/bin/do-the-mosh 'clip one;x.mp4' --end_sec 4 --start_effect_sec 1 \
      --end_effect_sec 2 --repeat_p_frames 2 --output_width 160 \
      --output_dir 'out dir' > mosh.log
    test -s 'out dir/moshed_clip one;x.mp4'
    test ! -e 'out dir/datamoshing_input.avi'
    $out/bin/video-to-gif 'clip one;x.mp4' 0 1 --gif_folder 'gif dir'
    head -c 6 'gif dir/clip one;x.gif' | grep -q GIF89a
    test ! -e 'gif dir/palette.png'
    if $out/bin/video-to-gif missing.mp4 2> missing.err; then exit 1; fi
    grep -q "Couldn't find missing.mp4" missing.err
    cd ..
    runHook postInstallCheck
  '';

  meta = {
    description = "Datamosh videos and convert videos to palette-optimized GIFs";
    longDescription = ''
      Two command-line tools from happyhorseskull/you-can-datamosh-on-linux.
      do-the-mosh converts a video to AVI, repeats P-frames and drops I-frames
      in a chosen interval, and re-encodes the glitched result to MP4.
      video-to-gif converts a video to a GIF with a generated palette.  Both
      run FFmpeg from this package's closure.
    '';
    homepage = "https://github.com/happyhorseskull/you-can-datamosh-on-linux";
    # Upstream is public domain; do_the_mosh.py credits MIT-licensed
    # predecessors in its retained comments.
    license = with lib.licenses; [ unlicense mit ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "do-the-mosh";
  };
})
