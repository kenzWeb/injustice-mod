#import "IMHooks.h"
#import "IMRuntime.h"
#import "IMSettings.h"
#import "IMDamage.h"
#import "Offsets.h"
#import <substrate.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <CFNetwork/CFNetwork.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

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
                }
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

static id (*sOrigWkLoadRequest)(id self, SEL _cmd, NSURLRequest *req);
static id IMHookWkLoadRequest(id self, SEL _cmd, NSURLRequest *req) {
    if ([req isKindOfClass:NSURLRequest.class] && req.URL.absoluteString.length > 0) {
        IMPublishTapjoyURL(req.URL.absoluteString);
    }
    return sOrigWkLoadRequest ? sOrigWkLoadRequest(self, _cmd, req) : nil;
}

static void (*sOrigTjcLoadUrlReq)(id self, SEL _cmd, NSURLRequest *req, double timeout);
static void IMHookTjcLoadUrlReq(id self, SEL _cmd, NSURLRequest *req, double timeout) {
    if ([req isKindOfClass:NSURLRequest.class] && req.URL.absoluteString.length > 0) {
        IMPublishTapjoyURL(req.URL.absoluteString);
    }
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

typedef bool (*IMTeamMeetsFn)(void *requirementData, void *team, void *context, long flags);
static IMTeamMeetsFn sOrigTeamMeetsRequirements;

static bool IMHookTeamMeetsRequirements(void *requirementData, void *team,
                                        void *context, long flags) {
    if (!IMMasterOff() && IMBypassRequirements()) return true;
    return sOrigTeamMeetsRequirements(requirementData, team, context, flags);
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

    sInstalled = (sOrigSetCurrentHealth != NULL && sOrigShowDamageMessage != NULL);

    NSLog(@"[IMMod] hooks %@ base %p slide 0x%lx",
          sInstalled ? @"installed" : @"FAILED",
          IMRuntimeImageBase(), (unsigned long)IMRuntimeSlide());

    return sInstalled;
}

BOOL IMHooksInstalled(void) { return sInstalled; }
