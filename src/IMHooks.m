#import "IMHooks.h"
#import "IMRuntime.h"
#import "IMSettings.h"
#import "IMDamage.h"
#import "Offsets.h"
#import "IMLog.h"
#import <substrate.h>
#import <QuartzCore/QuartzCore.h>
#import <stdint.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <CFNetwork/CFNetwork.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <sys/sysctl.h>
#import <sys/socket.h>

#ifndef NET_RT_IFLIST
#define NET_RT_IFLIST 3
#endif

typedef void (*IMSetCurrentHealthFn)(void *character, int newHealth);
typedef void (*IMShowDamageMessageFn)(void *victim,
                                      float amount,
                                      void *damageEvent,
                                      void *causer,
                                      bool isCrit,
                                      bool isLethal,
                                      bool isTrueDamage);

typedef bool  (*IMHasEnoughFn)(void *character, int abilityType);
typedef float (*IMPowerPercentFn)(void *character, int abilityType);
typedef float (*IMCurrentResourceFn)(void *character);
typedef float (*IMResourceCurrentFn)(void *resource);

static long long IMNowMillis(void) {
    return (long long)(CACurrentMediaTime() * 1000.0);
}

static IMSetCurrentHealthFn  sOrigSetCurrentHealth;
static IMShowDamageMessageFn sOrigShowDamageMessage;
static IMHasEnoughFn         sOrigHasEnoughFunds;
static IMHasEnoughFn         sOrigHasEnoughPower;
static IMHasEnoughFn         sOrigHasEnoughEnergy;
static IMHasEnoughFn         sOrigHasEnoughResource;
typedef bool (*IMIsStunnedFn)(void *character, int stunType);

static IMIsStunnedFn         sOrigIsStunned;
static IMPowerPercentFn      sOrigGetPowerPercentage;
static IMCurrentResourceFn   sOrigGetCurrentPower;
static IMCurrentResourceFn   sOrigGetCurrentEnergy;
static BOOL sInstalled;

typedef CFDictionaryRef (*IMCFNetworkCopySystemProxySettingsFn)(void);
static IMCFNetworkCopySystemProxySettingsFn sOrigCFNetworkCopySystemProxySettings;

static CFDictionaryRef IMHookCFNetworkCopySystemProxySettings(void) {
    if (!IMMasterOff() && IMBypassVPNCheck()) {
        static CFDictionaryRef sEmptyProxyDict;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sEmptyProxyDict = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                                                 &kCFTypeDictionaryKeyCallBacks,
                                                 &kCFTypeDictionaryValueCallBacks);
        });
        if (sEmptyProxyDict) CFRetain(sEmptyProxyDict);
        return sEmptyProxyDict;
    }
    return sOrigCFNetworkCopySystemProxySettings ? sOrigCFNetworkCopySystemProxySettings() : NULL;
}

typedef Boolean (*IMSCNetworkReachabilityGetFlagsFn)(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags);
static IMSCNetworkReachabilityGetFlagsFn sOrigSCNetworkReachabilityGetFlags;

static Boolean IMHookSCNetworkReachabilityGetFlags(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags) {
    Boolean ret = sOrigSCNetworkReachabilityGetFlags ? sOrigSCNetworkReachabilityGetFlags(target, flags) : false;
    if (ret && flags && !IMMasterOff() && IMBypassVPNCheck()) {
        // Clear transient/direct VPN connection flags (1 << 0 and 1 << 17)
        *flags &= ~(kSCNetworkReachabilityFlagsTransientConnection | kSCNetworkReachabilityFlagsIsDirect);
        *flags |= kSCNetworkReachabilityFlagsReachable;
    }
    return ret;
}

typedef int (*IMSysctlFn)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static IMSysctlFn sOrigSysctl;

