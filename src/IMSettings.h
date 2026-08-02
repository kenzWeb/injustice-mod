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

#ifdef __cplusplus
extern "C" {
#endif

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

BOOL IMFreezeAI(void);
void IMSetFreezeAI(BOOL on);

BOOL IMBypassRequirements(void);
void IMSetBypassRequirements(BOOL on);

BOOL IMBypassVPNCheck(void);
void IMSetBypassVPNCheck(BOOL on);

void IMRequestHeal(void);
BOOL IMConsumeHealRequest(void);

void IMTriggerAutoWin(void);
BOOL IMAutoWinActive(void);

typedef struct {
    BOOL      godMode;
    BOOL      oneHitKill;
    BOOL      freezeAll;
    BOOL      infiniteEnergy;
    BOOL      freezeAI;
    BOOL      fixedDamageEnabled;
    BOOL      bypassVPNCheck;
    long long fixedDamage;
    double    damageMultiplier;
    double    defenseMultiplier;
} IMSettingsSnapshot;

IMSettingsSnapshot IMCaptureSettings(void);
void IMApplySettings(IMSettingsSnapshot snapshot);

void IMPublishPlayerHealth(int hp, int max);
void IMPublishEnemyHealth(int hp, int max);
IMHealthSnapshot IMReadHealth(void);

void IMPublishTapjoyURL(NSString *urlString);
NSString *IMGetLastTapjoyURL(void);

#ifdef __cplusplus
}
#endif
