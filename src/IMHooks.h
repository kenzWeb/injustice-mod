#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

BOOL IMHooksInstall(void);
BOOL IMHooksInstalled(void);

int IMSummaryPressCount(void);
unsigned long long IMSummaryArg1(void);
unsigned long long IMSummaryArg2(void);
BOOL IMSummaryMenuMatches(void);

#ifdef __cplusplus
}
#endif
