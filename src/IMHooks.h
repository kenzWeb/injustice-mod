#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

BOOL IMHooksInstall(void);
BOOL IMHooksInstalled(void);
BOOL IMTriggerClaimSoloRaidBoss(int difficultyIndex, int levelIndex, int bossIndex);

#ifdef __cplusplus
}
#endif
