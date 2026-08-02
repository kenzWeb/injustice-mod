TARGET := iphone:clang:latest:15.0
ARCHS  := arm64 arm64e

THEOS_PACKAGE_SCHEME := roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = InjusticeMod

InjusticeMod_FILES = \
    Tweak.xm \
    src/IMSettings.m \
    src/IMPresets.m \
    src/IMRuntime.m \
    src/IMDamage.m \
    src/IMHooks.m \
    src/IMTheme.m \
    src/IMOverlayWindow.m \
    src/IMRowBuilder.m \
    src/IMMenu.m

InjusticeMod_CFLAGS     = -fobjc-arc -I$(THEOS_PROJECT_DIR)/src -Wno-unused-variable -Wno-deprecated-declarations
InjusticeMod_FRAMEWORKS = UIKit Foundation QuartzCore CFNetwork SystemConfiguration WebKit
InjusticeMod_LIBRARIES  = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 Injustice2Mobile || true"
