#pragma once
#import <UIKit/UIKit.h>

@interface IMMenu : NSObject
+ (instancetype)shared;
- (BOOL)presentIfPossible;
@end

void IMMenuPresentWhenReady(void);
