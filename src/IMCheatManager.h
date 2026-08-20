#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Constructs (once, cached) a real UFrontendCheatManager via the game's own
// APlayerController::EnableCheats, then invokes the ClaimSoloRaidBossRewards
// UFUNCTION through UObject::ProcessEvent — the ABI-safe path.
//
// Returns YES if the cheat manager was constructed and ProcessEvent was called
// (this does NOT mean the server granted rewards — that is exactly what the
// on-device test observes). NO means construction failed (see log for stage).
BOOL IMCheatClaimSoloRaidBoss(int difficultyIndex, int levelIndex, int bossIndex);

// Refresh solo-raid attempts (pips) by simulating an IronSource rewarded-video
// completion — reuses the constructed UFrontendCheatManager and hand-calls the
// no-arg cheat impl. TEST: does the server grant pips for the resulting request?
void IMCheatRefreshSoloRaidPips(void);

// Diagnostic: force (re)construction and report which stage reached, for the
// test build. Fills nothing; logs via IMLog. Returns the manager pointer or NULL.
void *IMCheatEnsureManager(void);

// Called from game-thread hooks with a live world-context UObject (a menu/window).
// We cannot use GetSoloRaidManager for this — it dereferences a null global when
// no raid is active and crashes. A captured live menu is always safe.
void IMCheatNoteWorldContext(void *ctx);

#ifdef __cplusplus
}
#endif
