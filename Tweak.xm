// Injustice 2 Mobile mod menu — Theos tweak for jailbroken iOS 15+.
// Hooks ACombatCharacter::SetCurrentHealth, the single funnel every HP change
// goes through, and draws a floating overlay menu.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <math.h>
#import "offsets.h"

// ---------------------------------------------------------------- state
static uintptr_t gSlide = 0;
static BOOL      gHooked = NO;

static atomic_bool gMasterOff;     // kill switch: behave exactly like vanilla
static atomic_bool gGodMode;       // player never loses HP
static atomic_bool gOneHitKill;    // enemies drop to 0
static atomic_bool gFreezeAll;     // nobody's HP changes
static atomic_bool gHealLatch;     // one-shot: next player write becomes MaxHealth

// multipliers are held x100 so they can live in plain atomics
static atomic_int  gDmgMulX100;    // damage dealt TO enemies
static atomic_int  gDefMulX100;    // damage taken BY the player

static atomic_bool gFixedDmgOn;    // exact damage per hit, overrides gDmgMulX100
static atomic_int  gFixedDmg;

// last values seen by the hook — copied out, never dereferenced later
static atomic_int   gPlayerHP;
static atomic_int   gPlayerMax;
static atomic_int   gEnemyHP;
static atomic_int   gEnemyMax;
static atomic_llong gLastSeenMs;   // written on the game thread, read on main

// ---------------------------------------------------------------- helpers
static const struct mach_header *gMainHeader = NULL;
static uintptr_t gTextLo = 0, gTextHi = 0, gImageHi = 0;

static inline long long nowMs(void) {
    return (long long)(CACurrentMediaTime() * 1000.0);
}

static inline int clampi(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
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
    if (!self) { orig_SetCurrentHealth(self, newHP); return; }

    const int maxHP = *(int *)((uintptr_t)self + OFF_MaxHealth);
    const int curHP = *(int *)((uintptr_t)self + OFF_CurrentHealth);
    const BOOL mine = isPlayerCharacter(self);

    // readout is passive, so it keeps working even with the kill switch on
    if (mine) {
        atomic_store(&gPlayerMax, maxHP);
        atomic_store(&gPlayerHP, newHP);
    } else {
        atomic_store(&gEnemyMax, maxHP);
        atomic_store(&gEnemyHP, newHP);
    }
    atomic_store(&gLastSeenMs, nowMs());

    if (atomic_load(&gMasterOff)) { orig_SetCurrentHealth(self, newHP); return; }
    if (atomic_load(&gFreezeAll)) return;             // drop the write entirely

    const int delta = curHP - newHP;                  // >0 damage, <0 heal

    if (mine) {
        if (atomic_load(&gGodMode)) {
            newHP = maxHP;
        } else if (atomic_exchange(&gHealLatch, false)) {
            newHP = maxHP;                            // one-shot "heal to full"
        } else if (delta > 0) {
            int m = atomic_load(&gDefMulX100);
            if (m != 100) newHP = curHP - (int)lround((double)delta * m / 100.0);
        }
    } else {
        if (atomic_load(&gOneHitKill)) {
            newHP = 0;
        } else if (delta > 0) {
            if (atomic_load(&gFixedDmgOn)) {
                newHP = curHP - atomic_load(&gFixedDmg);   // exact hit, ignores the multiplier
            } else {
                int m = atomic_load(&gDmgMulX100);
                if (m != 100) newHP = curHP - (int)lround((double)delta * m / 100.0);
            }
        }
    }

    orig_SetCurrentHealth(self, clampi(newHP, 0, maxHP > 0 ? maxHP : newHP));
}

// ---------------------------------------------------------------- overlay
// A full-screen overlay window would swallow every touch, leaving the game
// visible and audible but completely dead. Returning nil from hitTest: for
// points that do not land on our own controls makes UIKit fall through to the
// window underneath, so only the ball and the panel take input.
@interface IMPassthroughWindow : UIWindow
@end

@implementation IMPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
// must be YES, otherwise the numeric fields can never receive the keyboard
- (BOOL)canBecomeKeyWindow { return YES; }
@end

static UIColor *IMAccent(void)  { return [UIColor colorWithRed:1.00 green:0.27 blue:0.23 alpha:1]; }
static UIColor *IMDim(void)     { return [UIColor colorWithWhite:1 alpha:0.45]; }
static UIColor *IMHair(void)    { return [UIColor colorWithWhite:1 alpha:0.10]; }