static int IMHookSysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = sOrigSysctl ? sOrigSysctl(name, namelen, oldp, oldlenp, newp, newlen) : -1;
    if (ret == 0 && oldp && oldlenp && *oldlenp > 0 && name && namelen >= 6 && !IMMasterOff() && IMBypassVPNCheck()) {
        if (name[0] == CTL_NET && name[1] == PF_ROUTE && name[4] == NET_RT_IFLIST) {
            char *buf = (char *)oldp;
            size_t size = *oldlenp;
            for (size_t i = 0; i + 4 < size; i++) {
                if (strncasecmp(buf + i, "utun", 4) == 0 ||
                    strncasecmp(buf + i, "ipsec", 5) == 0) {
                    memcpy(buf + i, "lo99", 4);
                }
            }
        }
    }
    return ret;
}

typedef int (*IMGetifaddrsFn)(struct ifaddrs **ifap);
static IMGetifaddrsFn sOrigGetifaddrs;

static int IMHookGetifaddrs(struct ifaddrs **ifap) {
    int ret = sOrigGetifaddrs ? sOrigGetifaddrs(ifap) : -1;
    if (ret == 0 && ifap && *ifap && !IMMasterOff() && IMBypassVPNCheck()) {
        for (struct ifaddrs *curr = *ifap; curr != NULL; curr = curr->ifa_next) {
            char *name = curr->ifa_name;
            if (name) {
                if (strncasecmp(name, "utun", 4) == 0 ||
                    strncasecmp(name, "tun", 3) == 0 ||
                    strncasecmp(name, "ppp", 3) == 0 ||
                    strncasecmp(name, "ipsec", 5) == 0 ||
                    strncasecmp(name, "tap", 3) == 0 ||
                    strncasecmp(name, "wg", 2) == 0 ||
                    strcasestr(name, "vpn") != NULL) {
                    size_t len = strlen(name);
                    if (len >= 3) {
                        memcpy(name, "lo9", 3);
                        memset(name + 3, 0, len - 3);
                    }
                    curr->ifa_flags &= ~IFF_POINTOPOINT;
                    curr->ifa_dstaddr = NULL;
                }
            }
            if (curr->ifa_flags & IFF_POINTOPOINT) {
                curr->ifa_flags &= ~IFF_POINTOPOINT;
            }
        }
    }
    return ret;
}

static NSInteger (*sOrigNEVPNConnectionStatus)(id self, SEL _cmd);
static NSInteger IMHookNEVPNConnectionStatus(id self, SEL _cmd) {
    if (!IMMasterOff() && IMBypassVPNCheck()) {
        return 0; // NEVPNStatusDisconnected
    }
    return sOrigNEVPNConnectionStatus ? sOrigNEVPNConnectionStatus(self, _cmd) : 0;
}

static NSString * (*sOrigTjConnType)(id self, SEL _cmd);
static NSString * IMHookTjConnType(id self, SEL _cmd) {
    if (!IMMasterOff() && IMBypassVPNCheck()) {
        return @"wifi";
    }
    return sOrigTjConnType ? sOrigTjConnType(self, _cmd) : @"wifi";
}

static NSString * (*sOrigTjConnSubtype)(id self, SEL _cmd);
static NSString * IMHookTjConnSubtype(id self, SEL _cmd) {
    if (!IMMasterOff() && IMBypassVPNCheck()) {
        return @"wifi";
    }
    return sOrigTjConnSubtype ? sOrigTjConnSubtype(self, _cmd) : @"wifi";
}

static NSURLRequest *IMCleanTapjoyRequestURL(NSURLRequest *req) {
    if (!req || !req.URL) return req;
    NSString *urlStr = req.URL.absoluteString;
    if ([urlStr containsString:@"offerwall"] || [urlStr containsString:@"tapjoy"] ||
        [urlStr containsString:@"unity3d"] || [urlStr containsString:@"doubleclick"] ||
        [urlStr containsString:@"googleads"]) {
        IMPublishTapjoyURL(urlStr);
        BOOL modified = NO;
        if ([urlStr containsString:@"is_vpn=true"] || [urlStr containsString:@"is_vpn=1"]) {
            urlStr = [urlStr stringByReplacingOccurrencesOfString:@"is_vpn=true" withString:@"is_vpn=false"];
            urlStr = [urlStr stringByReplacingOccurrencesOfString:@"is_vpn=1" withString:@"is_vpn=0"];
            modified = YES;
        }
        if ([urlStr containsString:@"connection_type=vpn"] || [urlStr containsString:@"connection_type=other"]) {
            urlStr = [urlStr stringByReplacingOccurrencesOfString:@"connection_type=vpn" withString:@"connection_type=wifi"];
            urlStr = [urlStr stringByReplacingOccurrencesOfString:@"connection_type=other" withString:@"connection_type=wifi"];
            modified = YES;
        }
        if (modified) {
            NSMutableURLRequest *mreq = [req mutableCopy];
            mreq.URL = [NSURL URLWithString:urlStr];
            return mreq;
        }
    }
    return req;
}

