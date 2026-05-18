# Builds OpenColorIO on Windows with MSVC and packages a tarball.
# Ships OpenColorIO.lib (import library) + OpenColorIO.dll. Bundled
# external deps are static-linked into the DLL.

$ErrorActionPreference = "Stop"

$OcioVersion = $env:OCIO_VERSION
if (-not $OcioVersion) { $OcioVersion = "2.5.1" }

$OcioRepo = $env:OCIO_REPO
if (-not $OcioRepo) { $OcioRepo = "AcademySoftwareFoundation/OpenColorIO" }

$PlatformTag = $env:PLATFORM_TAG
if (-not $PlatformTag) { $PlatformTag = "windows-x86_64" }

$ReleaseTag = $env:RELEASE_TAG
if (-not $ReleaseTag) { $ReleaseTag = "ocio-v${OcioVersion}-dev" }

$Work = Join-Path $PWD "_build"
$Src = Join-Path $Work "src"
$Build = Join-Path $Work "build"
$Stage = Join-Path $Work "stage"
$Dist = Join-Path $PWD "dist"

if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
if (Test-Path $Dist) { Remove-Item -Recurse -Force $Dist }
New-Item -ItemType Directory -Path $Work, $Dist | Out-Null

Write-Host "==> Cloning OCIO $OcioVersion"
git clone --depth 1 --branch "v$OcioVersion" `
    "https://github.com/$OcioRepo.git" $Src

Write-Host "==> Configuring CMake (Visual Studio 17 2022, x64)"
cmake -S $Src -B $Build `
    -G "Visual Studio 17 2022" -A x64 `
    "-DCMAKE_INSTALL_PREFIX=$Stage" `
    -DBUILD_SHARED_LIBS=ON `
    -DOCIO_BUILD_APPS=OFF `
    -DOCIO_BUILD_TESTS=OFF `
    -DOCIO_BUILD_GPU_TESTS=OFF `
    -DOCIO_BUILD_DOCS=OFF `
    -DOCIO_BUILD_PYTHON=OFF `
    -DOCIO_BUILD_JAVA=OFF `
    -DOCIO_BUILD_OPENFX=OFF `
    -DOCIO_INSTALL_EXT_PACKAGES=ALL

Write-Host "==> Building OCIO (Release)"
cmake --build $Build --config Release -j

Write-Host "==> Installing into staging dir"
cmake --install $Build --config Release

Write-Host "==> Assembling tarball payload"
$Payload = Join-Path $Work "payload"
New-Item -ItemType Directory -Path "$Payload\include", "$Payload\lib", "$Payload\bin" | Out-Null

Copy-Item -Recurse "$Stage\include\OpenColorIO" "$Payload\include\"
# Import library
Get-ChildItem "$Stage\lib\OpenColorIO*.lib" | Copy-Item -Destination "$Payload\lib\"
# Runtime DLL
Get-ChildItem "$Stage\bin\OpenColorIO*.dll" | Copy-Item -Destination "$Payload\bin\"

$BuiltAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ" -AsUTC)
@"
{
  "release_tag": "$ReleaseTag",
  "ocio_version": "$OcioVersion",
  "platform": "$PlatformTag",
  "built_at": "$BuiltAt",
  "upstream": "https://github.com/$OcioRepo/releases/tag/v$OcioVersion"
}
"@ | Out-File -Encoding ASCII -FilePath "$Payload\MANIFEST.json"

$Out = Join-Path $Dist "$ReleaseTag-$PlatformTag.tar.gz"
Write-Host "==> Packaging $Out"
# Windows 10+ ships bsdtar as `tar` — emits the same .tar.gz format the
# installer's tarfile.open(...) reads on the other end.
tar -C $Payload -czf $Out .

Get-ChildItem $Dist
(Get-FileHash -Algorithm SHA256 $Out).Hash
