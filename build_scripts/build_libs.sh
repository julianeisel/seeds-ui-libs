#!/usr/bin/env bash
set -e

# ======================================================
# Fully Static Skia, Freetype & HarfBuzz Toolchain Build
# ======================================================

# ---------- Versions ----------
SKIA_VERSION_TAG="chrome/m146"
EXPAT_VERSION_TAG="R_2_7_4"
FREETYPE_VERSION_TAG="VER-2-14-2"
BROTLI_VERSION_TAG="v1.2.0"
# Looks like bzip isn't making releases anymore.
# BZIP_VERSION_TAG="bzip2-1.0.8"
HARFBUZZ_VERSION_TAG="12.3.2"
ZLIB_VERSION_TAG="v1.3.2"
LIBPNG_VERSION_TAG="v1.6.55"

# ---------- Platform Detection ----------
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

PLATFORM_FULLNAME="${PLATFORM}-${ARCH}"

echo "=== Building libraries for ${PLATFORM_FULLNAME} ==="
echo "Using:"
echo "  zlib: ${ZLIB_VERSION_TAG}"
echo "  libpng: ${LIBPNG_VERSION_TAG}"
echo "  Brotli: ${BROTLI_VERSION_TAG}"
echo "  FreeType: ${FREETYPE_VERSION_TAG}"
echo "  HarfBuzz: ${HARFBUZZ_VERSION_TAG}"
echo "  Expat: ${EXPAT_VERSION_TAG}"
echo "  Skia: ${SKIA_VERSION_TAG}"

mkdir -p deps && cd deps
if [[ "$PLATFORM" == "win" ]]; then
  INSTALL_PREFIX=$(cygpath -m "$(pwd)/install")
else
  INSTALL_PREFIX=$(pwd)/install
fi
mkdir -p "$INSTALL_PREFIX"

build_and_install () {
  if [[ "$PLATFORM" == "win" ]]; then
    cmake -B build \
      -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
      -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_POLICY_DEFAULT_CMP0091=NEW \
      -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded \
      "$@"
    cmake --build build --config Release --parallel
    cmake --install build --config Release
  else
    cmake -B build \
      -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      "$@"
    cmake --build build --parallel
    cmake --install build
  fi
}

# =====================================================
# zlib
# =====================================================
echo ""
echo "- Building zlib..."
if [ ! -d zlib ]; then
  git clone --branch ${ZLIB_VERSION_TAG} --depth=1 https://github.com/madler/zlib.git
fi
cd zlib
build_and_install
echo "- Finished building zlib"
cd ..

# =====================================================
# libpng
# =====================================================
echo ""
echo "- Building libpng..."
if [ ! -d libpng ]; then
  git clone --branch ${LIBPNG_VERSION_TAG} --depth=1 https://github.com/glennrp/libpng.git
fi
cd libpng
build_and_install \
  -DCMAKE_PREFIX_PATH="$INSTALL_PREFIX" \
  -DPNG_TOOLS=OFF\
  -DPNG_TESTS=OFF \
  -DPNG_EXECUTABLES=OFF \
  -DPNG_SHARED=OFF
echo "- Finished building libpng"
cd ..

# =====================================================
# bzip2
# =====================================================
echo ""
echo "- Building Bzip2..."
if [ ! -d bzip2 ]; then
  git clone --depth=1 https://gitlab.com/bzip2/bzip2.git
fi
cd bzip2
build_and_install \
  -DENABLE_LIB_ONLY=ON \
  -DENABLE_SHARED_LIB=OFF \
  -DENABLE_STATIC_LIB=ON
echo "- Finished building Bzip2"
cd ..

# =====================================================
# Brotli
# =====================================================
echo ""
echo "- Building Brotli..."
if [ ! -d brotli ]; then
  git clone --branch ${BROTLI_VERSION_TAG} --depth=1 https://github.com/google/brotli.git
fi
cd brotli
build_and_install -DBROTLI_DISABLE_TESTS=ON
echo "- Finished building Brotli"
cd ..

# =====================================================
# FreeType
# =====================================================
echo ""
echo "- Building FreeType..."
if [ ! -d freetype ]; then
  git clone --branch ${FREETYPE_VERSION_TAG} --depth=1 https://gitlab.freedesktop.org/freetype/freetype.git
fi
cd freetype

build_and_install \
  -DCMAKE_PREFIX_PATH="$INSTALL_PREFIX" \
  -DFT_REQUIRE_ZLIB=TRUE \
  -DFT_REQUIRE_PNG=TRUE \
  -DFT_REQUIRE_BZIP2=TRUE \
  -DFT_REQUIRE_BROTLI=TRUE
echo "- Finished building FreeType"
cd ..

# =====================================================
# HarfBuzz
# =====================================================
echo ""
echo "- Building HarfBuzz..."
if [ ! -d harfbuzz ]; then
  git clone --branch ${HARFBUZZ_VERSION_TAG} --depth=1 https://github.com/harfbuzz/harfbuzz.git
fi
cd harfbuzz
build_and_install \
  -DHB_HAVE_FREETYPE=ON
