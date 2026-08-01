#import "IMDamage.h"
#import "IMSettings.h"
#import <math.h>

static inline int IMClampHealth(long long value, int maxHealth) {
    long long hi = maxHealth > 0 ? (long long)maxHealth : value;
    if (value < 0) value = 0;
    if (value > hi) value = hi;
    return (int)value;
}

static long long IMScaledLoss(int delta, double multiplier) {
    double scaled = (double)delta * multiplier;
    if (scaled > (double)INT64_MAX) return INT64_MAX;
    return (long long)llround(scaled);
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
        } else if (delta > 0) {
            resolved = IMGodMode()
                ? maxHealth
                : (long long)currentHealth - IMScaledLoss(delta, IMDefenseMultiplier());
        }
    } else if (IMAutoWinActive()) {
        resolved = 0;
    } else if (delta > 0) {
        if (IMOneHitKill()) {
            resolved = 0;
        } else if (IMFixedDamageEnabled()) {
            resolved = (long long)currentHealth - IMFixedDamage();
        } else {
            resolved = (long long)currentHealth - IMScaledLoss(delta, IMDamageMultiplier());
        }
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
        shown = IMGodMode() ? 0.0 : rawAmount * IMDefenseMultiplier();
    } else if (IMOneHitKill()) {
        shown = victimCurrentHealth;
    } else if (IMFixedDamageEnabled()) {
        shown = (double)IMFixedDamage();
    } else {
        shown = rawAmount * IMDamageMultiplier();
    }

    if (shown < 0.0) shown = 0.0;
    if (victimCurrentHealth > 0 && shown > victimCurrentHealth) shown = victimCurrentHealth;
    return (float)shown;
}
