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
    Linux*)   PLATFORM="linux-x64";;
    Darwin*)
        ARCH=$(uname -m)
        if [ "$ARCH" = "arm64" ]; then
            PLATFORM="macos-arm64"
        else
            PLATFORM="macos-x64"
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows-x64";;
    *) echo "Unsupported OS"; exit 1;;
esac

echo "=== Building libraries for ${PLATFORM} ==="
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

# --- Build HarfBuzz ---
if [ ! -d "harfbuzz" ]; then
    git clone --branch ${HARFBUZZ_VERSION_TAG} --depth=1 https://github.com/harfbuzz/harfbuzz.git
fi
cd harfbuzz

# Resolve FreeType library path (platform-dependent)
if [[ "$PLATFORM" == windows-* ]]; then
    FREETYPE_LIB_PATH="$(realpath ../freetype/build/Release/freetype.lib)"
else
    FREETYPE_LIB_PATH="$(realpath ../freetype/build/libfreetype.a)"
fi

cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
      -DHB_HAVE_FREETYPE=ON  \
      -DFREETYPE_INCLUDE_DIRS=../freetype/include \
      -DFREETYPE_LIBRARY="${FREETYPE_LIB_PATH}"
cmake --build build --config Release
cd ..

# --- Build Skia ---
if [ ! -d "skia" ]; then
    git clone https://github.com/google/skia.git
    cd skia
    git checkout ${SKIA_VERSION_TAG}
    python3 tools/git-sync-deps
else
    cd skia
    git fetch origin ${SKIA_VERSION_TAG}
    git checkout ${SKIA_VERSION_TAG}
    python3 tools/git-sync-deps
fi

SKIA_ARGS="
is_official_build=true
is_component_build=false
skia_use_gl=true
skia_enable_tools=false
skia_use_freetype=true
skia_use_harfbuzz=true
extra_cflags=[\"-I$(pwd)/../freetype/include\",\"-I$(pwd)/../harfbuzz/src\"]
extra_ldflags=[\"-L$(pwd)/../freetype/build\",\"-L$(pwd)/../harfbuzz/build\"]"

bin/gn gen out/Release --args="$SKIA_ARGS"
ninja -C out/Release
cd ../..

# --- Package ---
PKG_DIR="artifacts/seeds-ui-libs-${PLATFORM}"
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
if [[ "$PLATFORM" == windows-* ]]; then
    7z a seeds-ui-libs-${PLATFORM}.zip ${PKG_DIR}/*
else
    tar -czf seeds-ui-libs-${PLATFORM}.tar.gz -C artifacts seeds-ui-libs-${PLATFORM}
fi

echo "Build complete: seeds-ui-libs-${PLATFORM}"

