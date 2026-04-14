#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$SCRIPT_DIR/Dependencies"
NDK_DIR="$DEPS_DIR/NDK"
WORKDIR="$SCRIPT_DIR/mali_build"

mkdir -p "$DEPS_DIR" "$NDK_DIR" "$WORKDIR"

# System deps
sudo apt-get update -y
sudo apt-get install -y --show-progress wget unzip zip ninja-build meson python3-pip python3-mako patchelf pkg-config cmake libxcb-*-dev libgl1-mesa-dev libegl1-mesa-dev libdrm-dev glslang-tools
pip3 install --user --upgrade meson mako
export PATH="$HOME/.local/bin:$PATH"

# NDK cached
NDK_PATH="$NDK_DIR/android-ndk-r28"
if [ ! -d "$NDK_PATH" ]; then
    cd "$NDK_DIR"
    wget --progress=bar:force https://dl.google.com/android/repository/android-ndk-r28-linux.zip
    unzip -q android-ndk-r28-linux.zip
    rm android-ndk-r28-linux.zip
fi
TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64"

# Mesa source
cd "$WORKDIR"
[ -d mesa ] || git clone --depth 1 --branch main https://gitlab.freedesktop.org/mesa/mesa.git
cd mesa
MESA_VERSION=$(cat VERSION)

# Cross file
cat > "$WORKDIR/cross.txt" <<EOF
[binaries]
c = '$TOOLCHAIN/bin/aarch64-linux-android28-clang'
cpp = '$TOOLCHAIN/bin/aarch64-linux-android28-clang++'
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

# Configure (NO opencl options)
meson setup build-android --cross-file "$WORKDIR/cross.txt" \
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
    -Dzstd=enabled \
    -Dvulkan-beta=false \
    --strip

# Build
meson compile -C build-android -j$(nproc)

# Package Vulkan
PKG_V="$WORKDIR/vulkan_panfrost"
rm -rf "$PKG_V" && mkdir -p "$PKG_V"
cp build-android/src/panfrost/vulkan/libvulkan_panfrost.so "$PKG_V/vulkan.panfrost.so"
patchelf --set-soname vulkan.panfrost.so "$PKG_V/vulkan.panfrost.so"
echo "{\"name\":\"PanVK\",\"version\":\"$MESA_VERSION\",\"vulkan\":{\"file\":\"vulkan.panfrost.so\",\"uuid\":\"panvk-mali\"}}" > "$PKG_V/meta.json"
cd "$WORKDIR" && zip -qr panvk_adrenotools.zip vulkan_panfrost/

# Package GLES
PKG_G="$WORKDIR/opengl_panfrost"
rm -rf "$PKG_G" && mkdir -p "$PKG_G"
cp mesa/build-android/src/gallium/targets/dri/libgallium_dri.so "$PKG_G/"
cp mesa/build-android/src/egl/libEGL.so "$PKG_G/"
cp mesa/build-android/src/mapi/shared-glapi/libglapi.so "$PKG_G/"
cp mesa/build-android/src/gles/libGLESv2.so "$PKG_G/"
[ -f mesa/build-android/src/gles/libGLESv1_CM.so ] && cp mesa/build-android/src/gles/libGLESv1_CM.so "$PKG_G/"
echo "{\"name\":\"Mesa NIR\",\"version\":\"$MESA_VERSION\",\"gles\":{\"file\":\"libgallium_dri.so\"}}" > "$PKG_G/meta.json"
zip -qr mesa_nir_adrenotools.zip opengl_panfrost/

echo "✅ Build complete."
echo "NDK cached: $NDK_PATH"
echo "Packages: $WORKDIR/panvk_adrenotools.zip, $WORKDIR/mesa_nir_adrenotools.zip"
