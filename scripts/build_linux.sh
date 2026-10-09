#!/usr/bin/env bash
# Builds OpenColorIO from source on Linux and packages a tarball with
# the layout StoryTools' `ocio-sys` build.rs + install_storytools.py
# expect (MANIFEST.json + include/OpenColorIO/*.h + lib/libOpenColorIO.so*).
#
# CI runs this inside the `quay.io/pypa/manylinux_2_28_x86_64` container
# (AlmaLinux 8, glibc 2.28, gcc-toolset) so the library loads on
# Rocky / RHEL 8 and every newer distro. r2 was built on the
# ubuntu-22.04 host and needed glibc 2.33 — it would not load on
# Rocky 8. MAX_GLIBC makes that a build failure instead of a user's.
#
# OCIO's bundled-deps mode (-DOCIO_INSTALL_EXT_PACKAGES=ALL) static-links
# Imath / expat / yaml-cpp / pystring / minizip-ng into the .so so the
# shipped tarball has zero external runtime deps beyond glibc/libstdc++.

set -euo pipefail

OCIO_VERSION="${OCIO_VERSION:-2.5.1}"
OCIO_REPO="${OCIO_REPO:-AcademySoftwareFoundation/OpenColorIO}"
PLATFORM_TAG="${PLATFORM_TAG:-linux-x86_64}"
RELEASE_TAG="${RELEASE_TAG:-ocio-v${OCIO_VERSION}-dev}"

WORK="$(pwd)/_build"
SRC="$WORK/src"
BUILD="$WORK/build"
STAGE="$WORK/stage"
DIST="$(pwd)/dist"

rm -rf "$WORK" "$DIST"
mkdir -p "$WORK" "$DIST"

MAX_GLIBC="${MAX_GLIBC:-2.28}"

echo "==> Installing build tooling"
if command -v apt-get >/dev/null 2>&1; then
    SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo"
    $SUDO apt-get update -qq
    $SUDO apt-get install -qq -y build-essential cmake ninja-build git pkg-config binutils
else
    # manylinux / RHEL-family: compilers come from gcc-toolset; cmake +
    # ninja from pip if the image doesn't already carry them.
    command -v git >/dev/null 2>&1 || dnf install -y git
    command -v objdump >/dev/null 2>&1 || dnf install -y binutils
    if ! command -v cmake >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
        PY="$(ls /opt/python/cp311-*/bin/python 2>/dev/null | head -1)"
        "${PY:-python3}" -m pip install --quiet cmake ninja
        export PATH="$(dirname "${PY:-$(command -v python3)}"):$PATH"
    fi
fi
cmake --version | head -1
gcc --version | head -1

echo "==> Cloning OCIO $OCIO_VERSION"
git clone --depth 1 --branch "v$OCIO_VERSION" \
    "https://github.com/$OCIO_REPO.git" "$SRC"

echo "==> Configuring CMake"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$STAGE" \
    -DBUILD_SHARED_LIBS=ON \
    -DOCIO_BUILD_APPS=OFF \
    -DOCIO_BUILD_TESTS=OFF \
    -DOCIO_BUILD_GPU_TESTS=OFF \
    -DOCIO_BUILD_DOCS=OFF \
    -DOCIO_BUILD_PYTHON=OFF \
    -DOCIO_BUILD_JAVA=OFF \
    -DOCIO_BUILD_OPENFX=OFF \
    -DOCIO_INSTALL_EXT_PACKAGES=ALL \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON

echo "==> Building OCIO"
cmake --build "$BUILD" -j "$(nproc)"

echo "==> Installing into staging dir"
cmake --install "$BUILD"

echo "==> Assembling tarball payload"
PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD/include" "$PAYLOAD/lib"

cp -a "$STAGE/include/OpenColorIO" "$PAYLOAD/include/"
# Ship the .so + its versioned symlinks; skip cmake config files and
# pkgconfig — Rust build.rs links directly via -lOpenColorIO.
for f in "$STAGE"/lib*/libOpenColorIO*; do
    [ -e "$f" ] || continue
    cp -a "$f" "$PAYLOAD/lib/"
done

# Oldest glibc / libstdc++ the library runs on — recorded in the
# manifest and enforced against MAX_GLIBC.
SO="$(ls "$PAYLOAD"/lib/libOpenColorIO.so.*.*.* | head -1)"
MIN_GLIBC="$(objdump -T "$SO" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -1)"
MIN_GLIBCXX="$(objdump -T "$SO" | grep -o 'GLIBCXX_[0-9.]*' | sed 's/GLIBCXX_//' | sort -uV | tail -1)"
echo "==> $SO needs glibc >= $MIN_GLIBC, libstdc++ GLIBCXX >= $MIN_GLIBCXX"
if [ "$(printf '%s\n%s\n' "$MIN_GLIBC" "$MAX_GLIBC" | sort -V | tail -1)" != "$MAX_GLIBC" ]; then
    echo "ERROR: needs glibc $MIN_GLIBC, newer than the supported $MAX_GLIBC" >&2
    exit 1
fi

# Write the MANIFEST.json the installer uses to verify the bundle.
cat > "$PAYLOAD/MANIFEST.json" <<JSON
{
  "release_tag": "$RELEASE_TAG",
  "ocio_version": "$OCIO_VERSION",
  "platform": "$PLATFORM_TAG",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "built_by": "$(. /etc/os-release && echo "$PRETTY_NAME") / $(gcc -dumpfullversion)",
  "min_glibc": "$MIN_GLIBC",
  "min_glibcxx": "$MIN_GLIBCXX",
  "upstream": "https://github.com/$OCIO_REPO/releases/tag/v$OCIO_VERSION"
}
JSON

OUT="$DIST/$RELEASE_TAG-$PLATFORM_TAG.tar.gz"
echo "==> Packaging $OUT"
tar -C "$PAYLOAD" -czf "$OUT" .

ls -la "$DIST"
sha256sum "$OUT"