static id (*sOrigWkLoadRequest)(id self, SEL _cmd, NSURLRequest *req);
static id IMHookWkLoadRequest(id self, SEL _cmd, NSURLRequest *req) {
    req = IMCleanTapjoyRequestURL(req);
    return sOrigWkLoadRequest ? sOrigWkLoadRequest(self, _cmd, req) : nil;
}

static void (*sOrigTjcLoadUrlReq)(id self, SEL _cmd, NSURLRequest *req, double timeout);
static void IMHookTjcLoadUrlReq(id self, SEL _cmd, NSURLRequest *req, double timeout) {
    req = IMCleanTapjoyRequestURL(req);
    if (sOrigTjcLoadUrlReq) {
        sOrigTjcLoadUrlReq(self, _cmd, req, timeout);
    }
}

static void IMHookSetCurrentHealth(void *character, int newHealth) {
    if (!character) {
        sOrigSetCurrentHealth(character, newHealth);
        return;
    }

    const int maxHealth = IMCharacterMaxHealth(character);
    const int currentHealth = IMCharacterCurrentHealth(character);
    const BOOL isPlayer = IMIsPlayerCharacter(character);

    if (isPlayer) {
        IMPublishPlayerHealth(newHealth, maxHealth);
    } else {
        IMPublishEnemyHealth(newHealth, maxHealth);
    }

    IMHealthDecision decision =
        IMResolveHealthWrite(isPlayer, currentHealth, maxHealth, newHealth);

    if (decision.suppressWrite) return;
    sOrigSetCurrentHealth(character, decision.resolvedHealth);
}

static void IMHookShowDamageMessage(void *victim,
                                    float amount,
                                    void *damageEvent,
                                    void *causer,
                                    bool isCrit,
                                    bool isLethal,
                                    bool isTrueDamage) {
    const BOOL isPlayer = IMIsPlayerCharacter(victim);
    const int currentHealth = IMCharacterCurrentHealth(victim);
    const float shown = IMResolveDisplayedDamage(isPlayer, currentHealth, amount);

    sOrigShowDamageMessage(victim, shown, damageEvent, causer,
                           isCrit, isLethal, isTrueDamage);
}

static inline BOOL IMEnergyOverrideApplies(void *character) {
    return !IMMasterOff() && IMInfiniteEnergy() && IMIsPlayerCharacter(character);
}

static bool IMHookHasEnoughFunds(void *character, int abilityType) {
    if (IMEnergyOverrideApplies(character)) return true;
    return sOrigHasEnoughFunds(character, abilityType);
}

static bool IMHookHasEnoughPower(void *character, int abilityType) {
    if (IMEnergyOverrideApplies(character)) return true;
    return sOrigHasEnoughPower(character, abilityType);
}

static bool IMHookHasEnoughEnergy(void *character, int abilityType) {
    if (IMEnergyOverrideApplies(character)) return true;
    return sOrigHasEnoughEnergy(character, abilityType);
}

static bool IMHookHasEnoughResource(void *character, int abilityType) {
    if (IMEnergyOverrideApplies(character)) return true;
    return sOrigHasEnoughResource(character, abilityType);
}

static float IMHookGetPowerPercentage(void *character, int abilityType) {
    if (IMEnergyOverrideApplies(character)) return 1.0f;
    return sOrigGetPowerPercentage(character, abilityType);
}

static float IMHookGetCurrentPower(void *character) {
    if (IMEnergyOverrideApplies(character)) return 1000000.0f;
    return sOrigGetCurrentPower(character);
}

