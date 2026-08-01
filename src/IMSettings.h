#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    int  playerHP;
    int  playerMax;
    int  enemyHP;
    int  enemyMax;
    BOOL stale;
} IMHealthSnapshot;

#define IM_MULTIPLIER_MAX  999999999.0
#define IM_FIXED_DAMAGE_MAX 999999999LL

void IMSettingsInit(void);

BOOL IMMasterOff(void);
void IMSetMasterOff(BOOL on);

BOOL IMGodMode(void);
void IMSetGodMode(BOOL on);

BOOL IMOneHitKill(void);
void IMSetOneHitKill(BOOL on);

BOOL IMFreezeAll(void);
void IMSetFreezeAll(BOOL on);

BOOL IMFixedDamageEnabled(void);
void IMSetFixedDamageEnabled(BOOL on);

long long IMFixedDamage(void);
void IMSetFixedDamage(long long value);

double IMDamageMultiplier(void);
void IMSetDamageMultiplier(double value);

double IMDefenseMultiplier(void);
void IMSetDefenseMultiplier(double value);

BOOL IMInfiniteEnergy(void);
void IMSetInfiniteEnergy(BOOL on);

void IMRequestHeal(void);
BOOL IMConsumeHealRequest(void);

void IMTriggerAutoWin(void);
BOOL IMAutoWinActive(void);

void IMPublishPlayerHealth(int hp, int max);
void IMPublishEnemyHealth(int hp, int max);
IMHealthSnapshot IMReadHealth(void);
