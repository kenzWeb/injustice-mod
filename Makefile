TARGET := iphone:clang:latest:15.0
ARCHS  := arm64 arm64e

# Packaging scheme — this is the ONLY thing that differs between jailbreaks,
# the tweak code itself uses no filesystem paths.
#   roothide  : RootHide (needs the roothide/theos fork — see README)
#   rootless  : Dopamine / palera1n rootless
#   (omit)    : rootful — checkra1n / unc0ver
THEOS_PACKAGE_SCHEME := roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = InjusticeMod

InjusticeMod_FILES      = Tweak.xm
InjusticeMod_CFLAGS     = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations
InjusticeMod_FRAMEWORKS = UIKit Foundation QuartzCore
InjusticeMod_LIBRARIES  = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 Injustice2Mobile || true"
