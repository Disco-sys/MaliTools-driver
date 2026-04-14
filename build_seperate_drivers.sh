#!/bin/bash
# Build two separate Mali drivers: ZINK/NIR and PanVK

set -e

NDK_VERSION="r28"
API_LEVEL="24"

setup_ndk() { ... }   # same as before
clone_mesa() { ... }  # same
generate_cross_file() { ... }  # same

# --------------------------------------------
# Driver 1: ZINK + Panfrost (MESA NIR path)
# --------------------------------------------
build_zink_nir() {
    echo "Building ZINK/NIR driver (MESA NIR path)..."
    meson setup build-zink \
        --cross-file ../android-cross.txt \
        -Dplatforms=android \
        -Dvulkan-drivers= \
        -Dgallium-drivers=zink,panfrost \
        -Dbuildtype=release \
        -Dllvm=disabled \
        -Dandroid-stub=true \
        -Dzink-descriptors=lazy
    meson compile -C build-zink

    mkdir -p zink_nir_package
    cp build-zink/src/gallium/targets/dri/libgallium_dri.so zink_nir_package/
    # Also include the native Panfrost DRI driver (optional)
    cp build-zink/src/gallium/drivers/panfrost/libpanfrost_dri.so zink_nir_package/ 2>/dev/null || true

    cat > zink_nir_package/meta.json <<EOF
{
    "name": "ZINK_NIR_Mali",
    "version": "1.0",
    "type": "opengl",
    "description": "MESA NIR direct path via ZINK + Panfrost",
    "env": {
        "GALLIUM_DRIVER": "zink",
        "ZINK_DEBUG": "spirv_compact,nir",
        "MESA_GL_VERSION_OVERRIDE": "4.5"
    },
    "supported_gpus": ["Mali-G52", "Mali-G71", "Mali-G72", "Mali-G76", "Mali-G78", "Mali-G710"]
}
EOF
    cd zink_nir_package && zip -r ../zink_nir_driver.zip * && cd ..
}

# --------------------------------------------
# Driver 2: PanVK (Vulkan only)
# --------------------------------------------
build_panvk() {
    echo "Building PanVK driver (Vulkan fallback)..."
    meson setup build-panvk \
        --cross-file ../android-cross.txt \
        -Dplatforms=android \
        -Dvulkan-drivers=panfrost \
        -Dgallium-drivers= \
        -Dbuildtype=release \
        -Dllvm=disabled \
        -Dandroid-stub=true
    meson compile -C build-panvk

    mkdir -p panvk_package
    cp build-panvk/src/panfrost/vulkan/libvulkan_panfrost.so panvk_package/

    cat > panvk_package/meta.json <<EOF
{
    "name": "PanVK_Mali",
    "version": "1.0",
    "type": "vulkan",
    "description": "Standard Panfrost Vulkan driver (fallback)",
    "env": {
        "VK_ICD_FILENAMES": "/path/to/libvulkan_panfrost.so"
    },
    "supported_gpus": ["Mali-G52", "Mali-G71", "Mali-G72", "Mali-G76", "Mali-G78", "Mali-G710"]
}
EOF
    cd panvk_package && zip -r ../panvk_driver.zip * && cd ..
}

# Main
main() {
    setup_ndk
    generate_cross_file
    clone_mesa
    build_zink_nir
    build_panvk
    echo "Two separate drivers built:"
    echo "  - zink_nir_driver.zip (MESA NIR path, for OpenGL games like MX Bikes)"
    echo "  - panvk_driver.zip (Vulkan fallback)"
}

main
