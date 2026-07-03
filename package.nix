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

      if [ -x "$out/bin/zedg" ] && [ ! -e "$out/bin/zed" ]; then
        ln -s "$out/bin/zedg" "$out/bin/zed"
      fi

      if [ -f "$out/share/applications/zedg.desktop" ]; then
        substituteInPlace "$out/share/applications/zedg.desktop" \
          --replace-fail "Exec=zedg %F" "Exec=$out/bin/zedg %F" \
          --replace-fail "TryExec=zedg" "TryExec=$out/bin/zedg" \
          || true
      fi

      runHook postInstall
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
