TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PinaTVLabTweak
PinaTVLabTweak_FILES = Tweak.xm
PinaTVLabTweak_CFLAGS = -fobjc-arc
PinaTVLabTweak_FRAMEWORKS = UIKit AVFoundation
PinaTVLabTweak_PRIVATE_FRAMEWORKS =

include $(THEOS_MAKE_PATH)/tweak.mk
