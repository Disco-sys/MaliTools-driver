#!/bin/bash -e

WORKDIR="$PWD/mali_build"
NDK_VERSION="r27c"
API_LEVEL="26"
MESA_REPO="https://gitlab.freedesktop.org/mesa/mesa.git"
MESA_BRANCH="main"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Install dependencies
sudo apt update
sudo apt install -y python3-pip ninja-build pkg-config libelf-dev wget unzip zip
pip3 install meson mako

# Download and set up the NDK
wget -q "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
unzip -q "android-ndk-${NDK_VERSION}-linux.zip"
NDK="$PWD/android-ndk-${NDK_VERSION}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
export PATH=$TOOLCHAIN/bin:$PATH

# Clone Mesa
git clone --depth 1 --branch "$MESA_BRANCH" "$MESA_REPO"
cd mesa

# Create the cross-compilation file (based on the official docs)
cat > "$WORKDIR/android-aarch64.txt" <<EOF
[binaries]
c = ['ccache', '$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang']
cpp = ['ccache', '$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
ar = '$TOOLCHAIN/bin/llvm-ar'
strip = '$TOOLCHAIN/bin/llvm-strip'
pkg-config = '/usr/bin/pkg-config'
c_ld = 'lld'
cpp_ld = 'lld'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'

[built-in options]
# This line is the key: it disables the clc compiler, which was the source of the LLVM dependency.
clc = 'disabled'
EOF

# Configure the build with the cross file.
# Note: -Dllvm is not needed here, as the dependency is removed in the cross file.
meson setup build-android \
  --cross-file "$WORKDIR/android-aarch64.txt" \
  -Dplatforms=android \
  -Dplatform-sdk-version=26 \
  -Dandroid-stub=true \
  -Degl=disabled \
  -Dgallium-drivers= \
  -Dvulkan-drivers=panfrost \
  -Dbuildtype=release

meson compile -C build-android

# Package the driver
mkdir -p "$WORKDIR/panvk_pkg"
cp build-android/src/panfrost/vulkan/libvulkan_panfrost.so "$WORKDIR/panvk_pkg/"

cat > "$WORKDIR/panvk_pkg/meta.json" <<EOF
{
  "name": "PanVK_Mali",
  "version": "mesa-$(git rev-parse --short HEAD)",
  "type": "vulkan"
}
EOF

cd "$WORKDIR"
zip -r panvk_driver.zip panvk_pkg/

echo "Build successful. Artifact: $WORKDIR/panvk_driver.zip"
