#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    BOOL suppressWrite;
    int  resolvedHealth;
} IMHealthDecision;

IMHealthDecision IMResolveHealthWrite(BOOL victimIsPlayer,
                                      int currentHealth,
                                      int maxHealth,
                                      int requestedHealth);

float IMResolveDisplayedDamage(BOOL victimIsPlayer,
                               int victimCurrentHealth,
                               float rawAmount);
