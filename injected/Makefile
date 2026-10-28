TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = PinaTVLabInjected
PinaTVLabInjected_FILES = Injected.m
PinaTVLabInjected_CFLAGS = -fobjc-arc -Wno-unused-parameter
PinaTVLabInjected_FRAMEWORKS = Foundation UIKit AVFoundation
PinaTVLabInjected_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk
