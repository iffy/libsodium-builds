#!/bin/bash

VERSION=1.0.18
SRC_URL="https://download.libsodium.org/libsodium/releases/"
PREBUILT_URL="https://github.com/iffy/libsodium-builds/releases/latest"
CACHEDIR="${CACHEDIR:-_cache}"
OUTDIR="${OUTDIR:-libsodium}"

ARCH="${ARCH:-}"
if [ -z "$ARCH" ]; then
  echo >&2 "Auto-detecting ARCH ..."
  case "$(uname -m)" in
    i686|i386|x86) ARCH="x32" ;;
    x86_64) ARCH="x64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
  esac
fi

OS="${OS:-$(uname -s)}"
case "$OS" in
  Darwin|macos) OS="macos" ;;
  Linux|linux) OS="linux" ;;
  CYGWIN*|MINGW*|windows) OS="windows" ;;
  ios) OS="ios" ;;
  android) OS="android" ;;
  *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

OUTNAME="${OUTDIR}/${OS}-${ARCH}-v${VERSION}"

download_if_not_present() {
  local dst="$1"
  local url="$2"
  if [ -e "$dst" ]; then
    echo "Already downloaded $dst"
  else
    mkdir -p "$(dirname "$dst")"
    echo "Downloading $dst from $url"
    curl -L -o "$dst" "$url"
    return "$?"
  fi
}

do_fetch() {
  if [ "$OS" == "windows" ]; then
    download_if_not_present "${CACHEDIR}/libsodium-${VERSION}-stable-mingw.tar.gz" "${SRC_URL}/libsodium-${VERSION}-stable-mingw.tar.gz"
  else
    download_if_not_present "${CACHEDIR}/libsodium-${VERSION}-stable.tar.gz" "${SRC_URL}/libsodium-${VERSION}-stable.tar.gz"
  fi
  if [ "$OS" == "android" ]; then
    download_if_not_present "${CACHEDIR}/scripts/buildscripts.tar.gz" "https://github.com/jedisct1/libsodium/tarball/7621b135e2ec08cb96d1b5d5d6a213d9713ac513"
  fi
}

do_build() {
  if [ -f "${OUTNAME}/libsodium.a" ]; then
    echo "${OUTNAME}/libsodium.a already exists"
  else
    do_fetch
    mkdir -p "$OUTNAME"    
    if [ "$OS" == "macos" ]; then
      # macos
      (cd "$CACHEDIR" && tar xf "libsodium-${VERSION}-stable.tar.gz")
      if ! [ -e "${CACHEDIR}"/libsodium-stable/libsodium-osx ]; then
        echo "Building..."
        (cd "${CACHEDIR}/libsodium-stable" && dist-build/osx.sh)
      else
        echo "Already built"
      fi
      cp -R "${CACHEDIR}"/libsodium-stable/libsodium-osx/lib/* "${OUTNAME}/"
    elif [ "$OS" == "ios" ]; then
      # ios
      (cd "$CACHEDIR" && tar xf "libsodium-${VERSION}-stable.tar.gz")
      if ! [ -e "${CACHEDIR}"/libsodium-stable/libsodium-ios ]; then
        echo "Building..."
        (cd "${CACHEDIR}/libsodium-stable" && dist-build/ios.sh)
      else
        echo "Already built"
      fi
      cp -R "${CACHEDIR}"/libsodium-stable/libsodium-ios/lib/* "${OUTNAME}/"
    elif [ "$OS" == "windows" ]; then
      # windows
      (cd "$CACHEDIR" && tar xf "libsodium-${VERSION}-stable-mingw.tar.gz")
      local seg="libsodium-win64"
      if [ "$ARCH" == "x32" ]; then
        seg="libsodium-win32"
      fi
      cp -R "${CACHEDIR}/${seg}/lib/"* "${OUTNAME}/"
    else
      # linux
      (cd "$CACHEDIR" && tar xf "libsodium-${VERSION}-stable.tar.gz")
      (cd "${CACHEDIR}/libsodium-stable" && \
        ./configure --disable-debug && \
        make && \
        make check
      )
      cp -R "${CACHEDIR}"/libsodium-stable/src/libsodium/.libs/* "${OUTNAME}/"
      cp -R "${CACHEDIR}"/libsodium-stable/src/libsodium/include "${OUTNAME}/include"
    fi
    
  fi
}

do_nimconfig() {
  cat <<EOF
import os
const ROOT = currentSourcePath.parentDir()
const archsegment = block:
  when hostCPU == "i386": "x32"
  elif hostCPU == "arm64": "arm64"
  else: "x64"
switch("dynlibOverride", "libsodium")
when defined(macosx):
  switch("passL", ROOT/"${OUTDIR}"/"macos-" & archsegment & "-v${VERSION}"/"libsodium.a")
elif defined(linux):
  switch("cincludes", ROOT/"${OUTDIR}"/"linux-" & archsegment & "-v${VERSION}"/"include")
  switch("clibdir", ROOT/"${OUTDIR}"/"linux-" & archsegment & "-v${VERSION}")
  switch("passL", "-lsodium")
elif defined(windows):
  switch("passL", ROOT/"${OUTDIR}"/"windows-" & archsegment & "-v${VERSION}"/"libsodium.a")
EOF
}

do_get() {
  echo >&2 "Getting libsodium, one way or another"
    
  # 1. Check if there's a prebuilt binary
  # 2. Build it from source
  do_build

  do_nimconfig > libsodium.nims
  cat <<EOF
====================================================================
OK
====================================================================

To link against this, put the following add this to your config.nims

include "libsodium.nims"
EOF
}

CMD="${1:-get}"

echo >&2 "ARCH=$ARCH"
echo >&2 "OS=$OS"
echo >&2 "CACHEDIR=$CACHEDIR"
echo >&2 "OUT=$OUTNAME"
echo >&2 "CMD=$CMD"

(do_${CMD})
