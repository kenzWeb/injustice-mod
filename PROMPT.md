# Промпт для ИИ-агента на macOS

Скопируй всё, что ниже разделителя, в Claude Code / другого агента на маке.
Промпт самодостаточный: если папки `tweak/` на маке нет, агент создаст все файлы сам
из содержимого промпта. Если папка есть — он просто соберёт её.

---

## ЗАДАЧА

Собрать iOS-твик (Theos, `.deb`) под джейлбрейк **RootHide** и вернуть путь к готовому
пакету. Ничего устанавливать на устройство не нужно — только сборка.

Проект называется `InjusticeMod`: оверлей-меню для игры Injustice 2 Mobile 6.7.1,
хукает одну нативную функцию через `MSHookFunction` и рисует плавающее окно UIKit.

## ОКРУЖЕНИЕ

macOS с Xcode Command Line Tools. Нужен **форк Theos от roothide** — в стоковом Theos
нет схемы упаковки `roothide`, сборка на ней падает.

```bash
xcode-select --install 2>/dev/null || true
brew install ldid xz

export THEOS=~/theos-roothide
git clone --recursive https://github.com/roothide/theos "$THEOS"
```

SDK скачивать не надо: на macOS Theos берёт iPhoneOS SDK из Xcode, а твик использует
только публичные фреймворки (UIKit, QuartzCore, Foundation) плюс `substrate.h`,
который лежит в самом Theos.

## СБОРКА

```bash
cd <папка с Makefile>
export THEOS=~/theos-roothide
make package FINALPACKAGE=1
```

Готовый пакет появится в `./packages/*.deb`.

## КРИТИЧНО

1. **Не менять значения в `offsets.h`.** Это RVA, снятые статическим анализом
   конкретного бинаря Injustice2Mobile 6.7.1 (Mach-O UUID `2c66bd15-78e2-3cab-b3f6-2be3ff279a18`).
   Любая «поправка» их сломает.
2. **Не менять логику хука** в `hook_SetCurrentHealth` и `isPlayerCharacter`.
3. Если компилятор ругается — чини **минимально** (синтаксис, депрекейты, порядок
   объявлений) и в отчёте перечисли построчно, что именно поменял и почему.
4. Не добавлять никаких сетевых запросов, аналитики и обращений к ФС. Твик их не имеет
   намеренно: на RootHide рандомизированный jbroot, и любой хардкод путей всё сломает.

## ТИПОВЫЕ ОШИБКИ

| Симптом | Причина / что делать |
|---|---|
| `Unknown package scheme 'roothide'` | взят стоковый Theos — нужен форк roothide |
| `substrate.h: No such file` | Theos склонирован без `--recursive`, либо `$THEOS` не выставлен |
| `ldid: command not found` | `brew install ldid` |
| ошибки на `arm64e` | убрать `arm64e` из `ARCHS` в Makefile — у игры нет arm64e-слайса, слайс arm64 достаточен |
| `No rule to make target` | запуск не из папки с Makefile |
| ворнинги на `atomic_*` / `MSHookFunction` | игнорировать, это не ошибки |

## ЧТО ВЕРНУТЬ

1. Полный вывод `make package` (или хотя бы все ошибки/ворнинги).
2. Абсолютный путь к собранному `.deb` и его размер.
3. Вывод `dpkg-deb -I <deb>` и `dpkg-deb -c <deb>`.
4. Список изменений, если что-то пришлось править.

---

# ФАЙЛЫ ПРОЕКТА

Если файлов на маке нет — создай их ровно с этим содержимым, в одной папке.

## `Makefile`

```make
TARGET := iphone:clang:latest:15.0
ARCHS  := arm64 arm64e

# Packaging scheme — this is the ONLY thing that differs between jailbreaks,
# the tweak code itself uses no filesystem paths.
#   roothide  : RootHide (needs the roothide/theos fork — see README)
#   rootless  : Dopamine / palera1n rootless
#   (omit)    : rootful — checkra1n / unc0ver
THEOS_PACKAGE_SCHEME := roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = InjusticeMod

InjusticeMod_FILES      = Tweak.xm
InjusticeMod_CFLAGS     = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations
InjusticeMod_FRAMEWORKS = UIKit Foundation QuartzCore
InjusticeMod_LIBRARIES  = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 Injustice2Mobile || true"
```

> В `after-install::` отступ обязан быть **табом**, не пробелами.

## `control`

```
Package: com.local.injusticemod
Name: Injustice2 Mod Menu
Version: 1.0.0
Architecture: iphoneos-arm64
Description: Floating debug/mod menu for Injustice 2 Mobile 6.7.1 (build 1438123).
 Hooks ACombatCharacter::SetCurrentHealth and shows live HP for the player and
 the current opponent. Offsets are version-locked; the tweak self-disables on a
 build mismatch.
Maintainer: local
Author: local
Section: Tweaks
Depends: ellekit | mobilesubstrate
Tag: role::hacker
```

## `InjusticeMod.plist`

```
{
    Filter = {
        Bundles = ( "com.wb.Injustice.Brawler2017" );
    };
}
```

## `offsets.h`

```c
// Injustice 2 Mobile — offsets for build 6.7.1 (CFBundleVersion 1438123)
// Mach-O UUID 2c66bd15-78e2-3cab-b3f6-2be3ff279a18
//
// Every value is an RVA from the image base (0x100000000). In this binary the
// __TEXT file offset equals the RVA, so these are also raw file offsets.
// They are version-locked: any game update invalidates them. The tweak refuses
// to hook if the running build does not match (see kExpectedBundleVersion).
#pragma once

#define kExpectedBundleVersion  @"1438123"
#define kExpectedShortVersion   @"6.7.1"

// ---- ACombatCharacter (size 0x1DC0) -----------------------------------------
// void ACombatCharacter::SetCurrentHealth(int32 NewHP)
//   x0 = this, w1 = requested HP. Clamps to [0, MaxHealth] then stores to +0x4E4.
//   Single choke point: damage, healing and init all funnel through it.
#define RVA_SetCurrentHealth        0x1B50954

// float ACombatCharacter::GetHealthPercentage() const  -> CurrentHealth / MaxHealth
#define RVA_GetHealthPercentage     0x1B4CFB4

#define OFF_CurrentHealth           0x4E4   // int32
#define OFF_MaxHealth               0x4E8   // int32
#define OFF_CharacterTeam           0x118C  // ECharacterTeam (roster faction, NOT side)

// ---- ABaseGameCharacter (size 0x640) ----------------------------------------
// bool ABaseGameCharacter::IsPlayerCharacter() — virtual, vtable byte offset 0x9A0
#define VT_IsPlayerCharacter        0x9A0

// ---- native exec thunks (UFunction) -----------------------------------------
#define RVA_exec_SetBaseHealth      0x210D98C
#define RVA_exec_GetBaseHealth      0x210D978
#define RVA_exec_RestoreHealth      0x210D9CC
#define RVA_exec_SetHealthPercent   0x210AFBC
#define RVA_exec_InitMaxHealth      0x2111C6C
```

## `Tweak.xm`

```objc
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
```
