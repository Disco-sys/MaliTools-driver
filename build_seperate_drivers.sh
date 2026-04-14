#!/bin/bash -e

WORKDIR="$PWD/mali_build"
NDK_VERSION="r27c"
API_LEVEL="26"
MESA_REPO="https://gitlab.freedesktop.org/mesa/mesa.git"
MESA_BRANCH="main"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

sudo apt update
sudo apt install -y python3-pip ninja-build pkg-config libelf-dev wget unzip zip
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

# Define ETIME to avoid compile error
export CFLAGS="-DETIME=ETIMEDOUT"
export CXXFLAGS="-DETIME=ETIMEDOUT"

meson setup build-android \
    --cross-file "$WORKDIR/cross.txt" \
    -Dplatforms=android \
    -Dvulkan-drivers=panfrost \
    -Dandroid-stub=true \
    -Dbuildtype=release \
    -Dllvm=disabled

meson compile -C build-android

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
