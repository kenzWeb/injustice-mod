#import <Foundation/Foundation.h>
#import "src/Offsets.h"
#import "src/IMRuntime.h"
#import "src/IMSettings.h"
#import "src/IMHooks.h"
#import "src/IMLog.h"
#import "src/IMMenu.h"

%ctor {
    @autoreleasepool {
        IMLogInit();
        IMSettingsInit();

        if (!IMRuntimeResolveImage()) {
            NSLog(@"[IMMod] main image not found, aborting");
            return;
        }

        if (!IMRuntimeVersionMatches()) {
            NSDictionary *info = NSBundle.mainBundle.infoDictionary;
            NSLog(@"[IMMod] build mismatch, expected %@ (%@), got %@ (%@), not hooking",
                  kExpectedShortVersion, kExpectedBundleVersion,
                  info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]);
            return;
        }

        if (!IMHooksInstall()) return;
        IMMenuPresentWhenReady();
    }
}
