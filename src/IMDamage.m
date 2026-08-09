#import "IMDamage.h"
#import "IMSettings.h"
#import <math.h>

static inline int IMClampHealth(long long value, int maxHealth) {
    long long hi = maxHealth > 0 ? (long long)maxHealth : value;
    if (value < 0) value = 0;
    if (value > hi) value = hi;
    return (int)value;
}

IMHealthDecision IMResolveHealthWrite(BOOL victimIsPlayer,
                                      int currentHealth,
                                      int maxHealth,
                                      int requestedHealth) {
    IMHealthDecision decision;
    decision.suppressWrite = NO;
    decision.resolvedHealth = requestedHealth;

    if (IMMasterOff()) return decision;

    if (IMFreezeAll()) {
        decision.suppressWrite = YES;
        return decision;
    }

    const int delta = currentHealth - requestedHealth;
    long long resolved = requestedHealth;

    if (victimIsPlayer) {
        if (IMConsumeHealRequest()) {
            resolved = maxHealth;
        } else if (delta > 0 && IMGodMode()) {
            resolved = maxHealth;
        }
    } else if (IMAutoWinActive() || IMAutoCampaignShouldFinish()) {
        resolved = 0;
    } else if (delta > 0 && IMOneHitKill()) {
        resolved = 0;
    }

    decision.resolvedHealth = IMClampHealth(resolved, maxHealth);
    return decision;
}

float IMResolveDisplayedDamage(BOOL victimIsPlayer,
                               int victimCurrentHealth,
                               float rawAmount) {
    if (IMMasterOff()) return rawAmount;
    if (IMFreezeAll()) return 0.0f;

    double shown = rawAmount;

    if (victimIsPlayer) {
        shown = IMGodMode() ? 0.0 : rawAmount;
    } else if (IMOneHitKill()) {
        shown = victimCurrentHealth;
    } else {
        shown = rawAmount;
    }

    if (shown < 0.0) shown = 0.0;
    if (victimCurrentHealth > 0 && shown > victimCurrentHealth) shown = victimCurrentHealth;
    return (float)shown;
}
