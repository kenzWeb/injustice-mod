#import "IMMenu.h"
#import "IMOverlayWindow.h"
#import "IMRowBuilder.h"
#import "IMSettings.h"
#import "IMPresets.h"
#import "IMTheme.h"
#import "IMLog.h"
#import <math.h>

static const CGFloat kBallSize = 46.0;
static const CGFloat kMultiplierSliderMax = 10.0;
static const CGFloat kDefaultFixedDamageSliderMax = 20000.0;

@interface IMMenu () <UITextFieldDelegate>
@property (nonatomic, strong) IMOverlayWindow   *window;
@property (nonatomic, strong) UIVisualEffectView *panel;
@property (nonatomic, strong) UIVisualEffectView *ball;
@property (nonatomic, strong) UIScrollView      *scroll;
@property (nonatomic, strong) UILabel           *readout;
@property (nonatomic, strong) UILabel           *badge;
@property (nonatomic, strong) UILabel           *trace;
@property (nonatomic, strong) UISwitch          *godSwitch;
@property (nonatomic, strong) UISwitch          *oneHitSwitch;
@property (nonatomic, strong) UISwitch          *freezeSwitch;
@property (nonatomic, strong) UISwitch          *energySwitch;
@property (nonatomic, strong) UISwitch          *freezeAISwitch;
@property (nonatomic, strong) UISwitch          *fixedSwitch;
@property (nonatomic, strong) UISwitch          *vpnSwitch;
@property (nonatomic, strong) NSArray<UIButton *> *loadButtons;
@property (nonatomic, strong) IMValueRow        *damageRow;
@property (nonatomic, strong) IMValueRow        *defenseRow;
@property (nonatomic, strong) IMValueRow        *fixedRow;
@property (nonatomic, strong) IMValueRow        *campaignRow;
@property (nonatomic, strong) NSTimer           *ticker;
@property (nonatomic, weak)   UIWindow          *previousKeyWindow;
@property (nonatomic, assign) CGFloat            contentHeight;
@property (nonatomic, assign) CGSize             lastWindowSize;
@property (nonatomic, assign) BOOL               panelMoved;
@property (nonatomic, assign) BOOL               badgeEnabled;
@end

@implementation IMMenu

+ (instancetype)shared {
    static IMMenu *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [IMMenu new]; });
    return instance;
}

- (UIWindowScene *)activeScene {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

- (BOOL)presentIfPossible {
    if (self.window) return YES;

    UIWindowScene *scene = [self activeScene];
    if (!scene) return NO;

    self.window = [[IMOverlayWindow alloc] initWithWindowScene:scene];
    self.window.frame = scene.coordinateSpace.bounds;
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
    [root addSubview:self.badge];

    self.ticker = [NSTimer scheduledTimerWithTimeInterval:0.12
                                                   target:self
                                                 selector:@selector(refresh)
                                                 userInfo:nil
                                                  repeats:YES];
    return YES;
}

- (void)buildBall {
    UIBlurEffect *effect =
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    self.ball = [[UIVisualEffectView alloc] initWithEffect:effect];
    self.ball.frame = CGRectMake(20, 110, kBallSize, kBallSize);
    self.ball.layer.cornerRadius = kBallSize / 2;
    self.ball.layer.cornerCurve = kCACornerCurveContinuous;
    self.ball.clipsToBounds = YES;
    self.ball.layer.borderWidth = 0.5;
    self.ball.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;

    UIImageView *glyph = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"bolt.fill"]];
    glyph.tintColor = IMColorAccent();
    glyph.contentMode = UIViewContentModeScaleAspectFit;
    glyph.frame = CGRectMake(13, 13, 20, 20);
    [self.ball.contentView addSubview:glyph];

    [self.ball addGestureRecognizer:
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePanel)]];
    [self.ball addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragBall:)]];

    self.badge = [[UILabel alloc] initWithFrame:CGRectZero];
    self.badge.font = [UIFont monospacedDigitSystemFontOfSize:11
                                                       weight:UIFontWeightSemibold];
    self.badge.textColor = UIColor.whiteColor;
    self.badge.textAlignment = NSTextAlignmentCenter;
    self.badge.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    self.badge.layer.cornerRadius = 9;
    self.badge.layer.masksToBounds = YES;
    self.badge.userInteractionEnabled = NO;
    self.badge.hidden = YES;
}

