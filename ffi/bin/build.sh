#!/usr/bin/env bash
# Builds minimal-static FFmpeg executables for Native.Encoding.FFmpeg.
#
# Encoder feature surface:
#   in:  image2pipe demuxer, png decoder
#   out: libx264 encoder, mp4/mov muxer
#   fx:  pad, scale, format, null, copy, aresample
#   io:  file + pipe protocols
#
# Targets:
#   darwin-arm64   native (run on a darwin-arm64 host)
#   darwin-amd64   native (run on an Intel Darwin host)
#   linux-amd64    docker --platform linux/amd64  ubuntu:22.04
#   linux-arm64    docker --platform linux/arm64  ubuntu:22.04
#   windows-amd64  docker  dockcross/windows-static-x64
#
# Usage:
#   ./build.sh darwin-arm64
#   ./build.sh linux-amd64
#
# The script writes the resulting ffmpeg binary into this directory under the
# expected name (ffmpeg_<os>_<arch>[.exe]) so go:embed picks it up on rebuild.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-darwin-arm64}"

# Complete, unmodified source archives are also attached to the v0.0.2 release.
# Set SOURCE_DIR to a directory containing those archives for an offline build.
FFMPEG_REV=b08d7969c550a804a59511c7b83f2dd8cc0499b8 # n7.1
X264_REV=31e19f92f00c7003fa115047ce50978bc98c3a0d # stable at release preparation
FFMPEG_SHA256=02fa6d9827da3b6786e4df821218cc036db2b4481e7f48267c2dcda695633afc
X264_SHA256=d053c9d86988d6bc78237ca5205865c5ddf99c98ef4cd9927eec8f6d388f6dd9
SOURCE_DIR="${SOURCE_DIR:-$DIR/sources}"
mkdir -p "$SOURCE_DIR"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

fetch_source () {
  local name="$1" revision="$2" checksum="$3" repository="$4"
  local archive="$SOURCE_DIR/$name-$revision.tar.gz"
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 3 \
      "https://codeload.github.com/$repository/tar.gz/$revision" -o "$archive"
  fi
  printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 --check
}

fetch_source ffmpeg "$FFMPEG_REV" "$FFMPEG_SHA256" FFmpeg/FFmpeg
fetch_source x264 "$X264_REV" "$X264_SHA256" mirror/x264

# --------------------------------------------------------------------------
# Configure flags shared by every target. Keep this list in sync with the
# consumer's requested codecs. If you re-enable a flag, leave a one-line WHY.
# --------------------------------------------------------------------------
FFMPEG_CONFIGURE_ARGS=(
  --disable-everything
  --disable-network
  --disable-debug
  --disable-doc
  --disable-htmlpages --disable-manpages --disable-podpages --disable-txtpages
  --disable-iconv
  --disable-bzlib --disable-lzma
  # No X11 capture is enabled; avoid accidental Homebrew shared dependencies.
  --disable-xlib --disable-libxcb
  --disable-shared --enable-static
  --enable-protocol=file --enable-protocol=pipe
  --enable-demuxer=image2pipe --enable-demuxer=image2 --enable-demuxer=rawvideo
  --enable-decoder=png --enable-decoder=rawvideo
  --enable-parser=png
  --enable-encoder=libx264
  --enable-muxer=mp4 --enable-muxer=mov
  --enable-filter=pad --enable-filter=scale --enable-filter=format
  --enable-filter=null --enable-filter=copy --enable-filter=aresample
  --enable-libx264
  --enable-gpl
)

