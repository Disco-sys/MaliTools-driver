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
export PATH=$TOOLCHAIN/bin:$PATH

git clone --depth 1 --branch "$MESA_BRANCH" "$MESA_REPO"
cd mesa

cat > "$WORKDIR/android-aarch64.txt" <<EOF
[constants]
ndk_path = '$NDK'

[binaries]
ar = ndk_path / 'toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
c = ['ccache', ndk_path / 'toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android${API_LEVEL}-clang']
cpp = ['ccache', ndk_path / 'toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android${API_LEVEL}-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = ndk_path / 'toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
pkg-config = '/usr/bin/pkg-config'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

meson setup build-android \
  --cross-file "$WORKDIR/android-aarch64.txt" \
  -Dplatforms=android \
  -Dplatform-sdk-version=26 \
  -Dandroid-stub=true \
  -Degl=disabled \
  -Dgallium-drivers= \
  -Dvulkan-drivers=panfrost \
  -Dbuildtype=release \
  -Dllvm=disabled \
  -Dgallium-opencl=disabled \
  -Dopencl=disabled

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