- (void)buildPanel {
    UIBlurEffect *effect =
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark];
    self.panel = [[UIVisualEffectView alloc] initWithEffect:effect];
    self.panel.layer.cornerRadius = 20;
    self.panel.layer.cornerCurve = kCACornerCurveContinuous;
    self.panel.clipsToBounds = YES;
    self.panel.layer.borderWidth = 0.5;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    self.panel.hidden = YES;

    [self buildHeader];

    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    self.scroll.delaysContentTouches = NO;
    self.scroll.canCancelContentTouches = YES;
    self.scroll.alwaysBounceVertical = YES;
    [self.panel.contentView addSubview:self.scroll];

    IMRowBuilder *builder = [[IMRowBuilder alloc] initWithContainer:self.scroll];
    [self buildReadoutWithBuilder:builder];

    self.godSwitch = [builder addSwitchRow:@"God mode (только я)"
                                    target:self action:@selector(onGodMode:) accent:NO];
    self.oneHitSwitch = [builder addSwitchRow:@"One-hit kill (враги)"
                                       target:self action:@selector(onOneHitKill:) accent:NO];
    self.freezeSwitch = [builder addSwitchRow:@"Freeze HP (все)"
                                       target:self action:@selector(onFreeze:) accent:NO];
    self.freezeAISwitch = [builder addSwitchRow:@"Заморозить ИИ"
                                         target:self action:@selector(onFreezeAI:) accent:NO];
    [builder addCaption:@"противник не действует, но его можно бить"];
    [builder addSeparator];

    self.damageRow = [builder addValueRow:@"Урон по врагам ×"
                                   target:self
                              fieldAction:@selector(onDamageField:)
                             sliderAction:@selector(onDamageSlider:)
                                    value:1.0
                                 maxValue:kMultiplierSliderMax
                                 decimals:YES];
    self.defenseRow = [builder addValueRow:@"Урон по мне ×"
                                    target:self
                               fieldAction:@selector(onDefenseField:)
                              sliderAction:@selector(onDefenseSlider:)
                                     value:1.0
                                  maxValue:kMultiplierSliderMax
                                  decimals:YES];
    [builder addCaption:@"ползунок до 10, вручную — до 999999999"];
    [builder addSeparator];

    self.fixedSwitch = [builder addSwitchRow:@"Фикс. урон по врагам"
                                      target:self action:@selector(onFixedDamage:) accent:NO];
    self.fixedRow = [builder addValueRow:@"Урон за удар"
                                  target:self
                             fieldAction:@selector(onFixedField:)
                            sliderAction:@selector(onFixedSlider:)
                                   value:IMFixedDamage()
                                maxValue:kDefaultFixedDamageSliderMax
                                decimals:NO];
    [builder addCaption:@"выключено — обычный урон × множитель"];
    [builder addSeparator];

    self.energySwitch = [builder addSwitchRow:@"Бесконечная энергия"
                                       target:self action:@selector(onInfiniteEnergy:) accent:NO];
    [builder addCaption:@"супер всегда доступен, без ожидания между приёмами"];
    [builder addSeparator];

    [builder addSwitchRow:@"Авто-прохождение кампании"
                   target:self action:@selector(onAutoCampaign:) accent:YES];
    self.campaignRow = [builder addValueRow:@"Длительность боя, сек"
                                     target:self
                                fieldAction:@selector(onCampaignDelayField:)
                               sliderAction:@selector(onCampaignDelaySlider:)
                                      value:IMAutoCampaignDelay()
                                   maxValue:15.0
                                   decimals:YES];
    [builder addCaption:@"бой сам завершается победой, экран наград закрывается"];

    UIView *traceRow = [builder addCustomRowOfHeight:34];
    self.trace = [[UILabel alloc] initWithFrame:
        CGRectMake(IMPanelPadding, 4, IMPanelWidth - IMPanelPadding * 2, 26)];
    self.trace.numberOfLines = 1;
    self.trace.font = [UIFont monospacedDigitSystemFontOfSize:10
                                                       weight:UIFontWeightRegular];
    self.trace.textColor = IMColorDim();
    self.trace.text = @"map0 sum0 press0 pre0 fight0 kill0";
    [traceRow addSubview:self.trace];
    [builder addSeparator];

    [builder addButtonRow:@"Авто-победа" target:self action:@selector(onAutoWin)];
    [builder addButtonRow:@"Восстановить HP" target:self action:@selector(onHeal)];
    [builder addSwitchRow:@"HP на экране"
                   target:self action:@selector(onBadge:) accent:NO];

    [builder addSwitchRow:@"Игнорировать требования"
                   target:self action:@selector(onBypassRequirements:) accent:YES];
    [builder addCaption:@"снимает клиентский замок входа в испытания"];
    [builder addSeparator];

    self.vpnSwitch = [builder addSwitchRow:@"Обход проверки VPN (Tapjoy)"
                                    target:self action:@selector(onBypassVPNCheck:) accent:YES];
    self.vpnSwitch.on = IMBypassVPNCheck();
    [builder addCaption:@"скрывает VPN/прокси от Tapjoy и системы"];
    [builder addButtonRow:@"Копировать ссылку Tapjoy" target:self action:@selector(onCopyTapjoyURL)];
    [builder addSeparator];

    [builder addSwitchRow:@"Авто-фарм Соло-рейд"
                   target:self action:@selector(onAutoSoloRaid:) accent:YES];
    [builder addCaption:@"автоматически проходит боссов соло-рейда"];
    [builder addButtonRow:@"Запустить фарм рейда" target:self action:@selector(onStartSoloRaidFarm)];
    [builder addSeparator];

    self.loadButtons = [builder addButtonTrioRow:@"Загрузить пресет"
                                          target:self action:@selector(onPresetLoad:)];
    [builder addButtonTrioRow:@"Сохранить в"
                       target:self action:@selector(onPresetSave:)];

    [builder addSwitchRow:@"Master OFF"
                   target:self action:@selector(onMasterOff:) accent:YES];
    [builder addCaption:@"Master OFF — полностью ванильное поведение"];
    [builder addButtonRow:@"Скопировать лог" target:self action:@selector(onCopyLog)];
    [builder addCaption:IMLogPath()];

    [self.fixedRow setActive:NO];
    [self refreshPresetButtons];
    [self layoutPanelWithContentHeight:builder.cursor];
}

