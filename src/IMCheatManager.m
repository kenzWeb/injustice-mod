#import "IMCheatManager.h"
#import "IMRuntime.h"
#import "IMLog.h"
#import "Offsets.h"
#import <stdint.h>
#import <dispatch/dispatch.h>
#import <mach/mach.h>

// Safe memory read: returns NO for unmapped pages instead of crashing.
static BOOL IMSafeRead(const void *addr, void *buf, size_t n) {
    vm_size_t got = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)addr,
                                         (vm_size_t)n, (vm_address_t)buf, &got);
    return kr == KERN_SUCCESS && got == n;
}

// This build uses case-preserving FName: 12 bytes {ComparisonIndex, DisplayIndex, Number}.
typedef struct { uint32_t part[3]; } IMUEName;

typedef void  *(*IMStaticClassFn)(void);
typedef void  *(*IMGetPCFn)(void *worldCtx, int32_t playerIndex);
typedef void   (*IMFNameCtorFn)(IMUEName *out, const uint16_t *str, int findType);
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

// Called from game-thread hooks. Eagerly resolves and caches the (persistent)
// PlayerController the first time any live UObject is seen, so a later button
// press works from any screen — even one the tweak does not hook.
void IMCheatNoteWorldContext(void *ctx) {
    if (!ctx) return;
    sWorldCtx = ctx;
    if (sCachedPC) return;
    IMGetPCFn getPC = (IMGetPCFn)IMRuntimeAddress(RVA_GetPlayerController);
    void *pc = getPC ? getPC(ctx, 0) : NULL;
    if (pc) {
        sCachedPC = pc;
        IMLog("cheatmgr: PlayerController captured=%p (ctx=%p)", pc, ctx);
    }
}

// A live world-context UObject captured on the game thread (a menu/window).
static void *IMWorldContext(void) {
    return sWorldCtx;
}

static void *IMFindUFunction(void *obj, const char *name);

// Does `mgr` actually expose ClaimSoloRaidBossRewards? (i.e. is it a
// UFrontendCheatManager and not the base UBaseCheatManager the game ships.)
static BOOL IMManagerHasClaim(void *mgr) {
    if (!IMLooksLikeObject(mgr)) return NO;
    return IMFindUFunction(mgr, "ClaimSoloRaidBossRewards") != NULL;
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
    if (!IMLooksLikeObject(pc)) { IMLog("cheatmgr: pc=%p invalid vtable, abort", pc); return NULL; }
    IMLog("cheatmgr: pc=%p", pc);

    // Reuse an existing manager ONLY if it is a valid object that actually has
    // ClaimSoloRaidBossRewards. The game ships a base UBaseCheatManager which
    // does NOT, and the field can also hold garbage — both must be rejected.
    void *existing = *(void **)((uintptr_t)pc + OFF_PCCheatManager);
    IMLog("cheatmgr: existing pc->CheatManager=%p valid=%d", existing, IMLooksLikeObject(existing));
    if (IMLooksLikeObject(existing)) {
        // DIAGNOSTIC: is FindFunction itself working? CheatHelp exists on the
        // base UBaseCheatManager, so it MUST resolve if the mechanism is sound.
        void *ecls = *(void **)((uintptr_t)existing + OFF_UObjectClass);
        void *help = IMFindUFunction(existing, "CheatHelp");
        IMLog("cheatmgr: DIAG existing class=%p  CheatHelp=%p (mechanism ok if non-null)",
              ecls, help);
    }
    if (IMManagerHasClaim(existing)) {
        IMLog("cheatmgr: reusing valid frontend manager=%p", existing);
        sCheatManager = existing;
        return existing;
    }

    // Force-construct a UFrontendCheatManager: set the class, clear the slot,
    // let EnableCheats (which the game already uses — cheats are live here) build it.
    IMStaticClassFn staticClass =
        (IMStaticClassFn)IMRuntimeAddress(RVA_FrontendCheatMgrStaticClass);
    void *cls = staticClass ? staticClass() : NULL;
    if (!cls) { IMLog("cheatmgr: StaticClass null"); return NULL; }
    IMLog("cheatmgr: frontend cls=%p", cls);

    *(void **)((uintptr_t)pc + OFF_PCCheatClass)   = cls;
    *(void **)((uintptr_t)pc + OFF_PCCheatManager) = NULL;  // force EnableCheats to recreate

    IMEnableCheatsFn enableCheats = (IMEnableCheatsFn)IMVSlot(pc, VT_EnableCheats);
    IMLog("cheatmgr: calling EnableCheats fn=%p", (void *)enableCheats);
    enableCheats(pc);
    IMLog("cheatmgr: EnableCheats returned");

    void *mgr = *(void **)((uintptr_t)pc + OFF_PCCheatManager);
    IMLog("cheatmgr: pc->CheatManager after EnableCheats=%p valid=%d", mgr, IMLooksLikeObject(mgr));
    if (!IMLooksLikeObject(mgr)) { IMLog("cheatmgr: construction failed"); return NULL; }
    // DIAGNOSTIC: did EnableCheats honour our CheatClass, or hardcode the base?
    void *mcls = *(void **)((uintptr_t)mgr + OFF_UObjectClass);
    IMLog("cheatmgr: DIAG new mgr class=%p  frontendCls=%p  match=%d",
          mcls, cls, mcls == cls);
    sCheatManager = mgr;
    return mgr;
}