static float IMHookGetCurrentEnergy(void *character) {
    if (IMEnergyOverrideApplies(character)) return 1000000.0f;
    return sOrigGetCurrentEnergy(character);
}

void *IMOrigRequirementStates;

void IMForceRequirementsMet(void *outArray) {
    if (!outArray || IMMasterOff() || !IMBypassRequirements()) return;
    struct IMBoolArray { unsigned char *data; int num; int max; } *array = outArray;
    if (!array->data || array->num <= 0 || array->num > 4096) return;
    for (int i = 0; i < array->num; i++) array->data[i] = 1;
}

typedef void (*IMFightClickedFn)(void *menu, bool ignoreArtifactCharges);
static IMFightClickedFn sOrigFightButtonClicked;

typedef float (*IMHealthPercentFn)(void *character);
typedef void (*IMKillCharacterFn)(void *causer, void *victim, void *instigator);

static IMHealthPercentFn  sOrigGetHealthPercentage;
static IMKillCharacterFn  sKillCharacter;
static void * volatile    sLastPlayerCharacter;
static long long volatile sLastPlayerSeenMs;

#define IM_KILL_SLOTS 8
static struct { void *target; long long ms; } sRecentKills[IM_KILL_SLOTS];

static BOOL IMKillCooldownPassed(void *target) {
    long long now = IMNowMillis();
    for (int i = 0; i < IM_KILL_SLOTS; i++) {
        if (sRecentKills[i].target == target) {
            return (now - sRecentKills[i].ms) > 1500;
        }
    }
    return YES;
}

static void IMNoteKill(void *target) {
    long long now = IMNowMillis();
    int oldest = 0;
    for (int i = 0; i < IM_KILL_SLOTS; i++) {
        if (sRecentKills[i].target == target) {
            sRecentKills[i].ms = now;
            return;
        }
        if (sRecentKills[i].ms < sRecentKills[oldest].ms) oldest = i;
    }
    sRecentKills[oldest].target = target;
    sRecentKills[oldest].ms = now;
}

static void IMResetKillHistory(void) {
    for (int i = 0; i < IM_KILL_SLOTS; i++) {
        sRecentKills[i].target = NULL;
        sRecentKills[i].ms = 0;
    }
}
static _Thread_local BOOL sInAutoFinish;

static float IMHookGetHealthPercentage(void *character) {
    if (!character || sInAutoFinish) return sOrigGetHealthPercentage(character);

    const int current = IMCharacterCurrentHealth(character);
    const int maximum = IMCharacterMaxHealth(character);
    const BOOL isPlayer = IMIsPlayerCharacter(character);

    if (maximum > 0) {
        if (isPlayer) {
            sLastPlayerCharacter = character;
            sLastPlayerSeenMs = IMNowMillis();
            IMPublishPlayerHealth(current, maximum);
        } else {
            IMPublishEnemyHealth(current, maximum);
        }
    }

    void *causer = sLastPlayerCharacter;
    if (causer && IMNowMillis() - sLastPlayerSeenMs > 200) causer = NULL;
    if (!IMMasterOff() && sKillCharacter && causer && !isPlayer &&
        maximum > 0 && current > 0 &&
        IMKillCooldownPassed(character) &&
        (IMAutoWinActive() || IMAutoCampaignShouldFinish())) {
        sInAutoFinish = YES;
        IMTraceBump(IMTraceKill);
        IMLog("kill  victim=%p causer=%p hp=%d/%d", character, causer, current, maximum);
        IMNoteKill(character);
        sKillCharacter(causer, character, causer);
        IMLog("kill  done");
        sInAutoFinish = NO;
    }

    return sOrigGetHealthPercentage(character);
}

typedef struct { uint32_t part[3]; } IMFName;
typedef void (*IMChapterInitFn)(void *menu, int32_t chapterIndex, IMFName battle);
typedef void (*IMStartCampaignBattleFn)(void *menu, IMFName battleID);
typedef IMFName (*IMCurrentBattleIdFn)(void *menu);
typedef void (*IMPreFightFn)(void *menu);