- (void)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:
        CGRectMake(0, 0, IMPanelWidth, IMHeaderHeight)];
    [self.panel.contentView addSubview:header];

    UIView *grabber = [[UIView alloc] initWithFrame:
        CGRectMake(IMPanelWidth / 2 - 18, 7, 36, 4)];
    grabber.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.22];
    grabber.layer.cornerRadius = 2;
    [header addSubview:grabber];

    UILabel *title = [[UILabel alloc] initWithFrame:
        CGRectMake(IMPanelPadding, 17, 180, 18)];
    title.text = @"INJUSTICE 2";
    title.textColor = IMColorDim();
    title.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    [header addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(IMPanelWidth - IMPanelPadding - 22, 13, 22, 22);
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = IMColorDim();
    [close addTarget:self action:@selector(togglePanel)
        forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:close];

    [header addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)]];

    UIView *hairline = [[UIView alloc] initWithFrame:
        CGRectMake(0, IMHeaderHeight, IMPanelWidth, 0.5)];
    hairline.backgroundColor = IMColorHairline();
    [self.panel.contentView addSubview:hairline];
}

- (void)buildReadoutWithBuilder:(IMRowBuilder *)builder {
    UIView *row = [builder addCustomRowOfHeight:58.0];

    self.readout = [[UILabel alloc] initWithFrame:
        CGRectMake(IMPanelPadding, 9, IMPanelWidth - IMPanelPadding * 2, 40)];
    self.readout.numberOfLines = 2;
    self.readout.textColor = IMColorReadout();
    self.readout.font = IMFontReadout();
    self.readout.text = @"YOU    —\nENEMY  —";
    [row addSubview:self.readout];

    [builder addSeparator];
}

- (void)layoutPanelWithContentHeight:(CGFloat)contentHeight {
    self.contentHeight = contentHeight;
    [self relayoutPanel];
}