static void *IMFindUFunction(void *obj, const char *name) {
    IMFNameCtorFn nameCtor = (IMFNameCtorFn)IMRuntimeAddress(RVA_FNameCtor);
    if (!nameCtor) return NULL;

    // The FName ctor takes a UTF-16 (TCHAR) string, not UTF-8. ASCII names widen
    // trivially (high byte 0). Passing char* produced a wrong hash -> wrong FName
    // -> FindFunction never matched (even CheatHelp failed).
    uint16_t wide[96];
    int i = 0;
    for (; name[i] && i < 95; i++) wide[i] = (uint16_t)(unsigned char)name[i];
    wide[i] = 0;

    IMUEName fn = {{0, 0, 0}};
    IMLog("cheatmgr: FName ctor fn=%p name=%s (utf16)", (void *)nameCtor, name);
    nameCtor(&fn, wide, 1 /* FNAME_Add: returns existing if present */);
    IMLog("cheatmgr: FName -> idx=%u disp=%u num=%u", fn.part[0], fn.part[1], fn.part[2]);

    IMFindFunctionFn find = (IMFindFunctionFn)IMVSlot(obj, VT_FindFunction);
    IMLog("cheatmgr: FindFunction fn=%p obj=%p", (void *)find, obj);
    void *func = find(obj, fn);
    IMLog("cheatmgr: FindFunction(%s) -> %p", name, func);
    return func;
}

// Diagnostic: dump the class object's pointer-sized fields so we can locate the
// Children (UField* linked list) offset from real memory instead of guessing.
// Cheap "looks like a pointer" WITHOUT dereferencing (deref of a canonical but
// unmapped value crashes). Just a canonical + plausible-range check.
static inline int IMLooksLikePtr(void *v) {
    uintptr_t p = (uintptr_t)v;
    return p >= 0x100000000ULL && p < 0x0000300000000000ULL;
}

static void IMDumpClassLayout(void *cls) {
    if (!IMLooksLikeObject(cls)) { IMLog("cheatmgr: DUMP class invalid %p", cls); return; }
    IMLog("cheatmgr: DUMP obj=%p fields (off: value ptr?):", cls);
    for (uintptr_t off = 0x00; off <= 0x140; off += 8) {
        void *v = *(void **)((uintptr_t)cls + off);
        IMLog("cheatmgr:   +0x%03lx = %p  ptr=%d", (unsigned long)off, v, IMLooksLikePtr(v));
    }
}

static const uintptr_t IM_EXECMASK = 0x0000FFFFFFFFFFFFULL;   // low 48 bits (ignore PAC)

// Walk cls->[childrenOff] following [+nextOff], scanning each node for the exec.
// All reads go through IMSafeRead so wrong offsets never crash.
static void *IMWalkChain(void *cls, uintptr_t childrenOff, uintptr_t nextOff,
                         uintptr_t target, int *outLen) {
    void *child = NULL;
    if (!IMSafeRead((void *)((uintptr_t)cls + childrenOff), &child, 8)) { *outLen = 0; return NULL; }
    int guard = 0;
    while (IMLooksLikePtr(child) && guard < 8000) {
        guard++;
        uintptr_t node[0x1E];   // 0xF0 bytes of the child
        if (!IMSafeRead(child, node, sizeof(node))) break;
        for (unsigned i = 0; i < 0x1D; i++) {
            if ((node[i] & IM_EXECMASK) == target) {
                *outLen = guard;
                IMLog("cheatmgr: MATCH UFunction=%p Func@+0x%x children=0x%lx next=0x%lx after %d",
                      child, i * 8, (unsigned long)childrenOff, (unsigned long)nextOff, guard);
                return child;
            }
        }
        child = (void *)node[nextOff / 8];
    }
    *outLen = guard;
    return NULL;
}

// Probe several (childrenOff, nextOff) layouts; the correct one produces a long
// chain and finds the exec. Reports each chain length so we can lock the offsets.
static void *IMFindFunctionByExec(void *cls, uintptr_t childrenOffIgnored, uintptr_t nextOffIgnored) {
    (void)childrenOffIgnored; (void)nextOffIgnored;
    if (!IMLooksLikePtr(cls)) return NULL;
    uintptr_t target = (uintptr_t)IMRuntimeAddress(RVA_ClaimSoloRaidBossExec) & IM_EXECMASK;
    const uintptr_t childCands[] = {0x48, 0x50, 0x38, 0x30};
    const uintptr_t nextCands[]  = {0x28, 0x30, 0x48, 0x50, 0xE0, 0x20};
    for (unsigned ci = 0; ci < sizeof(childCands)/sizeof(childCands[0]); ci++) {
        for (unsigned ni = 0; ni < sizeof(nextCands)/sizeof(nextCands[0]); ni++) {
            int len = 0;
            void *f = IMWalkChain(cls, childCands[ci], nextCands[ni], target, &len);
            IMLog("cheatmgr: probe child=0x%lx next=0x%lx -> len=%d%s",
                  (unsigned long)childCands[ci], (unsigned long)nextCands[ni],
                  len, f ? " MATCH" : "");
            if (f) return f;
        }
    }
    return NULL;
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
    if (!func) {
        // FName/FindFunction path failed — fall back to walking the class function
        // list and matching by the exec pointer. First dump the class layout so we
        // can confirm the Children offset from real memory.
        void *cls = *(void **)((uintptr_t)mgr + OFF_UObjectClass);
        IMDumpClassLayout(cls);
        // Dump the first child (cls+0x48) so we can read the real Next/Func offsets.
        void *child0 = *(void **)((uintptr_t)cls + 0x48);
        IMLog("cheatmgr: --- first child @0x48 = %p ---", child0);
        IMDumpClassLayout(child0);
        // Children @ 0x48, Next @ 0x28 (confirmed from the class layout dump).
        func = IMFindFunctionByExec(cls, 0x48, 0x28);
    }
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
