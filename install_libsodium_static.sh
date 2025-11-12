#!/bin/bash

VERSION=1.0.18
SRC_URL="https://download.libsodium.org/libsodium/releases/"
PREBUILT_URL="https://github.com/iffy/libsodium-builds/releases/latest"
CACHEDIR="${CACHEDIR:-_cache}"
OUTDIR="${OUTDIR:-libsodium}"

SCRIPTDIR="${CACHEDIR}/_scripts"
BUILDROOT="${CACHEDIR}/_build"

log() {
  echo "$@" >&2
}

ARCH="${ARCH:-}"
if [ -z "$ARCH" ]; then
  log "Auto-detecting ARCH ..."
  case "$(uname -m)" in
    i686|i386|x86) ARCH="x32" ;;
    x86_64) ARCH="x64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) log "Unsupported architecture: $ARCH"; exit 1 ;;
  esac
fi

HOST_OS="$(uname -s)"
case "$HOST_OS" in
  Darwin|macos) HOST_OS="macos" ;;
  Linux|linux) HOST_OS="linux" ;;
  CYGWIN*|MINGW*|windows) HOST_OS="windows" ;;
  *) log "Unsupported OS: $HOST_OS"; exit 1 ;;
esac
TARGET_OS="${TARGET_OS:-$HOST_OS}"

if [ "$TARGET_OS" == "$HOST_OS" ]; then
  OUTNAME="${OUTDIR}/${HOST_OS}-${ARCH}-v${VERSION}"
else
  OUTNAME="${OUTDIR}/${HOST_OS}-${TARGET_OS}-${ARCH}-v${VERSION}"
fi

download_if_not_present() {
  local dst="$1"
  local url="$2"
  if [ -e "$dst" ]; then
    log "Already downloaded $dst"
  else
    mkdir -p "$(dirname "$dst")"
    log "Downloading $dst from $url"
    curl -L -o "$dst" "$url"
    return "$?"
  fi
}

do_fetch() {
  if [ "$TARGET_OS" == "windows" ]; then
    download_if_not_present "${CACHEDIR}/libsodium-${VERSION}-stable-mingw.tar.gz" "${SRC_URL}/libsodium-${VERSION}-stable-mingw.tar.gz"
  else
    download_if_not_present "${CACHEDIR}/libsodium-${VERSION}-stable.tar.gz" "${SRC_URL}/libsodium-${VERSION}-stable.tar.gz"
  fi
  if [ "$TARGET_OS" == "android" ]; then
    download_if_not_present "${CACHEDIR}/buildscripts.tar.gz" "https://github.com/jedisct1/libsodium/tarball/7621b135e2ec08cb96d1b5d5d6a213d9713ac513"
  fi
}

