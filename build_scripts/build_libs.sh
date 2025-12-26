#!/usr/bin/env bash
set -e

# =====================================================
# Build Skia + FreeType + HarfBuzz prebuilt libraries
# =====================================================

# --- Versions (pin exact commits/tags) ---
SKIA_VERSION_TAG="chrome/m143"
FREETYPE_VERSION_TAG="VER-2-14-1"
HARFBUZZ_VERSION_TAG="12.0.0"

# Detect platform
case "$(uname -s)" in
    Linux*)   PLATFORM="linux" ;;
    Darwin*)  PLATFORM="mac" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="win" ;;
esac

# Detect architecture
ARCH_FULLNAME="$(uname -m)"
case "$ARCH_FULLNAME" in
    x86_64)   ARCH="x64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *)        ARCH="x64" ;;
esac

PLATFORM_FULLNAME="${PLATFORM}-$ARCH"

echo "=== Building libraries for ${PLATFORM_FULLNAME} ==="
echo "Using:"
echo "  Skia: ${SKIA_VERSION_TAG}"
echo "  FreeType: ${FREETYPE_VERSION_TAG}"
echo "  HarfBuzz: ${HARFBUZZ_VERSION_TAG}"

mkdir -p deps && cd deps

# --- Build FreeType ---
if [ ! -d "freetype" ]; then
    git clone --branch ${FREETYPE_VERSION_TAG} --depth=1 https://gitlab.freedesktop.org/freetype/freetype.git
fi
cd freetype
cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
cmake --build build --config Release
cd ..

if [[ "$PLATFORM" == "win" ]]; then
    # Convert to Windows absolute paths (C:/... style)
    FREETYPE_INCLUDE=$(cygpath -m "$(pwd)/freetype/include")
    HARFBUZZ_INCLUDE=$(cygpath -m "$(pwd)/harfbuzz/src")
    FREETYPE_LIB=$(cygpath -m "$(pwd)/freetype/build/Release/freetype.lib")
    HARFBUZZ_LIB=$(cygpath -m "$(pwd)/harfbuzz/build/Release/harfbuzz.lib")
else
    FREETYPE_INCLUDE="$(pwd)/freetype/include"
    HARFBUZZ_INCLUDE="$(pwd)/harfbuzz/src"
    FREETYPE_LIB="$(pwd)/freetype/build/libfreetype.a"
    HARFBUZZ_LIB="$(pwd)/harfbuzz/build/libharfbuzz.a"
fi

# --- Build HarfBuzz ---
if [ ! -d "harfbuzz" ]; then
    git clone --branch ${HARFBUZZ_VERSION_TAG} --depth=1 https://github.com/harfbuzz/harfbuzz.git
fi
cd harfbuzz

cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
      -DHB_HAVE_FREETYPE=ON  \
      -DFREETYPE_INCLUDE_DIRS=${FREETYPE_INCLUDE} \
      -DFREETYPE_LIBRARY="${FREETYPE_LIB}"
cmake --build build --config Release
cd ..

# --- Build Skia ---
if [ ! -d "skia" ]; then
    git clone https://github.com/google/skia.git
    cd skia
else
    cd skia
    git fetch origin ${SKIA_VERSION_TAG}
fi
git checkout ${SKIA_VERSION_TAG}
python3 tools/git-sync-deps

if [[ "$PLATFORM" == "win" ]]; then
    EXTRA_CFLAGS="[
        \"-DSK_FREETYPE_STATIC\",
        \"-DSK_BUILD_FOR_WIN\",
        \"-I$FREETYPE_INCLUDE\",
        \"-I$HARFBUZZ_INCLUDE\"
    ]"
else
    EXTRA_CFLAGS="[
        \"-I$FREETYPE_INCLUDE\",
        \"-I$HARFBUZZ_INCLUDE\"
    ]"
fi

SKIA_ARGS="
is_official_build=true
is_component_build=false
skia_use_gl=true
skia_enable_tools=false
skia_use_freetype=true
skia_use_harfbuzz=true
skia_use_zlib=true
skia_use_system_libpng=false
skia_enable_pdf=false
skia_use_system_libjpeg_turbo=false
skia_use_system_libwebp=false
skia_use_system_icu=false
skia_enable_fontmgr_android=false
target_os=\"${PLATFORM}\"
target_cpu=\"${ARCH}\"
extra_cflags=$EXTRA_CFLAGS
extra_ldflags=[\"$FREETYPE_LIB\",\"$HARFBUZZ_LIB\"]"

bin/gn gen out/Release --args="$SKIA_ARGS"
ninja -C out/Release
cd ../..

# --- Package ---
PKG_DIR="artifacts/seeds-ui-libs-${PLATFORM_FULLNAME}"
rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}/lib"
mkdir -p "${PKG_DIR}/include"

# Copy includes
cp -r deps/skia/include "${PKG_DIR}/include/skia"
cp -r deps/freetype/include "${PKG_DIR}/include/freetype2"
cp -r deps/harfbuzz/src "${PKG_DIR}/include/harfbuzz"

# Copy libs
find deps/skia/out/Release -name "libskia.*" -or -name "skia.lib" -exec cp {} "${PKG_DIR}/lib/" \;
find deps/freetype/build -name "libfreetype.*" -or -name "freetype.lib" -exec cp {} "${PKG_DIR}/lib/" \;
find deps/harfbuzz/build -name "libharfbuzz.*" -or -name "harfbuzz.lib" -exec cp {} "${PKG_DIR}/lib/" \;

# Compress
if [[ "$PLATFORM" == "win" ]]; then
    7z a ${PKG_DIR}.zip ${PKG_DIR}/*
else
    tar -czf ${PKG_DIR}.tar.gz -C artifacts seeds-ui-libs-${PLATFORM_FULLNAME}
fi

echo "Build complete: seeds-ui-libs-${PLATFORM_FULLNAME}"

