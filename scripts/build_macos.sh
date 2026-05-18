#!/usr/bin/env bash
# Builds OpenColorIO as a universal binary (x86_64 + arm64) on macOS and
# packages a tarball. Cross-compiles arm64 from the x86_64 runner via
# CMAKE_OSX_ARCHITECTURES — OCIO and its bundled deps respect that and
# emit a single fat .dylib.

set -euo pipefail

OCIO_VERSION="${OCIO_VERSION:-2.5.1}"
OCIO_REPO="${OCIO_REPO:-AcademySoftwareFoundation/OpenColorIO}"
PLATFORM_TAG="${PLATFORM_TAG:-macos-universal}"
RELEASE_TAG="${RELEASE_TAG:-ocio-v${OCIO_VERSION}-dev}"

WORK="$(pwd)/_build"
SRC="$WORK/src"
BUILD="$WORK/build"
STAGE="$WORK/stage"
DIST="$(pwd)/dist"

rm -rf "$WORK" "$DIST"
mkdir -p "$WORK" "$DIST"

echo "==> Installing build tooling"
brew install --quiet cmake ninja

echo "==> Cloning OCIO $OCIO_VERSION"
git clone --depth 1 --branch "v$OCIO_VERSION" \
    "https://github.com/$OCIO_REPO.git" "$SRC"

echo "==> Configuring CMake (universal: x86_64 + arm64)"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$STAGE" \
    -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="11.0" \
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
cmake --build "$BUILD" -j "$(sysctl -n hw.ncpu)"

echo "==> Installing into staging dir"
cmake --install "$BUILD"

echo "==> Verifying universal binary"
DYLIB="$(ls "$STAGE"/lib/libOpenColorIO*.dylib | head -1)"
file "$DYLIB"
lipo -info "$DYLIB"

echo "==> Assembling tarball payload"
PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD/include" "$PAYLOAD/lib"

cp -a "$STAGE/include/OpenColorIO" "$PAYLOAD/include/"
for f in "$STAGE"/lib/libOpenColorIO*; do
    [ -e "$f" ] || continue
    cp -a "$f" "$PAYLOAD/lib/"
done

cat > "$PAYLOAD/MANIFEST.json" <<JSON
{
  "release_tag": "$RELEASE_TAG",
  "ocio_version": "$OCIO_VERSION",
  "platform": "$PLATFORM_TAG",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "upstream": "https://github.com/$OCIO_REPO/releases/tag/v$OCIO_VERSION"
}
JSON

OUT="$DIST/ocio-$RELEASE_TAG-$PLATFORM_TAG.tar.gz"
echo "==> Packaging $OUT"
tar -C "$PAYLOAD" -czf "$OUT" .

ls -la "$DIST"
shasum -a 256 "$OUT"