echo "- Finished building HarfBuzz"
cd ..

# =====================================================
# Expat
# =====================================================
echo ""
echo "- Building Expat..."
if [ ! -d libexpat ]; then
  git clone --branch ${EXPAT_VERSION_TAG} --depth=1 https://github.com/libexpat/libexpat.git
fi
cd libexpat/expat
build_and_install \
  -DEXPAT_MSVC_STATIC_CRT=ON \
  -DEXPAT_SHARED_LIBS=OFF \
  -DEXPAT_BUILD_TESTS=OFF \
  -DEXPAT_BUILD_TOOLS=OFF \
  -DEXPAT_BUILD_EXAMPLES=OFF
echo "- Finished building Expat"
cd ../..

# =====================================================
# Skia
# =====================================================
echo ""
echo "- Building Skia..."
if [ ! -d skia ]; then
  git clone https://github.com/google/skia.git
fi
cd skia
git checkout ${SKIA_VERSION_TAG}
python3 tools/git-sync-deps

if [[ "$PLATFORM" == "win" ]]; then
  # `SK_FREETYPE_MINIMUM_RUNTIME_VERSION=0` is a workaround for a build error on Windows. Without
  # it Skia tries to include the dlfcn.h Unix header.
  SKIA_EXTRA_CFLAGS="[
    \"-I$INSTALL_PREFIX/include\",
    \"-I$INSTALL_PREFIX/include/freetype2\",
    \"-I$INSTALL_PREFIX/include/harfbuzz\",
    \"-DSK_BUILD_FOR_WIN\",
    \"-DSK_FREETYPE_STATIC\",
    \"-DSK_FREETYPE_MINIMUM_RUNTIME_VERSION=0\"
  ]"
  SKIA_EXTRA_LDFLAGS="[
    \"/LIBPATH:$INSTALL_PREFIX/lib\",
    \"freetype.lib\",
    \"harfbuzz.lib\",
    \"zlibstatic.lib\",
    \"libpng16_static.lib\",
    \"bz2.lib\",
    \"brotlidec.lib\"
  ]"
else
  SKIA_EXTRA_CFLAGS="[
    \"-I$INSTALL_PREFIX/include\",
    \"-I$INSTALL_PREFIX/include/freetype2\",
    \"-I$INSTALL_PREFIX/include/harfbuzz\"
  ]"
  SKIA_EXTRA_LDFLAGS="[
    \"-L$INSTALL_PREFIX/lib\"
  ]"
fi


SKIA_ARGS="
is_official_build=true
is_component_build=false
skia_use_gl=true
skia_enable_ganesh=true
skia_enable_tools=false
skia_enable_pdf=false
skia_enable_fontmgr_android=false
skia_use_freetype=true
skia_use_harfbuzz=true
skia_use_system_zlib=true
skia_use_system_libpng=true
skia_use_system_libjpeg_turbo=false
skia_use_system_libwebp=false
skia_use_system_icu=false
target_os=\"${PLATFORM}\"
target_cpu=\"${ARCH}\"
extra_cflags=$SKIA_EXTRA_CFLAGS
extra_ldflags=$SKIA_EXTRA_LDFLAGS
"
if [[ "$PLATFORM" == "linux" ]]; then
  SKIA_ARGS+="
skia_use_egl=true
skia_use_x11=true
"
fi

echo "Building Skia with the following args:"
echo "${SKIA_ARGS}"
echo ""

bin/gn gen out/Release --args="$SKIA_ARGS"
ninja -C out/Release
echo "- Finished building Skia"
cd ../..

# --- Package ---
echo ""
echo "Packaging libraries..."
PKG_DIR="artifacts/seeds-ui-libs-${PLATFORM_FULLNAME}"
rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}/lib"
mkdir -p "${PKG_DIR}/include"
mkdir -p "${PKG_DIR}/skia"

# Copy includes
cp -r deps/skia/include "${PKG_DIR}/include/skia"
# Skia does includes like `#include "include/core/SkFoo.h"`. Within SeedsUI it's better to keep it
# as "skia/core/SkFoo.h", so just copy the directories to two locations.
cp -r deps/skia/include "${PKG_DIR}/skia/include"
rsync -a  \
    --include='*/' \
    --include='*.h*' \
    --exclude='*' \
        deps/skia/modules/ "${PKG_DIR}/skia/modules"

# Copy libs
find deps/skia/out/Release \( -name "lib*.a" -or -name "*.lib" \) -exec cp {} "${PKG_DIR}/lib/" \;
find deps/install/lib \( -name "lib*.a" -or -name "*.lib" \) -exec cp {} "${PKG_DIR}/lib/" \;

# Compress
if [[ "$PLATFORM" == "win" ]]; then
    7z a ${PKG_DIR}.zip ./${PKG_DIR}/*
else
    tar -czf ${PKG_DIR}.tar.gz -C artifacts seeds-ui-libs-${PLATFORM_FULLNAME}
fi

echo "Building & packaging complete: seeds-ui-libs-${PLATFORM_FULLNAME}"
