#import "IMCheatManager.h"
#import "IMRuntime.h"
#import "IMLog.h"
#import "Offsets.h"
#import <stdint.h>
#import <dispatch/dispatch.h>

// This build uses case-preserving FName: 12 bytes {ComparisonIndex, DisplayIndex, Number}.
typedef struct { uint32_t part[3]; } IMUEName;

typedef void  *(*IMStaticClassFn)(void);
typedef void  *(*IMGetPCFn)(void *worldCtx, int32_t playerIndex);
typedef void   (*IMFNameCtorFn)(IMUEName *out, const char *str, int findType);
typedef void   (*IMEnableCheatsFn)(void *pc);
typedef void  *(*IMFindFunctionFn)(void *obj, IMUEName name);
typedef void   (*IMProcessEventFn)(void *obj, void *func, void *params);

static void * volatile sCheatManager;
static void * volatile sCachedPC;
static void * volatile sWorldCtx;   // freshest live UObject captured by game hooks

static inline void *IMVSlot(void *obj, uintptr_t byteOffset) {
    // obj -> vtable -> *(vtable + byteOffset)
    void **vtable = *(void ***)obj;
    return vtable[byteOffset / sizeof(void *)];
}

void IMCheatNoteWorldContext(void *ctx) {
    if (ctx) sWorldCtx = ctx;
}

// A live world-context UObject captured on the game thread (a menu/window).
static void *IMWorldContext(void) {
    return sWorldCtx;
}

void *IMCheatEnsureManager(void) {
    void *cached = sCheatManager;
    if (cached) { IMLog("cheatmgr: cached mgr=%p", cached); return cached; }

    void *pc = sCachedPC;
    if (!pc) {
        void *ctx = IMWorldContext();
        if (!ctx) { IMLog("cheatmgr: no world context (navigate a game menu once)"); return NULL; }

        IMGetPCFn getPC = (IMGetPCFn)IMRuntimeAddress(RVA_GetPlayerController);
        IMLog("cheatmgr: calling GetPlayerController ctx=%p fn=%p", ctx, (void *)getPC);
        pc = getPC ? getPC(ctx, 0) : NULL;
        if (!pc) { IMLog("cheatmgr: GetPlayerController returned null"); return NULL; }
        sCachedPC = pc;
    }
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
    IMLog("cheatmgr: calling StaticClass fn=%p", (void *)staticClass);
    void *cls = staticClass ? staticClass() : NULL;
    if (!cls) { IMLog("cheatmgr: StaticClass null"); return NULL; }
    IMLog("cheatmgr: cls=%p", cls);

    // pc->CheatClass = UFrontendCheatManager::StaticClass()
    *(void **)((uintptr_t)pc + OFF_PCCheatClass) = cls;

    // pc->EnableCheats() — the engine constructs & inits the manager with pc as Outer.
    IMEnableCheatsFn enableCheats = (IMEnableCheatsFn)IMVSlot(pc, VT_EnableCheats);
    IMLog("cheatmgr: calling EnableCheats fn=%p", (void *)enableCheats);
    enableCheats(pc);
    IMLog("cheatmgr: EnableCheats returned");

    void *mgr = *(void **)((uintptr_t)pc + OFF_PCCheatManager);
    IMLog("cheatmgr: pc->CheatManager after EnableCheats=%p", mgr);
    sCheatManager = mgr;
    return mgr;
}

static void *IMFindUFunction(void *obj, const char *name) {
    IMFNameCtorFn nameCtor = (IMFNameCtorFn)IMRuntimeAddress(RVA_FNameCtor);
    if (!nameCtor) return NULL;
    IMUEName fn = {{0, 0, 0}};
    IMLog("cheatmgr: FName ctor fn=%p name=%s", (void *)nameCtor, name);
    nameCtor(&fn, name, 1 /* FNAME_Add: returns existing if present */);
    IMLog("cheatmgr: FName -> idx=%u disp=%u num=%u", fn.part[0], fn.part[1], fn.part[2]);

    IMFindFunctionFn find = (IMFindFunctionFn)IMVSlot(obj, VT_FindFunction);
    IMLog("cheatmgr: FindFunction fn=%p obj=%p", (void *)find, obj);
    void *func = find(obj, fn);
    IMLog("cheatmgr: FindFunction(%s) -> %p", name, func);
    return func;
}

// Runs on the main (game) queue — never straight from the UIKit touch handler,
// so the engine is at a clean point when we construct objects / ProcessEvent.
static void IMCheatClaimWork(int difficultyIndex, int levelIndex, int bossIndex) {
    // Negative indices default to 0 for this diagnostic run (we can no longer
    // read them from the solo-raid manager — that getter crashes off-raid).
    if (difficultyIndex < 0) difficultyIndex = 0;
    if (levelIndex < 0)      levelIndex = 0;
    if (bossIndex < 0)       bossIndex = 0;
    IMLog("cheatmgr: === claim work begin (diff=%d level=%d boss=%d) ===",
          difficultyIndex, levelIndex, bossIndex);

    void *mgr = IMCheatEnsureManager();
    if (!mgr) { IMLog("cheatmgr: abort — no manager"); return; }

    void *func = IMFindUFunction(mgr, "ClaimSoloRaidBossRewards");
    if (!func) { IMLog("cheatmgr: abort — UFunction not found"); return; }

    // UFUNCTION param layout: { int32 difficultyIndex; int32 levelIndex; int32 bossIndex; }
    struct { int32_t diff; int32_t level; int32_t boss; } params = {
        (int32_t)difficultyIndex, (int32_t)levelIndex, (int32_t)bossIndex
    };

    IMProcessEventFn pe = (IMProcessEventFn)IMVSlot(mgr, VT_ProcessEvent);
    IMLog("cheatmgr: ProcessEvent pe=%p mgr=%p func=%p", (void *)pe, mgr, func);
    pe(mgr, func, &params);
    IMLog("cheatmgr: === ProcessEvent returned OK ===");
}

BOOL IMCheatClaimSoloRaidBoss(int difficultyIndex, int levelIndex, int bossIndex) {
    // Defer the engine work onto the main/game queue (the same context the
    // auto-farm uses to call game functions). Calling these directly from the
    // UIKit touch handler re-enters the engine mid-event and crashes.
    IMLog("cheatmgr: claim requested (queued) diff=%d level=%d boss=%d",
          difficultyIndex, levelIndex, bossIndex);
    dispatch_async(dispatch_get_main_queue(), ^{
        IMCheatClaimWork(difficultyIndex, levelIndex, bossIndex);
    });
    return YES;  // "queued" — real outcome is in the log
}
