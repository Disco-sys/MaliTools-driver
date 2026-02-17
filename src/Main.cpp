#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <android/log.h>

static void* g_handle = nullptr;

extern "C" {

void* load_lib() {
    if (!g_handle) {
        g_handle = dlopen("vulkan.mt6768.so", RTLD_NOW);
        if (!g_handle) g_handle = dlopen("libvulkan.so", RTLD_NOW);
    }
    return g_handle;
}

VKAPI_ATTR VkResult VKAPI_CALL vkCreateInstance(
    const VkInstanceCreateInfo* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkInstance* pInstance) {
    typedef VkResult (*PFN_vkCreateInstance)(const VkInstanceCreateInfo*, const VkAllocationCallbacks*, VkInstance*);
    PFN_vkCreateInstance real_func = (PFN_vkCreateInstance)dlsym(load_lib(), "vkCreateInstance");
    return real_func(pCreateInfo, pAllocator, pInstance);
}

VKAPI_ATTR VkResult VKAPI_CALL vkCreateDevice(
    VkPhysicalDevice physicalDevice,
    const VkDeviceCreateInfo* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDevice* pDevice) {
    typedef VkResult (*PFN_vkCreateDevice)(VkPhysicalDevice, const VkDeviceCreateInfo*, const VkAllocationCallbacks*, VkDevice*);
    PFN_vkCreateDevice real_func = (PFN_vkCreateDevice)dlsym(load_lib(), "vkCreateDevice");
    return real_func(physicalDevice, pCreateInfo, pAllocator, pDevice);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetDeviceProcAddr(VkDevice device, const char* pName) {
    typedef PFN_vkVoidFunction (*PFN_vkGetDeviceProcAddr)(VkDevice, const char*);
    PFN_vkGetDeviceProcAddr real_func = (PFN_vkGetDeviceProcAddr)dlsym(load_lib(), "vkGetDeviceProcAddr");
    return real_func(device, pName);
}

}