build_native_darwin () {
  # Pin both x264 and FFmpeg below newer Xcode's host-derived deployment target.
  export MACOSX_DEPLOYMENT_TARGET=14.0
  WORKDIR="$(mktemp -d -t ffmpeg-build.XXXXXX)"
  trap "rm -rf '$WORKDIR'" EXIT

  command -v nasm >/dev/null || { echo "install nasm: brew install nasm"; exit 1; }

  mkdir -p "$WORKDIR/ffmpeg" "$WORKDIR/x264"
  tar -xzf "$SOURCE_DIR/ffmpeg-$FFMPEG_REV.tar.gz" -C "$WORKDIR/ffmpeg" --strip-components=1
  tar -xzf "$SOURCE_DIR/x264-$X264_REV.tar.gz" -C "$WORKDIR/x264" --strip-components=1

  ( cd "$WORKDIR/x264" && \
    ./configure --prefix="$WORKDIR/install" --enable-static --disable-cli --enable-pic && \
    make -j"$(sysctl -n hw.logicalcpu)" && make install )

  ( cd "$WORKDIR/ffmpeg" && \
    PKG_CONFIG_PATH="$WORKDIR/install/lib/pkgconfig" ./configure \
      --prefix="$WORKDIR/install" \
      --extra-cflags="-I$WORKDIR/install/include" \
      --extra-ldflags="-L$WORKDIR/install/lib" \
      --pkg-config-flags="--static" \
      "${FFMPEG_CONFIGURE_ARGS[@]}" && \
    make -j"$(sysctl -n hw.logicalcpu)" )

  cp "$WORKDIR/ffmpeg/ffmpeg" "$DIR/ffmpeg_${TARGET//-/_}"
  chmod +x "$DIR/ffmpeg_${TARGET//-/_}"
}

build_linux () {
  arch="$1"  # amd64 | arm64
  platform="linux/$arch"
  out="ffmpeg_linux_$arch"

  command -v docker >/dev/null || { echo "docker not found"; exit 1; }

  docker run --rm --platform "$platform" \
    -v "$DIR:/out" -v "$SOURCE_DIR:/sources:ro" \
    ubuntu:22.04 bash -euxc '
      apt-get update
      apt-get install -y --no-install-recommends \
        build-essential pkg-config nasm yasm ca-certificates \
        zlib1g-dev
      cd /tmp
      mkdir ffmpeg x264
      tar -xzf /sources/ffmpeg-'"$FFMPEG_REV"'.tar.gz -C ffmpeg --strip-components=1
      tar -xzf /sources/x264-'"$X264_REV"'.tar.gz -C x264 --strip-components=1
      mkdir -p /tmp/install
      cd /tmp/x264
      ./configure --prefix=/tmp/install --enable-static --disable-cli --enable-pic
      make -j"$(nproc)" && make install
      cd /tmp/ffmpeg
      PKG_CONFIG_PATH=/tmp/install/lib/pkgconfig ./configure \
        --prefix=/tmp/install \
        --extra-cflags="-I/tmp/install/include" \
        --extra-ldflags="-L/tmp/install/lib -static" \
        --pkg-config-flags="--static" \
        '"${FFMPEG_CONFIGURE_ARGS[*]}"'
      make -j"$(nproc)"
      cp /tmp/ffmpeg/ffmpeg /out/'"$out"'
      chmod +x /out/'"$out"'
    '
}

build_windows_amd64 () {
  command -v docker >/dev/null || { echo "docker not found"; exit 1; }
  docker run --rm -v "$DIR:/out" -v "$SOURCE_DIR:/sources:ro" dockcross/windows-static-x64 bash -euxc '
    cd /tmp
    mkdir ffmpeg x264
    tar -xzf /sources/ffmpeg-'"$FFMPEG_REV"'.tar.gz -C ffmpeg --strip-components=1
    tar -xzf /sources/x264-'"$X264_REV"'.tar.gz -C x264 --strip-components=1
    mkdir -p /tmp/install
    cd x264
    ./configure --prefix=/tmp/install --host="$CROSS_TRIPLE" --cross-prefix="$CROSS_TRIPLE-" --enable-static --disable-cli
    make -j"$(nproc)" && make install
    cd /tmp/ffmpeg
    PKG_CONFIG_PATH=/tmp/install/lib/pkgconfig ./configure \
      --prefix=/tmp/install \
      --target-os=mingw32 --arch=x86_64 --enable-cross-compile \
      --cross-prefix="$CROSS_TRIPLE-" \
      --extra-cflags="-I/tmp/install/include" \
      --extra-ldflags="-L/tmp/install/lib -static" \
      --pkg-config-flags="--static" \
      '"${FFMPEG_CONFIGURE_ARGS[*]}"'
    make -j"$(nproc)"
    cp ffmpeg.exe /out/ffmpeg_windows_amd64.exe
  '
}

case "$TARGET" in
  darwin-arm64|darwin-amd64) build_native_darwin ;;
  linux-amd64)   build_linux amd64 ;;
  linux-arm64)   build_linux arm64 ;;
  windows-amd64) build_windows_amd64 ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac
