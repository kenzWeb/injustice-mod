#pragma once
#import <UIKit/UIKit.h>

@interface IMMenu : NSObject
+ (instancetype)shared;
- (BOOL)presentIfPossible;
@end

#ifdef __cplusplus
extern "C" {
#endif

void IMMenuPresentWhenReady(void);

#ifdef __cplusplus
}
#endif
