#import "IMCheatManager.h"
#import "IMRuntime.h"
#import "IMLog.h"
#import "Offsets.h"
#import <stdint.h>

// This build uses case-preserving FName: 12 bytes {ComparisonIndex, DisplayIndex, Number}.
typedef struct { uint32_t part[3]; } IMUEName;

typedef void  *(*IMStaticClassFn)(void);
typedef void  *(*IMGetPCFn)(void *worldCtx, int32_t playerIndex);
typedef void  *(*IMGetMgrFn)(void);
typedef void   (*IMFNameCtorFn)(IMUEName *out, const char *str, int findType);
typedef void   (*IMEnableCheatsFn)(void *pc);
typedef void  *(*IMFindFunctionFn)(void *obj, IMUEName name);
typedef void   (*IMProcessEventFn)(void *obj, void *func, void *params);

static void * volatile sCheatManager;

static inline void *IMVSlot(void *obj, uintptr_t byteOffset) {
    // obj -> vtable -> *(vtable + byteOffset)
    void **vtable = *(void ***)obj;
    return vtable[byteOffset / sizeof(void *)];
}

// A context-free live UObject to seed GetPlayerController's world context.
// The solo-raid manager is a subsystem-style UObject reachable without args.
static void *IMWorldContext(void) {
    IMGetMgrFn get = (IMGetMgrFn)IMRuntimeAddress(RVA_GetSoloRaidManager);
    return get ? get() : NULL;
}

void *IMCheatEnsureManager(void) {
    void *cached = sCheatManager;
    if (cached) return cached;

    void *ctx = IMWorldContext();
    if (!ctx) { IMLog("cheatmgr: no world context (open a solo-raid screen once)"); return NULL; }

    IMGetPCFn getPC = (IMGetPCFn)IMRuntimeAddress(RVA_GetPlayerController);
    void *pc = getPC ? getPC(ctx, 0) : NULL;
    if (!pc) { IMLog("cheatmgr: GetPlayerController returned null"); return NULL; }
    IMLog("cheatmgr: pc=%p", pc);

    // If a manager already exists, reuse it.
    void *existing = *(void **)((uintptr_t)pc + OFF_PCCheatManager);
    if (existing) {
        IMLog("cheatmgr: reusing existing pc->CheatManager=%p", existing);
        sCheatManager = existing;
        return existing;
    }

    IMStaticClassFn staticClass =
        (IMStaticClassFn)IMRuntimeAddress(RVA_FrontendCheatMgrStaticClass);
    void *cls = staticClass ? staticClass() : NULL;
    if (!cls) { IMLog("cheatmgr: StaticClass null"); return NULL; }

    // pc->CheatClass = UFrontendCheatManager::StaticClass()
    *(void **)((uintptr_t)pc + OFF_PCCheatClass) = cls;

    // pc->EnableCheats() — the engine constructs & inits the manager with pc as Outer.
    IMEnableCheatsFn enableCheats = (IMEnableCheatsFn)IMVSlot(pc, VT_EnableCheats);
    IMLog("cheatmgr: calling EnableCheats fn=%p cls=%p", (void *)enableCheats, cls);
    enableCheats(pc);

    void *mgr = *(void **)((uintptr_t)pc + OFF_PCCheatManager);
    IMLog("cheatmgr: pc->CheatManager after EnableCheats=%p", mgr);
    sCheatManager = mgr;
    return mgr;
}

static void *IMFindUFunction(void *obj, const char *name) {
    IMFNameCtorFn nameCtor = (IMFNameCtorFn)IMRuntimeAddress(RVA_FNameCtor);
    if (!nameCtor) return NULL;
    IMUEName fn = {{0, 0, 0}};
    nameCtor(&fn, name, 1 /* FNAME_Add: returns existing if present */);

    IMFindFunctionFn find = (IMFindFunctionFn)IMVSlot(obj, VT_FindFunction);
    void *func = find(obj, fn);
    IMLog("cheatmgr: FindFunction(%s) idx=%u -> %p", name, fn.part[0], func);
    return func;
}

BOOL IMCheatClaimSoloRaidBoss(int difficultyIndex, int levelIndex, int bossIndex) {
    // Negative => pull the last-seen battle coordinates from the solo-raid manager.
    if (difficultyIndex < 0 || levelIndex < 0 || bossIndex < 0) {
        void *srm = IMWorldContext();
        if (srm) {
            difficultyIndex = *(int32_t *)((uintptr_t)srm + OFF_MgrCachedDifficulty);
            levelIndex      = *(int32_t *)((uintptr_t)srm + OFF_MgrCachedLevel);
            bossIndex       = *(int32_t *)((uintptr_t)srm + OFF_MgrCachedBattleIndex);
            IMLog("cheatmgr: cached battle diff=%d level=%d boss=%d",
                  difficultyIndex, levelIndex, bossIndex);
        }
    }

    void *mgr = IMCheatEnsureManager();
    if (!mgr) return NO;

    void *func = IMFindUFunction(mgr, "ClaimSoloRaidBossRewards");
    if (!func) { IMLog("cheatmgr: UFunction not found"); return NO; }

    // UFUNCTION param layout: { int32 difficultyIndex; int32 levelIndex; int32 bossIndex; }
    struct { int32_t diff; int32_t level; int32_t boss; } params = {
        (int32_t)difficultyIndex, (int32_t)levelIndex, (int32_t)bossIndex
    };

    IMProcessEventFn pe = (IMProcessEventFn)IMVSlot(mgr, VT_ProcessEvent);
    IMLog("cheatmgr: ProcessEvent mgr=%p func=%p diff=%d level=%d boss=%d",
          mgr, func, difficultyIndex, levelIndex, bossIndex);
    pe(mgr, func, &params);
    IMLog("cheatmgr: ProcessEvent returned");
    return YES;
}
