{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  zlib,
  openssl,
  fontconfig,
  freetype,
  vulkan-loader,
  libxkbcommon,
  glib,
  alsa-lib,
  mesa,
  libglvnd,
  libepoxy,
  wayland,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxrandr,
  libxrender,
  libxfixes,
}: let
  sources = import ./sources.nix;
  source = sources.${stdenv.hostPlatform.system};
in
  stdenv.mkDerivation rec {
    pname = "zedg";
    version = sources.version;

    src = fetchurl {
      inherit (source) url hash;
    };

    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
    ];

    buildInputs = [
      stdenv.cc.cc.lib

      zlib
      openssl
      fontconfig
      freetype
      vulkan-loader
      libxkbcommon
      glib
      alsa-lib

      mesa
      libglvnd
      libepoxy
      wayland

      libx11
      libxcb
      libxcursor
      libxi
      libxrandr
      libxrender
      libxfixes
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -r . "$out/"

      # Upstream ships the GUI in bin/zedg and the CLI in libexec/zedg.
      # The CLI searches for ../libexec/zed-editor relative to itself.
      # Use that layout so CLI flags and bundle detection work correctly.
      test -x "$out/bin/zedg"
      test -x "$out/libexec/zedg"
      mv "$out/bin/zedg" "$out/libexec/zed-editor"
      mv "$out/libexec/zedg" "$out/bin/zedg"
      ln -sfn zedg "$out/bin/zed"
      ln -sfn ../bin/zedg "$out/libexec/zed-cli"

      if [ -f "$out/share/applications/zedg.desktop" ]; then
        substituteInPlace "$out/share/applications/zedg.desktop" \
          --replace-fail "Exec=zedg %F" "Exec=$out/bin/zedg %F" \
          --replace-fail "TryExec=zedg" "TryExec=$out/bin/zedg" \
          || true
      fi

      runHook postInstall
    '';

    # Exercise bundle detection as well as ELF linking; building alone does
    # not catch a CLI installed next to the wrong GUI executable.
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      "$out/bin/zedg" --version
      runHook postInstallCheck
    '';

    # 上游 tarball 在 Debian/Ubuntu 容器里打包，lib/zedg/ 下混进了构建环境的
    # libgit2.so.1.1.0。它不被 bin/zedg 引用（DT_NEEDED 里没有），但会拖着
    # libmbedtls.so.14 / libpcre.so.3 等 Debian 专属 soname 让 autoPatchelf 失败。
    # 删掉前先确认确实没人引用它，避免上游哪天改成动态链接时静默出问题。
    preFixup = ''
      orphan="$out/lib/zedg/libgit2.so.1.1.0"
      if [ -e "$orphan" ]; then
        if grep -rl --binary-files=text 'libgit2\.so\.1\.1\.0' "$out" \
             --exclude="libgit2.so.1.1.0" | grep -q .; then
          echo "错误：libgit2.so.1.1.0 仍被引用，不能直接删除" >&2
          echo "请改用 buildInputs 补齐 mbedtls_2 / http-parser / pcre 垫片" >&2
          exit 1
        fi
        echo "移除构建环境残留：lib/zedg/libgit2.so.1.1.0"
        rm -f "$orphan"
      fi
    '';

    postFixup = ''
      wrapProgram $out/bin/zedg \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
        vulkan-loader
        libglvnd
        wayland
        libxkbcommon
        alsa-lib
      ]} \
        --set ZED_UPDATE_EXPLANATION "由 Nix 管理，请通过 nix flake update 升级" \
        --set XMODIFIERS "@im=fcitx" \
        --set GTK_IM_MODULE "fcitx" \
        --set QT_IM_MODULE "fcitx" \
        --set LC_CTYPE "zh_CN.UTF-8"
    '';

    meta = {
      description = "ZedG, a Zed editor build with globalization and Chinese localization support";
      homepage = "https://github.com/x6nux/zed-globalization";
      platforms = ["x86_64-linux"];
      mainProgram = "zedg";
    };
  }
