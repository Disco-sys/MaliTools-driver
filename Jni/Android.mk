
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE    := vulkan.mt6768
LOCAL_SRC_FILES := ../src/main.cpp
LOCAL_LDLIBS    := -llog -ldl
LOCAL_CPPFLAGS  := -std=c++17
include $(BUILD_SHARED_LIBRARY)
