#!/usr/bin/env bash
# Builds OpenColorIO from source on Ubuntu 22.04 and packages a tarball
# with the layout StoryTools' `ocio-sys` build.rs + install_storytools.py
# expect (MANIFEST.json + include/OpenColorIO/*.h + lib/libOpenColorIO.so*).
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

echo "==> Installing build tooling"
sudo apt-get update -qq
sudo apt-get install -qq -y \
    build-essential \
    cmake \
    ninja-build \
    git \
    pkg-config

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

# Write the MANIFEST.json the installer uses to verify the bundle.
SHA_TARBALL=""  # filled in after we tar it up
cat > "$PAYLOAD/MANIFEST.json" <<JSON
{
  "release_tag": "$RELEASE_TAG",
  "ocio_version": "$OCIO_VERSION",
  "platform": "$PLATFORM_TAG",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "upstream": "https://github.com/$OCIO_REPO/releases/tag/v$OCIO_VERSION"
}
JSON

OUT="$DIST/$RELEASE_TAG-$PLATFORM_TAG.tar.gz"
echo "==> Packaging $OUT"
tar -C "$PAYLOAD" -czf "$OUT" .

ls -la "$DIST"
sha256sum "$OUT"
