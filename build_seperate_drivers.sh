#!/bin/bash

# ----------------------------------------------------------------------
# Adapted from K11MCH1's Turnip build script
# Modified for Mali PanVK + Panfrost NIR (Mesa main / 26.1-devel)
# Fixes: vulkan-layers=disabled error + deprecation warnings
# ----------------------------------------------------------------------

set -e

WORKDIR="$PWD/mali_build"
NDK_VERSION="r28"
API_LEVEL="28"
MESA_REPO="https://gitlab.freedesktop.org/mesa/mesa.git"
MESA_BRANCH="main"

# ---------- CREATE WORKSPACE ----------
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ---------- INSTALL DEPENDENCIES ----------
sudo apt-get update
sudo apt-get install -y wget unzip zip ninja-build meson python3-pip \
    python3-mako libxcb-keysyms1-dev libxcb-randr0-dev libx11-xcb-dev \
    libxcb-present-dev libxcb-dri3-dev libxcb-sync-dev libxshmfence-dev \
    libxxf86vm-dev libxrandr-dev libxfixes-dev libxdamage-dev libxext-dev \
    libgl1-mesa-dev libegl1-mesa-dev libdrm-dev pkg-config cmake \
    patchelf

pip3 install --user --upgrade meson
export PATH="$HOME/.local/bin:$PATH"

# ---------- DOWNLOAD NDK ----------
if [ ! -d "android-ndk-${NDK_VERSION}" ]; then
    echo "==> Downloading NDK ${NDK_VERSION}..."
    wget -q "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
    unzip -q "android-ndk-${NDK_VERSION}-linux.zip"
fi
NDK="$PWD/android-ndk-${NDK_VERSION}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"

# ---------- CLONE MESA ----------
if [ ! -d "mesa" ]; then
    echo "==> Cloning Mesa..."
    git clone --depth 1 --branch "$MESA_BRANCH" "$MESA_REPO"
fi
cd mesa
MESA_VERSION=$(cat VERSION)
echo "==> Mesa version: $MESA_VERSION"

# ---------- CREATE CROSS FILE (fixed deprecations) ----------
cat > "$WORKDIR/android-aarch64" <<EOF
[binaries]
c = '$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang'
cpp = '$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang++'
ar = '$TOOLCHAIN/bin/llvm-ar'
strip = '$TOOLCHAIN/bin/llvm-strip'
pkg-config = '/usr/bin/pkg-config'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'

[built-in options]
c_args = ['-DETIME=ETIMEDOUT', '-DANDROID']
cpp_args = ['-DETIME=ETIMEDOUT', '-DANDROID']

[properties]
needs_exe_wrapper = true
EOF

export CFLAGS="-DETIME=ETIMEDOUT"
export CXXFLAGS="-DETIME=ETIMEDOUT"

# ---------- MESON CONFIGURE (fixed vulkan-layers) ----------
echo "==> Configuring Mesa for PanVK + Panfrost NIR..."
meson setup build-android \
    --cross-file "$WORKDIR/android-aarch64" \
    -Dplatforms=android \
    -Dvulkan-drivers=panfrost \
    -Dgallium-drivers=panfrost \
    -Dvulkan-layers= \
    -Dandroid-stub=true \
    -Dbuildtype=release \
    -Dllvm=disabled \
    -Dopengl=true \
    -Dgbm=disabled \
    -Dglx=disabled \
    -Degl=enabled \
    -Dgles1=disabled \
    -Dgles2=enabled \
    -Dshared-glapi=enabled \
    -Dbuild-tests=false \
    -Dinstall-intel-gpu-tests=false \
    -Dzstd=enabled \
    -Dvulkan-beta=false \
    --strip

# ---------- COMPILE ----------
echo "==> Compiling..."
meson compile -C build-android -j$(nproc)

# ---------- PACKAGE VULKAN ----------
echo "==> Packaging Vulkan driver (Adreno Tools format)..."
PKG_VULKAN="$WORKDIR/vulkan_panfrost"
rm -rf "$PKG_VULKAN"
mkdir -p "$PKG_VULKAN"

cp build-android/src/panfrost/vulkan/libvulkan_panfrost.so "$PKG_VULKAN/vulkan.panfrost.so"
patchelf --set-soname vulkan.panfrost.so "$PKG_VULKAN/vulkan.panfrost.so"

cat > "$PKG_VULKAN/meta.json" <<EOF
{
  "name": "PanVK (Mali G52+)",
  "description": "Mesa ${MESA_VERSION} PanVK Vulkan driver for Mali",
  "author": "Mesa Community",
  "version": "${MESA_VERSION}",
  "api": "1.1",
  "vulkan": {
    "api": "1.3.0",
    "driver": "panvk",
    "file": "vulkan.panfrost.so",
    "uuid": "panvk-mali-bifrost-valhall"
  }
}
EOF

cd "$WORKDIR"
zip -r panvk_adrenotools.zip vulkan_panfrost/

# ---------- PACKAGE OPENGL ES (MESA NIR) ----------
echo "==> Packaging OpenGL ES driver (Mesa NIR/Panfrost)..."
PKG_GLES="$WORKDIR/opengl_panfrost"
rm -rf "$PKG_GLES"
mkdir -p "$PKG_GLES"

cp mesa/build-android/src/gallium/targets/dri/libgallium_dri.so "$PKG_GLES/"
cp mesa/build-android/src/egl/libEGL.so "$PKG_GLES/"
cp mesa/build-android/src/mapi/shared-glapi/libglapi.so "$PKG_GLES/"
cp mesa/build-android/src/gles/libGLESv2.so "$PKG_GLES/"
[ -f mesa/build-android/src/gles/libGLESv1_CM.so ] && cp mesa/build-android/src/gles/libGLESv1_CM.so "$PKG_GLES/"

cat > "$PKG_GLES/meta.json" <<EOF
{
  "name": "Mesa NIR (Panfrost)",
  "description": "OpenGL ES 2.0/3.x driver for Mali (Bifrost/Valhall)",
  "author": "Mesa Community",
  "version": "${MESA_VERSION}",
  "gles": {
    "driver": "panfrost",
    "file": "libgallium_dri.so"
  }
}
EOF

zip -r mesa_nir_adrenotools.zip opengl_panfrost/

# ---------- DONE ----------
echo "============================================================"
echo "Build complete!"
echo "Vulkan package   : $WORKDIR/panvk_adrenotools.zip"
echo "OpenGL ES package: $WORKDIR/mesa_nir_adrenotools.zip"
echo "Mesa version     : $MESA_VERSION"
echo "============================================================"