static IMChapterInitFn         sOrigChapterInit;
static IMStartCampaignBattleFn sStartCampaignBattle;
static IMStartCampaignBattleFn sGoToFightInCurrentTab;
static IMCurrentBattleIdFn     sCurrentBattleId;
static IMPreFightFn            sOrigOpponentView;
static IMPreFightFn            sPreFightStartFight;

static void * volatile sCampaignMenu;
static void * volatile sPreFightMenu;
static long long volatile sSummaryWindowSeenMs;
static long long volatile sPreFightSeenMs;
static BOOL volatile sPreFightPressArmed;
static void * volatile sSummaryWindow;
static int volatile sNavGeneration;
static IMPreFightFn sSimulateClick;
static IMFName sSummaryBattleName;
static BOOL volatile sSummaryBattleValid;
static int32_t volatile sCampaignChapter;
static IMPreFightFn sOrigSummaryShown;

static void IMHookChapterInit(void *menu, int32_t chapterIndex, IMFName battle) {
    sOrigChapterInit(menu, chapterIndex, battle);
    if (!menu) return;
    sCampaignMenu = menu;
    sCampaignChapter = chapterIndex;
    IMTraceBump(IMTraceChapterInit);
}

static void IMHookSummaryWindowShown(void *window) {
    sOrigSummaryShown(window);
    if (!window) return;

    sSummaryWindowSeenMs = IMNowMillis();
    sSummaryWindow = window;
    IMLog("summary shown window=%p gen=%d", window, sNavGeneration);
    sSummaryBattleValid = NO;

    void *data = *(void **)((uintptr_t)window + OFF_SummaryWindowData);
    if (data) {
        BOOL locked = *(unsigned char *)((uintptr_t)data + OFF_SummaryDataLocked) != 0;
        if (!locked) {
            sSummaryBattleName =
                *(IMFName *)((uintptr_t)data + OFF_SummaryDataBattleName);
            sSummaryBattleValid = YES;
        }
    }
    IMTraceBump(IMTraceSummaryShown);
}

static void IMHookPreFightOpponentView(void *menu) {
    sOrigOpponentView(menu);
    if (!menu) return;
    sNavGeneration++;
    sPreFightMenu = menu;
    sPreFightSeenMs = IMNowMillis();
    IMTraceBump(IMTracePreFightView);
    IMLog("prefight view menu=%p gen=%d armed=%d", menu, sNavGeneration, sPreFightPressArmed);

    if (IMMasterOff() || !IMAutoCampaign() || !sPreFightStartFight) return;
    if (!sPreFightPressArmed) return;
    if (IMInCombat() || IMFightStartedRecently()) return;

    const int generation = sNavGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (IMMasterOff() || !IMAutoCampaign()) return;
        if (generation != sNavGeneration) return;
        if (IMInCombat() || IMFightStartedRecently()) return;
        void *current = sPreFightMenu;
        if (!current || IMNowMillis() - sPreFightSeenMs > 4000) return;
        IMTraceBump(IMTraceFightStarted);
        sPreFightPressArmed = NO;
        IMNoteFightStarted();
        IMLog("startfight menu=%p gen=%d", current, generation);
        sPreFightStartFight(current);
        IMLog("startfight done");
    });
}

static IMPreFightFn sOrigPreFightStartFight;

static void IMHookPreFightStartFight(void *menu) {
    IMLog("game startfight menu=%p", menu);
    sNavGeneration++;
    sPreFightPressArmed = NO;
    sLastPlayerCharacter = NULL;
    sSummaryWindow = NULL;
    IMResetKillHistory();
    IMNoteFightStarted();
    sOrigPreFightStartFight(menu);
}

typedef void (*IMLadderViewFn)(void *menu, void *ladder, bool instant);
typedef void *(*IMLevelActorFn)(void *menu);
static IMLadderViewFn sOrigLadderView;
static IMLevelActorFn sOrigLevelActor;

static void IMCaptureCampaignMenu(void *menu) {
    if (!menu) return;
    sCampaignMenu = menu;
    IMTraceBump(IMTraceChapterInit);
}

static void IMHookLadderView(void *menu, void *ladder, bool instant) {
    IMCaptureCampaignMenu(menu);
    sOrigLadderView(menu, ladder, instant);
}