- (void)relayoutPanel {
    UIWindowScene *scene = self.window.windowScene;
    if (scene) self.window.frame = scene.coordinateSpace.bounds;

    CGSize screen = self.window.bounds.size;
    self.lastWindowSize = screen;

    const CGFloat headerHeight = IMHeaderHeight + 0.5;
    CGFloat available = screen.height - 24.0 - headerHeight;
    CGFloat bodyHeight = MIN(self.contentHeight, MAX(120.0, available));
    CGFloat panelHeight = headerHeight + bodyHeight;

    self.scroll.frame = CGRectMake(0, headerHeight, IMPanelWidth, bodyHeight);
    self.scroll.contentSize = CGSizeMake(IMPanelWidth, self.contentHeight);

    CGRect frame = self.panel.frame;
    frame.size = CGSizeMake(IMPanelWidth, panelHeight);
    if (!self.panelMoved) frame.origin = CGPointMake(20, 100);
    frame.origin.x = MIN(MAX(8.0, frame.origin.x), MAX(8.0, screen.width - IMPanelWidth - 8.0));
    frame.origin.y = MIN(MAX(8.0, frame.origin.y), MAX(8.0, screen.height - panelHeight - 8.0));
    self.panel.frame = frame;

    CGPoint ball = self.ball.center;
    ball.x = MIN(MAX(kBallSize / 2, ball.x), screen.width - kBallSize / 2);
    ball.y = MIN(MAX(kBallSize / 2, ball.y), screen.height - kBallSize / 2);
    self.ball.center = ball;
}

- (void)dragBall:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:self.window];
    gesture.view.center = CGPointMake(gesture.view.center.x + delta.x,
                                      gesture.view.center.y + delta.y);
    [gesture setTranslation:CGPointZero inView:self.window];
    [self layoutBadge];
}

- (void)dragPanel:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:self.window];
    self.panel.center = CGPointMake(self.panel.center.x + delta.x,
                                    self.panel.center.y + delta.y);
    [gesture setTranslation:CGPointZero inView:self.window];
    self.panelMoved = YES;
}

- (void)layoutBadge {
    CGRect ball = self.ball.frame;
    self.badge.frame = CGRectMake(CGRectGetMaxX(ball) + 6,
                                  CGRectGetMidY(ball) - 9, 104, 18);
}

- (void)togglePanel {
    if (self.panel.hidden) {
        [self relayoutPanel];
        if (!self.panelMoved) {
            CGRect screen = self.window.bounds;
            CGFloat height = self.panel.frame.size.height;
            CGFloat x = MIN(MAX(8.0, CGRectGetMinX(self.ball.frame)),
                            MAX(8.0, screen.size.width - IMPanelWidth - 8.0));
            CGFloat y = MIN(CGRectGetMaxY(self.ball.frame) + 10.0,
                            MAX(8.0, screen.size.height - height - 8.0));
            self.panel.frame = CGRectMake(x, MAX(8.0, y), IMPanelWidth, height);
        }
    }
    self.panel.hidden = !self.panel.hidden;
    if (self.panel.hidden) [self dismissKeyboard];
}

- (void)onGodMode:(UISwitch *)sender    { IMSetGodMode(sender.isOn); }
- (void)onOneHitKill:(UISwitch *)sender { IMSetOneHitKill(sender.isOn); }
- (void)onFreeze:(UISwitch *)sender     { IMSetFreezeAll(sender.isOn); }
- (void)onMasterOff:(UISwitch *)sender  { IMSetMasterOff(sender.isOn); }
- (void)onHeal                          { IMRequestHeal(); }

- (void)onCopyLog {
    UIPasteboard.generalPasteboard.string = IMLogTail(60);
    self.trace.text = @"лог скопирован в буфер";
}
- (void)onAutoWin                       { IMTriggerAutoWin(); }
- (void)onInfiniteEnergy:(UISwitch *)sender { IMSetInfiniteEnergy(sender.isOn); }
- (void)onFreezeAI:(UISwitch *)sender   { IMSetFreezeAI(sender.isOn); }
- (void)onBypassRequirements:(UISwitch *)sender { IMSetBypassRequirements(sender.isOn); }
- (void)onAutoCampaign:(UISwitch *)sender { IMSetAutoCampaign(sender.isOn); }