do_build() {
  if [ "$TARGET_OS" == "android" ] || ! [ -f "${OUTNAME}/libsodium.a" ]; then
    do_fetch
    mkdir -p "$OUTNAME"    
    if [ "$TARGET_OS" == "macos" ]; then
      # macos
      (cd "$CACHEDIR" && tar xf "libsodium-${VERSION}-stable.tar.gz")
      if ! [ -e "${CACHEDIR}"/libsodium-stable/libsodium-osx ]; then
        log "Building..."
        (cd "${CACHEDIR}/libsodium-stable" && dist-build/osx.sh)
      else
        log "Already built"
      fi
      cp -R "${CACHEDIR}"/libsodium-stable/libsodium-osx/lib/* "${OUTNAME}/"
    elif [ "$TARGET_OS" == "ios" ]; then
      # ios
      (cd "$CACHEDIR" && tar xf "libsodium-${VERSION}-stable.tar.gz")
      if ! [ -e "${CACHEDIR}"/libsodium-stable/libsodium-ios ]; then
        log "Building..."
        (cd "${CACHEDIR}/libsodium-stable" && dist-build/apple-xcframework.sh)
      else
        log "Already built"
      fi
      OUTNAME_SILICON="${OUTDIR}/${HOST_OS}-${TARGET_OS}-arm64-v${VERSION}"
      mkdir -p "$OUTNAME_SILICON"
      cp -R "${CACHEDIR}"/libsodium-stable/libsodium-apple/tmp/macos-arm64/lib/* "${OUTNAME_SILICON}/"
      cp -R "${CACHEDIR}"/libsodium-stable/libsodium-apple/tmp/macos-arm64/include "${OUTNAME_SILICON}/include"
      
      OUTNAME_INTEL="${OUTDIR}/${HOST_OS}-${TARGET_OS}-x64-v${VERSION}"
      mkdir -p "$OUTNAME_INTEL"
      cp -R "${CACHEDIR}"/libsodium-stable/libsodium-apple/tmp/macos-x86_64/lib/* "${OUTNAME_INTEL}/"
      cp -R "${CACHEDIR}"/libsodium-stable/libsodium-apple/tmp/macos-x86_64/include "${OUTNAME_INTEL}/include"
    elif [ "$TARGET_OS" == "windows" ]; then
      # windows
      (cd "$CACHEDIR" && tar xf "libsodium-${VERSION}-stable-mingw.tar.gz")
      local seg="libsodium-win64"
      if [ "$ARCH" == "x32" ]; then
        seg="libsodium-win32"
      fi
      cp -R "${CACHEDIR}/${seg}/lib/"* "${OUTNAME}/"
    elif [ "$TARGET_OS" == "android" ]; then
      # android
      set -x
      if [ ! -d "$SCRIPTDIR" ]; then
        mkdir -p "$SCRIPTDIR"
        local scripttar="buildscripts.tar.gz"
        if [ -f "${CACHEDIR}/${scripttar}" ]; then
          cp "${CACHEDIR}/${scripttar}" "${SCRIPTDIR}/${scripttar}"
          (cd "$SCRIPTDIR" && tar -x --strip-components=1 -f "${scripttar}")
          rm "${SCRIPTDIR}/${scripttar}"
        else
          log "Buildscripts not found"
          exit 1
        fi
      fi

      local android_steps=(
        #"arm64-v8a android-armv8-a.sh armv8-a+crypto"
        # "armeabi-v7a android-armv7-a.sh armv7-a"
        "x86 android-x86.sh i686"
        "x86_64 android-x86_64.sh westmere"
      )

      mkdir -p "${OUTDIR}/android"
      local builddir="${BUILDROOT}/android"

      for step in "${android_steps[@]}"; do
        read -r arch script suffix <<< "$step"
        mkdir -p "$builddir"
        log "Building ${arch} using ${script} in build dir ${suffix} ..."

        local dst="${OUTDIR}/${HOST_OS}-${TARGET_OS}-${arch}-v${VERSION}"
        if [ -d "$dst" ]; then
          log "${arch} already done"
          continue
        fi

        local tarname="libsodium-${VERSION}-stable.tar.gz"
        cp "${CACHEDIR}/${tarname}" "${builddir}/${tarname}"
        (cd "$builddir" && tar xf "${tarname}")
        cp -R "${SCRIPTDIR}/dist-build" "${builddir}/libsodium-stable/"
        (cd "${builddir}/libsodium-stable" && {
          log "Using latest build scripts"
          ls -al dist-build
          "./dist-build/${script}"
        })
        local interdir="${builddir}/libsodium-stable/libsodium-android-${suffix}"
        ls -al "${builddir}/libsodium-stable/" >&2
        if [ ! -d "$interdir" ]; then
          ls -al "$(dirname "${interdir}")" 2>/dev/null || true
          log "Expected ${interdir} not found."
          exit 1
        fi
        mkdir -p "$dst"
        cp -R "${interdir}"/* "$dst"/
        rm -r "$builddir"
      done
      rm -rf "$builddir"
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
  log "Getting libsodium, one way or another"
    
  # 1. Check if there's a prebuilt binary
  # TODO
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

log "ARCH=$ARCH"
log "HOST_OS=$HOST_OS"
log "TARGET_OS=$TARGET_OS"
log "CACHEDIR=$CACHEDIR"
log "OUT=$OUTNAME"
log "CMD=$CMD"

(do_${CMD})