static void *IMHookLevelActor(void *menu) {
    IMCaptureCampaignMenu(menu);
    return sOrigLevelActor(menu);
}

static IMCurrentBattleIdFn sOrigCurrentBattleId;

static IMFName IMHookCurrentBattleId(void *menu) {
    if (menu) {
        sCampaignMenu = menu;
        IMTraceBump(IMTraceChapterInit);
    }
    return sOrigCurrentBattleId(menu);
}

typedef void (*IMResultsPopupFn)(void *popup);
static IMResultsPopupFn sOrigResultsTransitionIn;
static IMResultsPopupFn sResultsOnContinue;


static void IMScheduleSummaryClick(int tick, int generation) {
    if (tick > 8 || IMMasterOff() || !IMAutoCampaign() || !sSimulateClick) return;
    if (generation != sNavGeneration) return;

    if (!IMInCombat() && !IMFightStartedRecently()) {
        void *window = sSummaryWindow;
        if (window && IMNowMillis() - sSummaryWindowSeenMs < 3000) {
            void *button = *(void **)((uintptr_t)window + OFF_SummaryFightButton);
            if (button) {
                IMTraceBump(IMTraceSummaryPressed);
                IMLog("summary click window=%p button=%p tick=%d gen=%d",
                      window, button, tick, generation);
                sSimulateClick(button);
                IMLog("summary click done");
                return;
            }
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ IMScheduleSummaryClick(tick + 1, generation); });
}

static void IMHookResultsTransitionIn(void *popup) {
    sOrigResultsTransitionIn(popup);
    IMLog("results shown popup=%p", popup);
    IMNoteFightEnded();
    sLastPlayerCharacter = NULL;
    sPreFightPressArmed = YES;
    sNavGeneration++;
    IMScheduleSummaryClick(1, sNavGeneration);
    if (!popup || IMMasterOff() || !IMAutoCampaign() || !sResultsOnContinue) return;

    __block void *target = popup;
    const int resultsGeneration = sNavGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (IMMasterOff() || !IMAutoCampaign()) return;
        if (resultsGeneration != sNavGeneration) return;
        IMLog("results continue popup=%p", target);
        sResultsOnContinue(target);
        IMLog("results continue done");
    });
}

typedef bool (*IMTeamMeetsFn)(void *requirementData, void *team, void *context, long flags);
static IMTeamMeetsFn sOrigTeamMeetsRequirements;

static bool IMHookTeamMeetsRequirements(void *requirementData, void *team,
                                        void *context, long flags) {
    if (!IMMasterOff() && IMBypassRequirements()) return true;
    return sOrigTeamMeetsRequirements(requirementData, team, context, flags);
}

typedef void (*IMStartChallengeRespFn)(void *response);
static IMStartChallengeRespFn sOrigStartChallengeResp;

static void IMHookStartChallengeBattleResponse(void *response) {
    if (response && !IMMasterOff() && IMBypassRequirements()) {
        *(bool *)((uintptr_t)response + 0x00) = true; // Force bAllowedToStart = true
    }
    if (sOrigStartChallengeResp) {
        sOrigStartChallengeResp(response);
    }
}

typedef void (*IMRequirementsResultFn)(void *context, void *resultFlag);
static IMRequirementsResultFn sOrigRequirementsResult;

static void IMHookRequirementsResult(void *context, void *resultFlag) {
    if (resultFlag && !IMMasterOff() && IMBypassRequirements()) {
        *(unsigned char *)resultFlag = 1;
    }
    sOrigRequirementsResult(context, resultFlag);
}

static void IMHookFightButtonClicked(void *menu, bool ignoreArtifactCharges) {
    if (menu && !IMMasterOff() && IMBypassRequirements()) {
        *(unsigned char *)((uintptr_t)menu + OFF_RequirementsUnmet) = 0;
    }
    sOrigFightButtonClicked(menu, ignoreArtifactCharges);
}