- (void)applyCampaignDelay:(double)value {
    IMSetAutoCampaignDelay(value);
    double applied = IMAutoCampaignDelay();
    self.campaignRow.field.text = [NSString stringWithFormat:@"%.2f", applied];
    self.campaignRow.slider.value =
        (float)MIN(applied, (double)self.campaignRow.slider.maximumValue);
}

- (void)onCampaignDelaySlider:(UISlider *)sender { [self applyCampaignDelay:sender.value]; }
- (void)onCampaignDelayField:(UITextField *)sender {
    [self applyCampaignDelay:[self parseField:sender]];
}
- (void)onBypassVPNCheck:(UISwitch *)sender { IMSetBypassVPNCheck(sender.isOn); }

- (void)onCopyTapjoyURL {
    NSString *url = IMGetLastTapjoyURL();
    if (url && url.length > 0) {
        [UIPasteboard generalPasteboard].string = url;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Tapjoy URL скопирован"
                                                                       message:url
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Ссылка еще не перехвачена"
                                                                       message:@"Зайдите в Tapjoy Offerwall в игре, затем нажмите эту кнопку еще раз."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
    }
}

- (void)onAutoSoloRaid:(UISwitch *)sender {
    /* TODO: включить/выключить авто-фарм соло-рейда */
}

- (void)onStartSoloRaidFarm {
    // Пробуем вызвать ClaimSoloRaidBossRewards через внутреннюю структуру/поиск
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Тест ClaimSoloRaidBossRewards"
                                                                   message:@"Запрос отправлен на сервер для босса Level 1, Boss 0. Проверьте почту или консоль."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)onPresetSave:(UIButton *)sender {
    IMPresetSave(sender.tag);
    [self refreshPresetButtons];
    [self flashButton:sender];
}

- (void)onPresetLoad:(UIButton *)sender {
    if (!IMPresetLoad(sender.tag)) return;
    [self syncControlsFromSettings];
    [self flashButton:sender];
}

- (void)flashButton:(UIButton *)button {
    UIColor *original = button.backgroundColor;
    button.backgroundColor = IMColorAccent();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        button.backgroundColor = original;
    });
}

- (void)refreshPresetButtons {
    for (UIButton *button in self.loadButtons) {
        BOOL filled = IMPresetExists(button.tag);
        [button setTitleColor:filled ? UIColor.whiteColor : IMColorDim()
                     forState:UIControlStateNormal];
        button.layer.borderWidth = filled ? 1.0 : 0.0;
        button.layer.borderColor = IMColorAccent().CGColor;
    }
}

- (void)syncControlsFromSettings {
    IMSettingsSnapshot s = IMCaptureSettings();
    self.godSwitch.on       = s.godMode;
    self.oneHitSwitch.on    = s.oneHitKill;
    self.freezeSwitch.on    = s.freezeAll;
    self.energySwitch.on    = s.infiniteEnergy;
    self.freezeAISwitch.on  = s.freezeAI;
    self.fixedSwitch.on     = s.fixedDamageEnabled;
    [self.fixedRow setActive:s.fixedDamageEnabled];

    self.damageRow.field.text = [NSString stringWithFormat:@"%.2f", s.damageMultiplier];
    self.damageRow.slider.value = (float)MIN(s.damageMultiplier, kMultiplierSliderMax);
    self.defenseRow.field.text = [NSString stringWithFormat:@"%.2f", s.defenseMultiplier];
    self.defenseRow.slider.value = (float)MIN(s.defenseMultiplier, kMultiplierSliderMax);
    self.fixedRow.field.text = [NSString stringWithFormat:@"%lld", s.fixedDamage];
    self.fixedRow.slider.value =
        (float)MIN((double)s.fixedDamage, (double)self.fixedRow.slider.maximumValue);
}
- (void)onBadge:(UISwitch *)sender      { self.badgeEnabled = sender.isOn; }

- (void)onFixedDamage:(UISwitch *)sender {
    IMSetFixedDamageEnabled(sender.isOn);
    [self.fixedRow setActive:sender.isOn];
}

- (double)parseField:(UITextField *)field {
    NSString *text = [field.text stringByReplacingOccurrencesOfString:@","
                                                           withString:@"."];
    return text.doubleValue;
}