static const CGFloat kPanelW = 292.0;
static const CGFloat kPad    = 16.0;

@interface IMModMenu : NSObject <UITextFieldDelegate>
@property (nonatomic, strong) IMPassthroughWindow *window;
@property (nonatomic, strong) UIVisualEffectView  *panel;
@property (nonatomic, strong) UIScrollView        *scroll;
@property (nonatomic, strong) UIVisualEffectView  *ball;
@property (nonatomic, strong) UILabel   *hud;
@property (nonatomic, strong) UILabel   *pill;      // compact readout next to the ball
@property (nonatomic, strong) UISlider  *dmgSlider;
@property (nonatomic, strong) UISlider  *defSlider;
@property (nonatomic, strong) UISlider  *fixSlider;
@property (nonatomic, strong) UITextField *dmgField;
@property (nonatomic, strong) UITextField *defField;
@property (nonatomic, strong) UITextField *fixField;
@property (nonatomic, strong) NSTimer   *ticker;
@property (nonatomic, weak)   UIWindow  *prevKeyWindow;
@property (nonatomic, assign) CGFloat    cursorY;
@property (nonatomic, assign) BOOL       panelMoved;
@property (nonatomic, assign) BOOL       pillOn;
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

    self.window = [[IMPassthroughWindow alloc] initWithWindowScene:scene];
    self.window.frame = UIScreen.mainScreen.bounds;
    self.window.windowLevel = UIWindowLevelAlert + 100;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.rootViewController = [UIViewController new];
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.window.hidden = NO;

    [self buildPanel];
    [self buildBall];
    UIView *root = self.window.rootViewController.view;
    [root addSubview:self.panel];
    [root addSubview:self.ball];
    [root addSubview:self.pill];

    self.ticker = [NSTimer scheduledTimerWithTimeInterval:0.12
                                                   target:self
                                                 selector:@selector(refresh)
                                                 userInfo:nil
                                                  repeats:YES];
}

#pragma mark - ball

- (void)buildBall {
    UIBlurEffect *fx = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    self.ball = [[UIVisualEffectView alloc] initWithEffect:fx];
    self.ball.frame = CGRectMake(20, 110, 46, 46);
    self.ball.layer.cornerRadius = 23;
    self.ball.layer.cornerCurve = kCACornerCurveContinuous;
    self.ball.clipsToBounds = YES;
    self.ball.layer.borderWidth = 0.5;
    self.ball.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;

    UIImageView *glyph = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"bolt.fill"]];
    glyph.tintColor = IMAccent();
    glyph.contentMode = UIViewContentModeScaleAspectFit;
    glyph.frame = CGRectMake(13, 13, 20, 20);
    [self.ball.contentView addSubview:glyph];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
    [self.ball addGestureRecognizer:tap];
    [self.ball addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragBall:)]];

    // compact HP readout that rides next to the ball while the panel is closed
    self.pill = [[UILabel alloc] initWithFrame:CGRectZero];
    self.pill.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    self.pill.textColor = UIColor.whiteColor;
    self.pill.textAlignment = NSTextAlignmentCenter;
    self.pill.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    self.pill.layer.cornerRadius = 9;
    self.pill.layer.masksToBounds = YES;
    self.pill.hidden = YES;
    self.pill.userInteractionEnabled = NO;
}

- (void)dragBall:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.window];
    g.view.center = CGPointMake(g.view.center.x + d.x, g.view.center.y + d.y);
    [g setTranslation:CGPointZero inView:self.window];
    [self layoutPill];
}

- (void)layoutPill {
    CGRect b = self.ball.frame;
    self.pill.frame = CGRectMake(CGRectGetMaxX(b) + 6, CGRectGetMidY(b) - 9, 96, 18);
}

#pragma mark - panel

// Rows live in a scroll view: the game is landscape-only (~390pt tall) and the
// full row stack is taller than that, so the panel must be able to scroll.
- (UIView *)panelBody { return self.scroll ?: self.panel.contentView; }

- (void)addSeparator {
    UIView *s = [[UIView alloc] initWithFrame:CGRectMake(kPad, self.cursorY, kPanelW - kPad * 2, 0.5)];
    s.backgroundColor = IMHair();
    [[self panelBody] addSubview:s];
    self.cursorY += 0.5;
}

- (UILabel *)rowLabel:(NSString *)t width:(CGFloat)w {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(kPad, self.cursorY + 11, w, 20)];
    l.text = t;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    [[self panelBody] addSubview:l];
    return l;
}