__attribute__((naked)) static void IMHookRequirementStates(void) {
    __asm__ volatile(
        "stp  x29, x30, [sp, #-32]!                          \n"
        "mov  x29, sp                                        \n"
        "str  x8, [sp, #16]                                  \n"
        "adrp x9, _IMOrigRequirementStates@PAGE              \n"
        "add  x9, x9, _IMOrigRequirementStates@PAGEOFF       \n"
        "ldr  x9, [x9]                                       \n"
        "blr  x9                                             \n"
        "ldr  x0, [sp, #16]                                  \n"
        "bl   _IMForceRequirementsMet                        \n"
        "ldp  x29, x30, [sp], #32                            \n"
        "ret                                                 \n"
    );
}

static bool IMHookIsStunned(void *character, int stunType) {
    if (!IMMasterOff() && IMFreezeAI() && character && !IMIsPlayerCharacter(character)) {
        return true;
    }
    return sOrigIsStunned(character, stunType);
}

BOOL IMHooksInstall(void) {
    if (sInstalled) return YES;

    MSHookFunction(IMRuntimeAddress(RVA_SetCurrentHealth),
                   (void *)IMHookSetCurrentHealth,
                   (void **)&sOrigSetCurrentHealth);

    MSHookFunction(IMRuntimeAddress(RVA_ShowDamageMessage),
                   (void *)IMHookShowDamageMessage,
                   (void **)&sOrigShowDamageMessage);

    MSHookFunction(IMRuntimeAddress(RVA_HasEnoughFunds),
                   (void *)IMHookHasEnoughFunds, (void **)&sOrigHasEnoughFunds);
    MSHookFunction(IMRuntimeAddress(RVA_HasEnoughPower),
                   (void *)IMHookHasEnoughPower, (void **)&sOrigHasEnoughPower);
    MSHookFunction(IMRuntimeAddress(RVA_HasEnoughEnergy),
                   (void *)IMHookHasEnoughEnergy, (void **)&sOrigHasEnoughEnergy);
    MSHookFunction(IMRuntimeAddress(RVA_HasEnoughResource),
                   (void *)IMHookHasEnoughResource, (void **)&sOrigHasEnoughResource);
    sKillCharacter = (IMKillCharacterFn)IMRuntimeAddress(RVA_KillCharacter);
    sSimulateClick = (IMPreFightFn)IMRuntimeAddress(RVA_SimulateClick);
    MSHookFunction(IMRuntimeAddress(RVA_GetHealthPercentage),
                   (void *)IMHookGetHealthPercentage,
                   (void **)&sOrigGetHealthPercentage);

    sStartCampaignBattle =
        (IMStartCampaignBattleFn)IMRuntimeAddress(RVA_CampaignStartBattle);
    MSHookFunction(IMRuntimeAddress(RVA_CampaignLadderView),
                   (void *)IMHookLadderView, (void **)&sOrigLadderView);
    MSHookFunction(IMRuntimeAddress(RVA_CampaignLevelActor),
                   (void *)IMHookLevelActor, (void **)&sOrigLevelActor);
    MSHookFunction(IMRuntimeAddress(RVA_CampaignCurrentBattleId),
                   (void *)IMHookCurrentBattleId, (void **)&sOrigCurrentBattleId);
    sCurrentBattleId = sOrigCurrentBattleId;
    sGoToFightInCurrentTab =
        (IMStartCampaignBattleFn)IMRuntimeAddress(RVA_CampaignGoToFight);
    MSHookFunction(IMRuntimeAddress(RVA_CampaignChapterInit),
                   (void *)IMHookChapterInit, (void **)&sOrigChapterInit);

    MSHookFunction(IMRuntimeAddress(RVA_SummaryWindowShown),
                   (void *)IMHookSummaryWindowShown, (void **)&sOrigSummaryShown);

    MSHookFunction(IMRuntimeAddress(RVA_PreFightStartFight),
                   (void *)IMHookPreFightStartFight,
                   (void **)&sOrigPreFightStartFight);
    sPreFightStartFight = sOrigPreFightStartFight;
    MSHookFunction(IMRuntimeAddress(RVA_PreFightOpponentView),
                   (void *)IMHookPreFightOpponentView, (void **)&sOrigOpponentView);

    sResultsOnContinue = (IMResultsPopupFn)IMRuntimeAddress(RVA_ResultsOnContinue);
    MSHookFunction(IMRuntimeAddress(RVA_ResultsTransitionIn),
                   (void *)IMHookResultsTransitionIn,
                   (void **)&sOrigResultsTransitionIn);
    MSHookFunction(IMRuntimeAddress(RVA_TeamMeetsRequirements),
                   (void *)IMHookTeamMeetsRequirements,
                   (void **)&sOrigTeamMeetsRequirements);
    MSHookFunction(IMRuntimeAddress(RVA_BattleRequirementStates),
                   (void *)IMHookRequirementStates, &IMOrigRequirementStates);
    MSHookFunction(IMRuntimeAddress(RVA_OnFightButtonClicked),
                   (void *)IMHookFightButtonClicked, (void **)&sOrigFightButtonClicked);
    MSHookFunction(IMRuntimeAddress(RVA_RequirementsResult),
                   (void *)IMHookRequirementsResult, (void **)&sOrigRequirementsResult);
    MSHookFunction(IMRuntimeAddress(RVA_IsStunned),
                   (void *)IMHookIsStunned, (void **)&sOrigIsStunned);
    MSHookFunction(IMRuntimeAddress(RVA_GetPowerPercentage),
                   (void *)IMHookGetPowerPercentage, (void **)&sOrigGetPowerPercentage);
    MSHookFunction(IMRuntimeAddress(RVA_GetCurrentPower),
                   (void *)IMHookGetCurrentPower, (void **)&sOrigGetCurrentPower);
    MSHookFunction(IMRuntimeAddress(RVA_GetCurrentEnergy),
                   (void *)IMHookGetCurrentEnergy, (void **)&sOrigGetCurrentEnergy);

    // System VPN / Proxy bypass hooks
    MSHookFunction((void *)CFNetworkCopySystemProxySettings,
                   (void *)IMHookCFNetworkCopySystemProxySettings,
                   (void **)&sOrigCFNetworkCopySystemProxySettings);

    MSHookFunction((void *)getifaddrs,
                   (void *)IMHookGetifaddrs,
                   (void **)&sOrigGetifaddrs);

    MSHookFunction((void *)SCNetworkReachabilityGetFlags,
                   (void *)IMHookSCNetworkReachabilityGetFlags,
                   (void **)&sOrigSCNetworkReachabilityGetFlags);

    MSHookFunction((void *)sysctl,
                   (void *)IMHookSysctl,
                   (void **)&sOrigSysctl);

    Class neClass = NSClassFromString(@"NEVPNConnection");
    if (neClass) {
        MSHookMessageEx(neClass, @selector(status), (IMP)IMHookNEVPNConnectionStatus, (IMP *)&sOrigNEVPNConnectionStatus);
    }

    Class wkClass = NSClassFromString(@"WKWebView");
    if (wkClass) {
        MSHookMessageEx(wkClass, @selector(loadRequest:), (IMP)IMHookWkLoadRequest, (IMP *)&sOrigWkLoadRequest);
    }

    Class tjcPageClass = NSClassFromString(@"TJCUIWebPageView");
    if (tjcPageClass) {
        MSHookMessageEx(tjcPageClass, @selector(loadURLRequest:withTimeOutInterval:), (IMP)IMHookTjcLoadUrlReq, (IMP *)&sOrigTjcLoadUrlReq);
    }

    Class tjReach = NSClassFromString(@"TJCNetReachability");
    if (tjReach) {
        Class metaCls = object_getClass(tjReach);
        if (metaCls) {
            MSHookMessageEx(metaCls, @selector(connectionType), (IMP)IMHookTjConnType, (IMP *)&sOrigTjConnType);
            MSHookMessageEx(metaCls, @selector(connectionSubtype), (IMP)IMHookTjConnSubtype, (IMP *)&sOrigTjConnSubtype);
        }
    }

    sInstalled = (sOrigSetCurrentHealth != NULL && sOrigShowDamageMessage != NULL);

    NSLog(@"[IMMod] hooks %@ base %p slide 0x%lx",
          sInstalled ? @"installed" : @"FAILED",
          IMRuntimeImageBase(), (unsigned long)IMRuntimeSlide());

    return sInstalled;
}

BOOL IMHooksInstalled(void) { return sInstalled; }