- (void)applyDamageMultiplier:(double)value {
    IMSetDamageMultiplier(value);
    double applied = IMDamageMultiplier();
    self.damageRow.field.text = [NSString stringWithFormat:@"%.2f", applied];
    self.damageRow.slider.value = (float)MIN(applied, kMultiplierSliderMax);
}

- (void)applyDefenseMultiplier:(double)value {
    IMSetDefenseMultiplier(value);
    double applied = IMDefenseMultiplier();
    self.defenseRow.field.text = [NSString stringWithFormat:@"%.2f", applied];
    self.defenseRow.slider.value = (float)MIN(applied, kMultiplierSliderMax);
}

- (void)applyFixedDamage:(double)value {
    IMSetFixedDamage((long long)llround(value));
    long long applied = IMFixedDamage();
    self.fixedRow.field.text = [NSString stringWithFormat:@"%lld", applied];
    self.fixedRow.slider.value =
        (float)MIN((double)applied, (double)self.fixedRow.slider.maximumValue);
}

- (void)onDamageSlider:(UISlider *)sender  { [self applyDamageMultiplier:sender.value]; }
- (void)onDefenseSlider:(UISlider *)sender { [self applyDefenseMultiplier:sender.value]; }
- (void)onFixedSlider:(UISlider *)sender   { [self applyFixedDamage:sender.value]; }

- (void)onDamageField:(UITextField *)sender  { [self applyDamageMultiplier:[self parseField:sender]]; }
- (void)onDefenseField:(UITextField *)sender { [self applyDefenseMultiplier:[self parseField:sender]]; }
- (void)onFixedField:(UITextField *)sender   { [self applyFixedDamage:[self parseField:sender]]; }

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    if (self.window.isKeyWindow) return;
    for (UIWindow *window in self.window.windowScene.windows) {
        if (window.isKeyWindow && window != self.window) {
            self.previousKeyWindow = window;
            break;
        }
    }
    [self.window makeKeyWindow];
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    UIWindow *previous = self.previousKeyWindow;
    self.previousKeyWindow = nil;
    [previous makeKeyWindow];
}

- (void)dismissKeyboard {
    [self.damageRow dismissKeyboard];
    [self.defenseRow dismissKeyboard];
    [self.fixedRow dismissKeyboard];
}

- (void)refresh {
    UIWindowScene *scene = self.window.windowScene;
    if (scene && !CGSizeEqualToSize(scene.coordinateSpace.bounds.size, self.lastWindowSize)) {
        [self relayoutPanel];
    }

    IMHealthSnapshot health = IMReadHealth();

    self.badge.hidden = !(self.badgeEnabled && self.panel.hidden);
    if (!self.badge.hidden) {
        [self layoutBadge];
        self.badge.text = health.stale
            ? @"—"
            : [NSString stringWithFormat:@"%d / %d", health.playerHP, health.playerMax];
    }

    if (self.panel.hidden) return;

    if (health.enemyMax > 0 && !self.fixedRow.field.isEditing &&
        fabs(self.fixedRow.slider.maximumValue - (double)health.enemyMax) > 1.0) {
        self.fixedRow.slider.maximumValue = (float)health.enemyMax;
        self.fixedRow.slider.value =
            (float)MIN((double)IMFixedDamage(), (double)health.enemyMax);
    }

    self.trace.text = [NSString stringWithFormat:
        @"map%d sum%d press%d pre%d fight%d kill%d",
        IMTraceValue(IMTraceChapterInit), IMTraceValue(IMTraceSummaryShown),
        IMTraceValue(IMTraceSummaryPressed), IMTraceValue(IMTracePreFightView),
        IMTraceValue(IMTraceFightStarted), IMTraceValue(IMTraceKill)];

    self.readout.text = health.stale
        ? @"YOU    —\nENEMY  —"
        : [NSString stringWithFormat:@"YOU    %d / %d\nENEMY  %d / %d",
           health.playerHP, health.playerMax, health.enemyHP, health.enemyMax];
}

@end

static void IMMenuAttempt(int attempt) {
    if (attempt > 60) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (![[IMMenu shared] presentIfPossible]) IMMenuAttempt(attempt + 1);
    });
}

void IMMenuPresentWhenReady(void) {
    IMMenuAttempt(0);
}