- (UISwitch *)addSwitchRow:(NSString *)title action:(SEL)sel accent:(BOOL)accent {
    [self rowLabel:title width:190];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.transform = CGAffineTransformMakeScale(0.82, 0.82);
    sw.center = CGPointMake(kPanelW - kPad - 21, self.cursorY + 21);
    sw.onTintColor = accent ? IMAccent() : [UIColor colorWithRed:0.30 green:0.78 blue:0.42 alpha:1];
    [sw addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [[self panelBody] addSubview:sw];
    self.cursorY += 42;
    [self addSeparator];
    return sw;
}

// label + editable value on one line, slider underneath
- (void)addValueRow:(NSString *)title
              field:(UITextField **)outField
             slider:(UISlider **)outSlider
        fieldAction:(SEL)fieldSel
       sliderAction:(SEL)sliderSel
              value:(float)initial
                max:(float)maxV
           decimals:(BOOL)dec
{
    [self rowLabel:title width:150];

    UITextField *tf = [[UITextField alloc] initWithFrame:
        CGRectMake(kPanelW - kPad - 90, self.cursorY + 8, 90, 26)];
    tf.text = dec ? [NSString stringWithFormat:@"%.2f", initial]
                  : [NSString stringWithFormat:@"%d", (int)initial];
    tf.textAlignment = NSTextAlignmentRight;
    tf.textColor = IMAccent();
    tf.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    tf.keyboardType = dec ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumberPad;
    tf.keyboardAppearance = UIKeyboardAppearanceDark;
    tf.borderStyle = UITextBorderStyleNone;
    tf.delegate = self;
    tf.tintColor = IMAccent();
    [tf addTarget:self action:fieldSel forControlEvents:UIControlEventEditingDidEnd];

    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 200, 40)];
    bar.barStyle = UIBarStyleBlack;
    bar.items = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                      target:nil action:nil],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self action:@selector(dismissKeyboard)]
    ];
    [bar sizeToFit];
    tf.inputAccessoryView = bar;
    [[self panelBody] addSubview:tf];

    UISlider *sl = [[UISlider alloc] initWithFrame:
        CGRectMake(kPad, self.cursorY + 36, kPanelW - kPad * 2, 20)];
    sl.minimumValue = 0.0;
    sl.maximumValue = maxV;
    sl.value = fminf(initial, maxV);
    sl.minimumTrackTintColor = IMAccent();
    sl.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.16];
    [sl addTarget:self action:sliderSel forControlEvents:UIControlEventValueChanged];
    [[self panelBody] addSubview:sl];

    *outField = tf;
    *outSlider = sl;
    self.cursorY += 66;
    [self addSeparator];
}

- (void)addButtonRow:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(kPad, self.cursorY + 7, kPanelW - kPad * 2, 30);
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    b.layer.cornerRadius = 9;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [[self panelBody] addSubview:b];
    self.cursorY += 44;
    [self addSeparator];
}

