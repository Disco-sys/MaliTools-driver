#!/bin/bash -e

WORKDIR="$PWD/mali_build"
NDK_VERSION="r27c"
API_LEVEL="26"
MESA_REPO="https://gitlab.freedesktop.org/mesa/mesa.git"
MESA_BRANCH="main"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

sudo apt update
sudo apt install -y python3-pip ninja-build pkg-config libelf-dev wget unzip zip cmake libzstd-dev
pip3 install --user meson mako
export PATH="$HOME/.local/bin:$PATH"

if [ ! -d "android-ndk-${NDK_VERSION}" ]; then
    wget -q "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
    unzip -q "android-ndk-${NDK_VERSION}-linux.zip"
fi
NDK="$PWD/android-ndk-${NDK_VERSION}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"

if [ ! -d "mesa" ]; then
    git clone --depth 1 --branch "$MESA_BRANCH" "$MESA_REPO"
fi
cd mesa
MESA_VERSION=$(cat VERSION)

cat > "$WORKDIR/cross.txt" <<EOF
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

[properties]
needs_exe_wrapper = true
c_args = ['-DETIME=ETIMEDOUT', '-DANDROID']
cpp_args = ['-DETIME=ETIMEDOUT', '-DANDROID']
EOF

export CFLAGS="-DETIME=ETIMEDOUT"
export CXXFLAGS="-DETIME=ETIMEDOUT"

meson setup build-android \
    --cross-file "$WORKDIR/cross.txt" \
    -Dplatforms=android \
    -Dvulkan-drivers=panfrost \
    -Dgallium-drivers=panfrost \
    -Dvulkan-layers=disabled \
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

meson compile -C build-android -j 2

PKG_PANVK="$WORKDIR/panvk_pkg"
mkdir -p "$PKG_PANVK"
cp build-android/src/panfrost/vulkan/libvulkan_panfrost.so "$PKG_PANVK/"

cat > "$PKG_PANVK/meta.json" <<EOF
{
  "name": "PanVK_Mali",
  "version": "$MESA_VERSION",
  "type": "vulkan",
  "api_version": "1.1",
  "driver_uuid": "panvk-mali-g52",
  "file": "libvulkan_panfrost.so"
}
EOF

cd "$WORKDIR"
zip -r panvk_driver.zip panvk_pkg/

PKG_GLES="$WORKDIR/mesa_nir_pkg"
mkdir -p "$PKG_GLES"
cp mesa/build-android/src/gallium/targets/dri/libgallium_dri.so "$PKG_GLES/"
cp mesa/build-android/src/egl/libEGL.so "$PKG_GLES/"
cp mesa/build-android/src/mapi/shared-glapi/libglapi.so "$PKG_GLES/"
cp mesa/build-android/src/gles/libGLESv2.so "$PKG_GLES/"
[ -f mesa/build-android/src/gles/libGLESv1_CM.so ] && cp mesa/build-android/src/gles/libGLESv1_CM.so "$PKG_GLES/"

cat > "$PKG_GLES/meta.json" <<EOF
{
  "name": "Mesa_NIR_Panfrost",
  "version": "$MESA_VERSION",
  "type": "opengl",
  "renderer": "panfrost",
  "description": "OpenGL ES 2.0/3.x driver for Mali GPUs (Bifrost/Valhall)",
  "files": ["libgallium_dri.so", "libEGL.so", "libGLESv2.so", "libglapi.so"]
}
EOF

zip -r mesa_nir_driver.zip mesa_nir_pkg/

echo "============================================================"
echo "Build succeeded! Mesa version: $MESA_VERSION"
echo "Artifacts:"
echo "  Vulkan (PanVK)     : $WORKDIR/panvk_driver.zip"
echo "  OpenGL ES (Mesa NIR): $WORKDIR/mesa_nir_driver.zip"
echo "============================================================"
