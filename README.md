# ct-storytools-vendored-libs

Prebuilt native C/C++ libraries that the main [StoryTools](https://github.com/christiansjostedt/storytools) repo links against from Rust.

Same pattern as `ct-storytools-ai-models`: this repo carries the build
recipes + CI; the actual binaries live as **GitHub Release attachments**
(not in git history). StoryTools' installer pulls a version-pinned
tarball at first run.

The goal is to keep `python install_storytools.py` a **single-file
install** on Linux / macOS / Windows — no MSVC, no Xcode, no system
package manager required on the user's machine.

## Libraries shipped

| Library | Version | Used by | Release tag |
|---|---|---|---|
| OpenColorIO | 2.5.1 | StoryTools render daemon (via `ocio-sys` cxx::bridge) | `ocio-v2.5.1-r1` |

## How it works

1. CI builds OCIO from source on a matrix of Linux/macOS/Windows runners
   (`.github/workflows/build-ocio.yml`) with all external deps
   static-linked into the resulting library
   (`-DOCIO_INSTALL_EXT_PACKAGES=ALL`).
2. Each runner packages a per-platform tarball with the layout below
   and uploads it as a workflow artifact.
3. Push a tag like `ocio-v2.5.1-r1` to also publish the artifacts as
   release assets. The StoryTools installer reads `OCIO_RELEASE_TAG`
   from `install_storytools.py` and downloads the matching asset
   (`ocio-<tag>-<platform>.tar.gz`).

## Tarball layout

Same shape on every platform — the installer extracts directly into
`<storytools-repo>/src-tauri/vendor/ocio/`:

```
MANIFEST.json
include/
  OpenColorIO/
    OpenColorABI.h
    OpenColorIO.h
    ...
lib/
  libOpenColorIO.so*         (Linux)
  libOpenColorIO*.dylib      (macOS, universal x86_64 + arm64)
  OpenColorIO.lib            (Windows — import library)
bin/
  OpenColorIO.dll            (Windows only)
```

`MANIFEST.json`:

```json
{
  "release_tag": "ocio-v2.5.1-r1",
  "ocio_version": "2.5.1",
  "platform": "linux-x86_64",
  "built_at": "2026-05-18T12:34:56Z",
  "upstream": "https://github.com/AcademySoftwareFoundation/OpenColorIO/releases/tag/v2.5.1"
}
```

## Cutting a new release

1. Bump `OCIO_VERSION` in `.github/workflows/build-ocio.yml` (and the
   per-platform scripts default).
2. Push a new tag matching the `ocio-vX.Y.Z-rN` pattern. The `r` is
   the rebuild counter — bump it without changing the OCIO version if
   you only want to re-cut the binaries (e.g. for build-script fixes).
3. Watch the workflow run to completion. The release page will be
   populated automatically.
4. Bump `OCIO_RELEASE_TAG` in StoryTools' `install_storytools.py`
   to point at the new tag.

## Build matrix

| Tarball | Runner | Compiler | Build script |
|---|---|---|---|
| `linux-x86_64` | `ubuntu-22.04` | gcc | `scripts/build_linux.sh` |
| `macos-universal` | `macos-13` | clang (x86_64 + arm64) | `scripts/build_macos.sh` |
| `windows-x86_64` | `windows-2022` | MSVC 2022 | `scripts/build_windows.ps1` |

## License

OpenColorIO is BSD-3-Clause. Its bundled deps (Imath, expat, yaml-cpp,
pystring, minizip-ng) carry their own permissive licenses. The
LICENSES are baked into the upstream source we build from.
