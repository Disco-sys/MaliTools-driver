#!/bin/bash -e

# ----------------------------------------
# Configuration
# ----------------------------------------
WORKDIR="$PWD/mali_build"
NDK_VERSION="r28"
API_LEVEL="24"
MESA_REPO="https://gitlab.freedesktop.org/mesa/mesa.git"
MESA_BRANCH="main"

# ----------------------------------------
# Prepare environment
# ----------------------------------------
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Install system dependencies (if running on Ubuntu runner)
sudo apt update
sudo apt install -y python3-pip ninja-build pkg-config libelf-dev wget unzip zip libzstd-dev
pip3 install meson mako

# Download NDK
wget -q "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
unzip -q "android-ndk-${NDK_VERSION}-linux.zip"
NDK="$PWD/android-ndk-${NDK_VERSION}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"

# Clone Mesa
git clone --depth 1 --branch "$MESA_BRANCH" "$MESA_REPO"
cd mesa

# ----------------------------------------
# Create cross compilation file (exactly like Kimchi)
# ----------------------------------------
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

# ----------------------------------------
# Build Driver 1: ZINK (MESA NIR path)
# ----------------------------------------
meson setup build-zink \
    --cross-file "$WORKDIR/cross.txt" \
    -Dplatforms=android \
    -Dgallium-drivers=zink \
    -Dvulkan-drivers= \
    -Dbuildtype=release \
    -Dllvm=disabled \
    -Dandroid-stub=true

meson compile -C build-zink

# Find and copy the DRI driver
mkdir -p "$WORKDIR/zink_pkg"
DRIVER_PATH=$(find build-zink -name "libgallium_dri.so" | head -1)
cp "$DRIVER_PATH" "$WORKDIR/zink_pkg/"

# Create meta.json
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

# ----------------------------------------
# Build Driver 2: PanVK
# ----------------------------------------
meson setup build-panvk \
    --cross-file "$WORKDIR/cross.txt" \
    -Dplatforms=android \
    -Dvulkan-drivers=panfrost \
    -Dgallium-drivers= \
    -Dbuildtype=release \
    -Dllvm=disabled \
    -Dandroid-stub=true

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

# ----------------------------------------
# Package both drivers as separate ZIPs
# ----------------------------------------
cd "$WORKDIR"
zip -r zink_mesa_nir_driver.zip zink_pkg/
zip -r panvk_driver.zip panvk_pkg/

echo "Build completed. Artifacts:"
echo "  - $WORKDIR/zink_mesa_nir_driver.zip"
echo "  - $WORKDIR/panvk_driver.zip"
