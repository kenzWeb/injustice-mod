#import "IMHooks.h"
#import "IMRuntime.h"
#import "IMSettings.h"
#import "IMDamage.h"
#import "Offsets.h"
#import <substrate.h>

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
static IMPowerPercentFn      sOrigGetPowerPercentage;
static IMCurrentResourceFn   sOrigGetCurrentPower;
static IMCurrentResourceFn   sOrigGetCurrentEnergy;
static BOOL sInstalled;

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
    MSHookFunction(IMRuntimeAddress(RVA_GetPowerPercentage),
                   (void *)IMHookGetPowerPercentage, (void **)&sOrigGetPowerPercentage);
    MSHookFunction(IMRuntimeAddress(RVA_GetCurrentPower),
                   (void *)IMHookGetCurrentPower, (void **)&sOrigGetCurrentPower);
    MSHookFunction(IMRuntimeAddress(RVA_GetCurrentEnergy),
                   (void *)IMHookGetCurrentEnergy, (void **)&sOrigGetCurrentEnergy);

    sInstalled = (sOrigSetCurrentHealth != NULL && sOrigShowDamageMessage != NULL);

    NSLog(@"[IMMod] hooks %@ base %p slide 0x%lx",
          sInstalled ? @"installed" : @"FAILED",
          IMRuntimeImageBase(), (unsigned long)IMRuntimeSlide());

    return sInstalled;
}

BOOL IMHooksInstalled(void) { return sInstalled; }
