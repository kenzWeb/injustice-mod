// Injustice 2 Mobile mod menu — Theos tweak for jailbroken iOS 15+.
// Hooks ACombatCharacter::SetCurrentHealth, the single funnel every HP change
// goes through, and draws a floating overlay menu.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import "offsets.h"

// ---------------------------------------------------------------- state
static uintptr_t gSlide = 0;
static BOOL      gHooked = NO;

static atomic_bool gGodMode;      // player never loses HP
static atomic_bool gOneHitKill;   // enemies drop to 0
static atomic_bool gFreezeAll;    // nobody's HP changes

// last values seen by the hook — copied out, never dereferenced later
static atomic_int   gPlayerHP;
static atomic_int   gPlayerMax;
static atomic_int   gEnemyHP;
static atomic_int   gEnemyMax;
static atomic_llong gLastSeenMs;  // written on the game thread, read on main

// ---------------------------------------------------------------- helpers
static const struct mach_header *gMainHeader = NULL;
static uintptr_t gTextLo = 0, gTextHi = 0, gImageHi = 0;

static inline long long nowMs(void) {
    return (long long)(CACurrentMediaTime() * 1000.0);
}

static void computeImage(void) {
    gMainHeader = _dyld_get_image_header(0);
    gSlide = (uintptr_t)_dyld_get_image_vmaddr_slide(0);
    // main executable is always image 0; sanity-check the name anyway
    const char *nm = _dyld_get_image_name(0);
    if (nm && !strstr(nm, "Injustice2Mobile")) {
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *n = _dyld_get_image_name(i);
            if (n && strstr(n, "Injustice2Mobile")) {
                gMainHeader = _dyld_get_image_header(i);
                gSlide = (uintptr_t)_dyld_get_image_vmaddr_slide(i);
                break;
            }
        }
    }
    gTextLo  = (uintptr_t)gMainHeader;
    gTextHi  = gTextLo + 0x4B30000;   // end of __TEXT   (build 6.7.1)
    gImageHi = gTextLo + 0x661C000;   // end of __LINKEDIT — whole image span
}

static inline void *R(uintptr_t rva) { return (void *)((uintptr_t)gMainHeader + rva); }

// bool ABaseGameCharacter::IsPlayerCharacter() — virtual, slot at byte 0x9A0.
static BOOL isPlayerCharacter(void *self) {
    if (!self) return NO;
    uintptr_t vptr = *(uintptr_t *)self;          // vtables live in __DATA_CONST
    if (vptr < gTextLo || vptr >= gImageHi) return NO;
    uintptr_t fn = *(uintptr_t *)(vptr + VT_IsPlayerCharacter);
    if (fn < gTextLo || fn >= gTextHi) return NO; // the target must be code
    typedef bool (*IsPlayerFn)(void *);
    return ((IsPlayerFn)fn)(self) ? YES : NO;
}

// ---------------------------------------------------------------- hook
typedef void (*SetCurrentHealth_t)(void *self, int newHP);
static SetCurrentHealth_t orig_SetCurrentHealth = NULL;

static void hook_SetCurrentHealth(void *self, int newHP) {
    int maxHP = 0;
    if (self) maxHP = *(int *)((uintptr_t)self + OFF_MaxHealth);

    BOOL mine = isPlayerCharacter(self);

    if (mine) {
        atomic_store(&gPlayerMax, maxHP);
        atomic_store(&gPlayerHP, newHP);
    } else {
        atomic_store(&gEnemyMax, maxHP);
        atomic_store(&gEnemyHP, newHP);
    }
    atomic_store(&gLastSeenMs, nowMs());

    if (atomic_load(&gFreezeAll)) return;                 // drop the write entirely
    if (mine && atomic_load(&gGodMode))      newHP = maxHP;
    if (!mine && atomic_load(&gOneHitKill))  newHP = 0;

    orig_SetCurrentHealth(self, newHP);
}

// ---------------------------------------------------------------- menu UI
@interface IMModMenu : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView   *panel;
@property (nonatomic, strong) UIButton *ball;
@property (nonatomic, strong) UILabel  *hud;
@property (nonatomic, strong) NSTimer  *ticker;
+ (instancetype)shared;
- (void)present;
@end

@implementation IMModMenu

+ (instancetype)shared {
    static IMModMenu *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMModMenu new]; });
    return s;
}

- (UIWindowScene *)activeScene {
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if ([sc isKindOfClass:UIWindowScene.class] &&
            sc.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)sc;
        }
    }
    return nil;
}

- (void)present {
    if (self.window) return;
    UIWindowScene *scene = [self activeScene];
    if (!scene) return;

    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.window.frame = UIScreen.mainScreen.bounds;
    self.window.windowLevel = UIWindowLevelAlert + 100;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.rootViewController = [UIViewController new];
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.window.hidden = NO;

    // the panel is added first so the ball sits on top of it
    [self buildPanel];
    [self buildBall];
    [self.window.rootViewController.view addSubview:self.panel];
    [self.window.rootViewController.view addSubview:self.ball];

    self.ticker = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                   target:self
                                                 selector:@selector(refresh)
                                                 userInfo:nil
                                                  repeats:YES];
}