- (void)buildPanel {
    UIBlurEffect *fx = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark];
    self.panel = [[UIVisualEffectView alloc] initWithEffect:fx];
    self.panel.layer.cornerRadius = 20;
    self.panel.layer.cornerCurve = kCACornerCurveContinuous;
    self.panel.clipsToBounds = YES;
    self.panel.layer.borderWidth = 0.5;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    self.panel.hidden = YES;

    self.cursorY = 0;

    // -------- header: grabber + title, the whole strip drags the panel
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, 44)];
    [self.panel.contentView addSubview:header];

    UIView *grab = [[UIView alloc] initWithFrame:CGRectMake(kPanelW / 2 - 18, 7, 36, 4)];
    grab.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    grab.layer.cornerRadius = 2;
    [header addSubview:grab];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(kPad, 17, 180, 18)];
    title.text = @"INJUSTICE 2";
    title.textColor = IMDim();
    title.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    [header addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(kPanelW - kPad - 22, 13, 22, 22);
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = IMDim();
    [close addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:close];

    [header addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)]];

    UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 44, kPanelW, 0.5)];
    hair.backgroundColor = IMHair();
    [self.panel.contentView addSubview:hair];

    // everything below the header scrolls
    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scroll.showsVerticalScrollIndicator = YES;
    self.scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    // without these the scroll view swallows the start of a slider drag
    self.scroll.delaysContentTouches = NO;
    self.scroll.canCancelContentTouches = NO;
    [self.panel.contentView addSubview:self.scroll];

    self.cursorY = 0;

    // -------- live readout
    self.hud = [[UILabel alloc] initWithFrame:
        CGRectMake(kPad, self.cursorY + 10, kPanelW - kPad * 2, 40)];
    self.hud.numberOfLines = 2;
    self.hud.textColor = [UIColor colorWithRed:0.42 green:0.98 blue:0.55 alpha:1];
    self.hud.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    self.hud.text = @"YOU    —\nENEMY  —";
    [[self panelBody] addSubview:self.hud];
    self.cursorY += 58;
    [self addSeparator];

    // -------- toggles
    [self addSwitchRow:@"God mode (только я)"  action:@selector(god:)    accent:NO];
    [self addSwitchRow:@"One-hit kill (враги)" action:@selector(ohk:)    accent:NO];
    [self addSwitchRow:@"Freeze HP (все)"      action:@selector(freeze:) accent:NO];

    // -------- multipliers
    [self addValueRow:@"Урон по врагам ×"
                field:&_dmgField slider:&_dmgSlider
          fieldAction:@selector(dmgFieldDone:)
         sliderAction:@selector(dmgSlid:)
                value:1.0 max:10.0 decimals:YES];
    [self addValueRow:@"Урон по мне ×"
                field:&_defField slider:&_defSlider
          fieldAction:@selector(defFieldDone:)
         sliderAction:@selector(defSlid:)
                value:1.0 max:10.0 decimals:YES];

    // -------- exact damage per hit
    [self addSwitchRow:@"Фикс. урон по врагам" action:@selector(fixOn:) accent:NO];
    [self addValueRow:@"Урон за удар"
                field:&_fixField slider:&_fixSlider
          fieldAction:@selector(fixFieldDone:)
         sliderAction:@selector(fixSlid:)
                value:1000 max:20000 decimals:NO];
    UILabel *hint = [[UILabel alloc] initWithFrame:
        CGRectMake(kPad, self.cursorY + 2, kPanelW - kPad * 2, 14)];
    hint.text = @"перекрывает множитель; шкала — по HP противника";
    hint.textColor = IMDim();
    hint.font = [UIFont systemFontOfSize:10];
    [[self panelBody] addSubview:hint];
    self.cursorY += 18;
    [self addSeparator];

    // -------- actions
    [self addButtonRow:@"Восстановить HP" action:@selector(healNow)];
    [self addSwitchRow:@"HP на экране"    action:@selector(pillToggle:) accent:NO];
    [self addSwitchRow:@"Master OFF"      action:@selector(master:)     accent:YES];

    UILabel *note = [[UILabel alloc] initWithFrame:
        CGRectMake(kPad, self.cursorY + 6, kPanelW - kPad * 2, 14)];
    note.text = @"Master OFF — полностью ванильное поведение";
    note.textColor = IMDim();
    note.font = [UIFont systemFontOfSize:10];
    [[self panelBody] addSubview:note];
    self.cursorY += 26;

    // fit inside the (landscape) screen: header + as much body as there is room for
    const CGFloat headerH = 44.5;
    CGFloat avail = self.window.bounds.size.height - 24 - headerH;
    CGFloat bodyH = fmin(self.cursorY, fmax(120, avail));
    self.scroll.frame = CGRectMake(0, headerH, kPanelW, bodyH);
    self.scroll.contentSize = CGSizeMake(kPanelW, self.cursorY);
    self.panel.frame = CGRectMake(20, 100, kPanelW, headerH + bodyH);
}

- (void)dragPanel:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.window];
    self.panel.center = CGPointMake(self.panel.center.x + d.x, self.panel.center.y + d.y);
    [g setTranslation:CGPointZero inView:self.window];
    self.panelMoved = YES;
}

#pragma mark - actions

- (void)toggle {
    if (self.panel.hidden && !self.panelMoved) {
        // first open: park the panel just under the ball, kept on screen
        CGRect scr = self.window.bounds;
        CGFloat x = fmin(fmax(8, CGRectGetMinX(self.ball.frame)), scr.size.width - kPanelW - 8);
        CGFloat y = fmin(CGRectGetMaxY(self.ball.frame) + 10,
                         scr.size.height - self.panel.frame.size.height - 8);
        self.panel.frame = CGRectMake(x, fmax(8, y), kPanelW, self.panel.frame.size.height);
    }
    self.panel.hidden = !self.panel.hidden;
    if (self.panel.hidden) [self dismissKeyboard];
}

