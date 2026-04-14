#!/bin/bash -e

WORKDIR="$PWD/mali_build"
NDK_VERSION="r25c"
API_LEVEL="31"
MESA_REPO="https://gitlab.freedesktop.org/mesa/mesa.git"
MESA_BRANCH="main"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

sudo apt update
sudo apt install -y \
    python3-pip ninja-build pkg-config libelf-dev wget unzip zip \
    liblz4-dev libssl-dev \
    libx11-dev libxext-dev libxdamage-dev libxfixes-dev libxrandr-dev \
    libxcb-glx0-dev libxcb-shm0-dev libxcb-dri2-0-dev libxcb-dri3-dev \
    libxcb-present-dev libxcb-sync-dev libxshmfence-dev \
    libxxf86vm-dev libxinerama-dev libxcursor-dev \
    libwayland-dev wayland-protocols \
    libgl1-mesa-dev libglu1-mesa-dev \
    flex bison \
    libunwind-dev \
    libva-dev libvdpau-dev \
    libomxil-bellagio-dev \
    libvulkan-dev \
    libxml2-dev \
    libglvnd-dev \
    libsensors-dev \
    libpciaccess-dev

pip3 install --upgrade pip
pip3 install meson mako

wget -q "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
unzip -q "android-ndk-${NDK_VERSION}-linux.zip"
NDK="$PWD/android-ndk-${NDK_VERSION}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"

git clone --depth 1 --branch "$MESA_BRANCH" "$MESA_REPO"
cd mesa

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
EOF

# Build ZINK driver (disable drm and zstd)
meson setup build-zink \
    --cross-file "$WORKDIR/cross.txt" \
    -Dplatforms=android \
    -Dgallium-drivers=zink \
    -Dvulkan-drivers= \
    -Dbuildtype=release \
    -Dllvm=disabled \
    -Dandroid-stub=true \
    -Dglx=disabled \
    -Dshared-glapi=enabled \
    -Dzstd=disabled \
    -Dlibdrm=disabled \
    -Dc_args="-DETIME=ETIMEDOUT"

meson compile -C build-zink

mkdir -p "$WORKDIR/zink_pkg"
DRIVER_PATH=$(find build-zink -name "libgallium_dri.so" | head -1)
cp "$DRIVER_PATH" "$WORKDIR/zink_pkg/"

cat > "$WORKDIR/zink_pkg/meta.json" <<EOF
{
  "name": "ZINK_MESA_NIR_Mali",
  "version": "mesa-$(git rev-parse --short HEAD)",
  "type": "opengl",
  "env": {
    "GALLIUM_DRIVER": "zink",
    "ZINK_DEBUG": "spirv_compact,nir",
    "MESA_GL_VERSION_OVERRIDE": "4.5"
  }
}
EOF

# Build PanVK driver (disable drm and zstd)
meson setup build-panvk \
    --cross-file "$WORKDIR/cross.txt" \
    -Dplatforms=android \
    -Dvulkan-drivers=panfrost \
    -Dgallium-drivers= \
    -Dbuildtype=release \
    -Dllvm=disabled \
    -Dandroid-stub=true \
    -Dglx=disabled \
    -Dshared-glapi=enabled \
    -Dzstd=disabled \
    -Dlibdrm=disabled \
    -Dc_args="-DETIME=ETIMEDOUT"

meson compile -C build-panvk

mkdir -p "$WORKDIR/panvk_pkg"
cp build-panvk/src/panfrost/vulkan/libvulkan_panfrost.so "$WORKDIR/panvk_pkg/"

cat > "$WORKDIR/panvk_pkg/meta.json" <<EOF
{
  "name": "PanVK_Mali",
  "version": "mesa-$(git rev-parse --short HEAD)",
  "type": "vulkan"
}
EOF

cd "$WORKDIR"
zip -r zink_mesa_nir_driver.zip zink_pkg/
zip -r panvk_driver.zip panvk_pkg/

echo "Build successful. Artifacts:"
echo "  - $WORKDIR/zink_mesa_nir_driver.zip"
echo "  - $WORKDIR/panvk_driver.zip"