// only the menu subviews should swallow touches, the game keeps the rest
- (void)buildBall {
    self.ball = [UIButton buttonWithType:UIButtonTypeCustom];
    self.ball.frame = CGRectMake(24, 120, 54, 54);
    self.ball.backgroundColor = [UIColor colorWithRed:0.85 green:0.1 blue:0.1 alpha:0.85];
    self.ball.layer.cornerRadius = 27;
    self.ball.layer.borderWidth = 1.5;
    self.ball.layer.borderColor = UIColor.whiteColor.CGColor;
    [self.ball setTitle:@"MOD" forState:UIControlStateNormal];
    self.ball.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [self.ball addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.ball addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
}

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.window];
    g.view.center = CGPointMake(g.view.center.x + d.x, g.view.center.y + d.y);
    [g setTranslation:CGPointZero inView:self.window];
}

- (UISwitch *)rowAt:(CGFloat)y title:(NSString *)title action:(SEL)sel {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, y, 190, 30)];
    l.text = title;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:14];
    [self.panel addSubview:l];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(212, y - 2, 51, 31)];
    sw.onTintColor = [UIColor colorWithRed:0.85 green:0.1 blue:0.1 alpha:1];
    [sw addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:sw];
    return sw;
}

- (void)buildPanel {
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(24, 184, 286, 214)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    self.panel.hidden = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, 258, 20)];
    title.text = @"Injustice 2 — 6.7.1";
    title.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    title.font = [UIFont boldSystemFontOfSize:12];
    [self.panel addSubview:title];

    self.hud = [[UILabel alloc] initWithFrame:CGRectMake(14, 32, 258, 40)];
    self.hud.numberOfLines = 2;
    self.hud.textColor = [UIColor colorWithRed:0.4 green:1 blue:0.5 alpha:1];
    self.hud.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    self.hud.text = @"HP  --\nENEMY  --";
    [self.panel addSubview:self.hud];

    [self rowAt:84  title:@"God mode (только я)"   action:@selector(god:)];
    [self rowAt:126 title:@"One-hit kill (враги)"  action:@selector(ohk:)];
    [self rowAt:168 title:@"Freeze HP (все)"       action:@selector(freeze:)];
}

- (void)toggle { self.panel.hidden = !self.panel.hidden; }

- (void)god:(UISwitch *)s    { atomic_store(&gGodMode, s.isOn); }
- (void)ohk:(UISwitch *)s    { atomic_store(&gOneHitKill, s.isOn); }
- (void)freeze:(UISwitch *)s { atomic_store(&gFreezeAll, s.isOn); }

- (void)refresh {
    if (self.panel.hidden) return;
    BOOL stale = (nowMs() - atomic_load(&gLastSeenMs)) > 3000;
    if (stale) {
        self.hud.text = @"HP  --\nENEMY  --";
        return;
    }
    int hp = atomic_load(&gPlayerHP),  mx = atomic_load(&gPlayerMax);
    int eh = atomic_load(&gEnemyHP),   em = atomic_load(&gEnemyMax);
    self.hud.text = [NSString stringWithFormat:@"HP  %d / %d\nENEMY  %d / %d", hp, mx, eh, em];
}
@end

// ---------------------------------------------------------------- bootstrap
static BOOL versionMatches(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *bv = info[@"CFBundleVersion"];
    NSString *sv = info[@"CFBundleShortVersionString"];
    return [bv isEqualToString:kExpectedBundleVersion] &&
           [sv isEqualToString:kExpectedShortVersion];
}

static void installHooks(void) {
    if (gHooked) return;
    MSHookFunction(R(RVA_SetCurrentHealth),
                   (void *)hook_SetCurrentHealth,
                   (void **)&orig_SetCurrentHealth);
    gHooked = (orig_SetCurrentHealth != NULL);
    NSLog(@"[IMMod] hooks %@ (slide 0x%lx, base %p)",
          gHooked ? @"installed" : @"FAILED", (unsigned long)gSlide, gMainHeader);
}

static void presentWhenReady(int attempt) {
    if (attempt > 60) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[IMModMenu shared] present];
        if (![IMModMenu shared].window) presentWhenReady(attempt + 1);
    });
}

%ctor {
    @autoreleasepool {
        computeImage();
        if (!versionMatches()) {
            NSLog(@"[IMMod] build mismatch — offsets are for 6.7.1 (1438123), "
                  @"got %@ (%@). Not hooking.",
                  NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],
                  NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]);
            return;
        }
        installHooks();
        presentWhenReady(0);
    }
}
