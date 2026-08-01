#pragma once
#import <Foundation/Foundation.h>

// Tweak.xm is Objective-C++; these live in a plain .m file — keep C linkage.
#ifdef __cplusplus
extern "C" {
#endif

BOOL IMHooksInstall(void);
BOOL IMHooksInstalled(void);

#ifdef __cplusplus
}
#endif
