#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

BOOL IMHooksInstall(void);
BOOL IMHooksInstalled(void);
void IMTriggerClaimSoloRaidBoss(void);

#ifdef __cplusplus
}
#endif
