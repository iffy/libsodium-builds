import lin
import strformat

const ROOT = "https://download.libsodium.org/libsodium/releases/"
const VERSION = "1.0.18"
const TARNAME = &"libsodium-{VERSION}-stable.tar.gz"
const CACHEDIR = "_cache"
const DLDIR = CACHEDIR / "_fetch"
const BUILDROOT = CACHEDIR / "_build"
const OUTDIR = "out"/"v"&VERSION 

var fetch = sequence("fetch")
var build = sequence("build", default = true, includes = @["fetch"])
var local = sequence("local", help = "Build for the current OS only")
var clean = sequence("clean", reverse = true)
var deepclean = sequence("deepclean", reverse = true, includes = @["clean"])

when defined(macosx):
  local.step "macos":
    sh "lin", "fetch", "build/macos"
when defined(linux):
  local.step "linux":
    sh "lin", "fetch", "build/linux"
when defined(windows):
  local.step "windows":
    sh "lin", "fetch", "build/windows"

fetch.step "download":
  createDir DLDIR
  let urls = @[
    # macOS/Linux
    &"{ROOT}libsodium-{VERSION}-stable.tar.gz",
    # Windows mingw
    &"{ROOT}libsodium-{VERSION}-stable-mingw.tar.gz",
    # Windows msvc
    # &"{ROOT}libsodium-{VERSION}-stable-msvc.zip",
  ]
  for url in urls:
    let dst = DLDIR / url.extractFilename()
    if not fileExists(dst):
      echo &"Downloading {url} to {dst}"
      sh "curl", url, "-o", dst
deepclean.step "download":
  removeDir DLDIR

when defined(macosx):
  build.step "macos":
    let dstdir = OUTDIR/"macos"/"x64"
    let builddir = BUILDROOT / "macos"
    if dirExists(dstdir):
      skip "already done"
    else:
      createDir builddir
      defer: removeDir(builddir)
      copyFile(DLDIR/TARNAME, builddir/TARNAME)
      cd builddir:
        sh "tar", "xf", TARNAME
        cd("libsodium-stable"):
          sh "dist-build/osx.sh"
      copyDir(builddir/"libsodium-stable"/"libsodium-osx"/"lib", dstdir)
  clean.step "macos":
    removeDir(OUTDIR/"macos")

when defined(macosx):
  build.step "ios":
    let dstdir = OUTDIR/"ios"
    let builddir = BUILDROOT / "ios"
    if dirExists(dstdir):
      skip "already done"
    else:
      createDir builddir
      defer: removeDir(builddir)
      copyFile(DLDIR/TARNAME, builddir/TARNAME)
      cd builddir:
        sh "tar", "xf", TARNAME
        cd("libsodium-stable"):
          sh "dist-build/ios.sh"
      copyDir(builddir/"libsodium-stable"/"libsodium-ios"/"lib", dstdir)
  clean.step "ios":
    removeDir(OUTDIR/"ios")

build.step "linux":
  let dstdir = OUTDIR/"linux"/"x64"
  let builddir = BUILDROOT / "linux"
  if dirExists(dstdir):
    skip "already done"
  else:
    createDir builddir
    defer: removeDir(builddir)
    copyFile(DLDIR/TARNAME, builddir/TARNAME)
    cd builddir:
      sh "tar", "xf", TARNAME
      cd("libsodium-stable"):
        writeFile("./buildit.sh", """
          set -e
          uname -r
          ./configure
          make && make check
          """)
        defer: removeFile("buildit.sh")
        when defined(linux):
          # build natively
          sh "bash", "buildit.sh"
        else:
          # build in docker
          sh "docker", "run", "--rm", "-v", getCurrentDir() & ":/code", "-w", "/code", "gcc:4", "/bin/bash", "buildit.sh"
    copyDir(builddir/"libsodium-stable"/"src"/"libsodium"/".libs", dstdir/"lib")
    copyDir(builddir/"libsodium-stable"/"src"/"libsodium"/"include", dstdir/"include")
clean.step "linux":
  removeDir(OUTDIR/"linux")

build.step "windows":
  let dst32 = absolutePath(OUTDIR/"win"/"x32")
  let dst64 = absolutePath(OUTDIR/"win"/"x64")
  let builddir = BUILDROOT / "win"
  if not dst32.dirExists or not dst64.dirExists:
    createDir builddir
    defer: removeDir(builddir)
    copyFile(DLDIR/"libsodium-1.0.18-stable-mingw.tar.gz", builddir/"libsodium.tar.gz")
    cd builddir:
      sh "tar", "xf", "libsodium.tar.gz"
      if not dst32.dirExists:
        dst32.parentDir.createDir
        copyDir("libsodium-win32"/"lib", dst32)
      if not dst64.dirExists:
        dst64.parentDir.createDir
        copyDir("libsodium-win64"/"lib", dst64)
  else:
    skip "already done"
clean.step "win":
  removeDir(OUTDIR/"win")

build.step "android":
  let android_steps = [
    # (arch, build script name, build dir name)
    ("arm64-v8a", "android-armv8-a.sh", "armv8-a"),
    ("armeabi-v7a", "android-armv7-a.sh", "armv7-a"),
    ("x86", "android-x86.sh", "i686"),
    ("x86_64", "android-x86_64.sh", "westmere"),
  ]
  for (arch, script, suffix) in android_steps:
    let dst = absolutePath(OUTDIR/"android"/arch)
    let builddir = BUILDROOT / "android"
    if dirExists(dst):
      echo arch, " already done"
    else:
      createDir builddir
      defer: removeDir(builddir)
      copyFile(DLDIR/TARNAME, builddir/TARNAME)
      cd builddir:
        sh "tar", "xf", TARNAME
        cd("libsodium-stable"):
          sh "dist-build"/script
      copyDir(builddir/"libsodium-stable"/"libsodium-android-" & suffix, dst)
clean.step "android":
  removeDir(OUTDIR/"android")

when isMainModule:
  lin.cli()
