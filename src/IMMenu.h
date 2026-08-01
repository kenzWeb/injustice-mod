#pragma once
#import <UIKit/UIKit.h>

@interface IMMenu : NSObject
+ (instancetype)shared;
- (BOOL)presentIfPossible;
@end

// Tweak.xm is Objective-C++; this lives in a plain .m file — keep C linkage.
#ifdef __cplusplus
extern "C" {
#endif

void IMMenuPresentWhenReady(void);

#ifdef __cplusplus
}
#endif