- (void)god:(UISwitch *)s    { atomic_store(&gGodMode, s.isOn); }
- (void)ohk:(UISwitch *)s    { atomic_store(&gOneHitKill, s.isOn); }
- (void)freeze:(UISwitch *)s { atomic_store(&gFreezeAll, s.isOn); }
- (void)master:(UISwitch *)s { atomic_store(&gMasterOff, s.isOn); }
- (void)healNow              { atomic_store(&gHealLatch, true); }
- (void)pillToggle:(UISwitch *)s { self.pillOn = s.isOn; }

- (void)applyDmg:(float)v {
    v = fmaxf(0.0f, fminf(v, 999.0f));
    atomic_store(&gDmgMulX100, (int)lroundf(v * 100.0f));
    self.dmgField.text = [NSString stringWithFormat:@"%.2f", v];
    self.dmgSlider.value = fminf(v, self.dmgSlider.maximumValue);
}

- (void)applyDef:(float)v {
    v = fmaxf(0.0f, fminf(v, 999.0f));
    atomic_store(&gDefMulX100, (int)lroundf(v * 100.0f));
    self.defField.text = [NSString stringWithFormat:@"%.2f", v];
    self.defSlider.value = fminf(v, self.defSlider.maximumValue);
}

- (void)fixOn:(UISwitch *)s { atomic_store(&gFixedDmgOn, s.isOn); }

- (void)applyFix:(float)v {
    int iv = (int)lroundf(fmaxf(0.0f, fminf(v, 9999999.0f)));
    atomic_store(&gFixedDmg, iv);
    self.fixField.text = [NSString stringWithFormat:@"%d", iv];
    self.fixSlider.value = fminf((float)iv, self.fixSlider.maximumValue);
}

- (void)fixSlid:(UISlider *)s      { [self applyFix:s.value]; }
- (void)fixFieldDone:(UITextField *)f { [self applyFix:[f.text floatValue]]; }

- (void)dmgSlid:(UISlider *)s      { [self applyDmg:s.value]; }
- (void)defSlid:(UISlider *)s      { [self applyDef:s.value]; }
- (void)dmgFieldDone:(UITextField *)f {
    [self applyDmg:[[f.text stringByReplacingOccurrencesOfString:@"," withString:@"."] floatValue]];
}
- (void)defFieldDone:(UITextField *)f {
    [self applyDef:[[f.text stringByReplacingOccurrencesOfString:@"," withString:@"."] floatValue]];
}

#pragma mark - keyboard

// The overlay window is deliberately not key, so the game keeps its input.
// Borrow key status only while a field is being edited, then hand it back.
- (void)textFieldDidBeginEditing:(UITextField *)tf {
    if (!self.window.isKeyWindow) {
        for (UIWindow *w in self.window.windowScene.windows) {
            if (w.isKeyWindow && w != self.window) { self.prevKeyWindow = w; break; }
        }
        [self.window makeKeyWindow];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)tf {
    UIWindow *prev = self.prevKeyWindow;
    self.prevKeyWindow = nil;
    if (prev) [prev makeKeyWindow];
}

- (void)dismissKeyboard {
    [self.dmgField resignFirstResponder];
    [self.defField resignFirstResponder];
    [self.fixField resignFirstResponder];
}

#pragma mark - refresh

- (void)refresh {
    BOOL stale = (nowMs() - atomic_load(&gLastSeenMs)) > 3000;
    int hp = atomic_load(&gPlayerHP), mx = atomic_load(&gPlayerMax);
    int eh = atomic_load(&gEnemyHP),  em = atomic_load(&gEnemyMax);

    self.pill.hidden = !(self.pillOn && self.panel.hidden);
    if (!self.pill.hidden) {
        [self layoutPill];
        self.pill.text = stale ? @"—" : [NSString stringWithFormat:@"%d / %d", hp, mx];
    }

    if (self.panel.hidden) return;

    // make the fixed-damage slider span the opponent's actual health bar, so the
    // range stays meaningful instead of an arbitrary constant
    if (em > 0 && fabsf(self.fixSlider.maximumValue - (float)em) > 1.0f
        && !self.fixField.isEditing) {
        self.fixSlider.maximumValue = (float)em;
        self.fixSlider.value = fminf((float)atomic_load(&gFixedDmg), (float)em);
    }

    self.hud.text = stale
        ? @"YOU    —\nENEMY  —"
        : [NSString stringWithFormat:@"YOU    %d / %d\nENEMY  %d / %d", hp, mx, eh, em];
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
        atomic_store(&gDmgMulX100, 100);
        atomic_store(&gDefMulX100, 100);
        atomic_store(&gFixedDmg, 1000);
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
