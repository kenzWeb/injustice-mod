#import "IMSettings.h"
#import <stdatomic.h>
#import <QuartzCore/QuartzCore.h>

static const long long kScale = 100000LL;
static const long long kStaleMs = 3000LL;

static atomic_bool sMasterOff;
static atomic_bool sGodMode;
static atomic_bool sOneHitKill;
static atomic_bool sFreezeAll;
static atomic_bool sFixedDamageEnabled;
static atomic_bool sHealRequested;
static atomic_bool sInfiniteEnergy;
static atomic_bool sFreezeAI;
static atomic_bool sBypassRequirements;
static atomic_bool sAutoCampaign;
static atomic_llong sCombatStartMs;
static atomic_llong sAutoCampaignDelayMs;
static atomic_llong sLastAutoStartMs;
static atomic_llong sLastAutoFightMs;
static atomic_llong sLastAutoSummaryMs;
static atomic_llong sLastChapterAdvanceMs;
static atomic_bool sBypassVPNCheck;
static atomic_llong sAutoWinDeadlineMs;

static atomic_llong sFixedDamage;
static atomic_llong sDamageMultiplierScaled;
static atomic_llong sDefenseMultiplierScaled;

static atomic_int  sPlayerHP;
static atomic_int  sPlayerMax;
static atomic_int  sEnemyHP;
static atomic_int  sEnemyMax;
static atomic_llong sLastSeenMs;

static inline long long IMNowMs(void) {
    return (long long)(CACurrentMediaTime() * 1000.0);
}

static inline double IMClampD(double v, double lo, double hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

void IMSettingsInit(void) {
    atomic_store(&sDamageMultiplierScaled, kScale);
    atomic_store(&sDefenseMultiplierScaled, kScale);
    atomic_store(&sFixedDamage, 1000LL);
    atomic_store(&sAutoCampaignDelayMs, 1500LL);
    atomic_store(&sBypassVPNCheck, true);
}

BOOL IMMasterOff(void) { return atomic_load(&sMasterOff); }
void IMSetMasterOff(BOOL on) { atomic_store(&sMasterOff, on); }

BOOL IMGodMode(void) { return atomic_load(&sGodMode); }
void IMSetGodMode(BOOL on) { atomic_store(&sGodMode, on); }

BOOL IMOneHitKill(void) { return atomic_load(&sOneHitKill); }
void IMSetOneHitKill(BOOL on) { atomic_store(&sOneHitKill, on); }

BOOL IMFreezeAll(void) { return atomic_load(&sFreezeAll); }
void IMSetFreezeAll(BOOL on) { atomic_store(&sFreezeAll, on); }

BOOL IMFixedDamageEnabled(void) { return atomic_load(&sFixedDamageEnabled); }
void IMSetFixedDamageEnabled(BOOL on) { atomic_store(&sFixedDamageEnabled, on); }

long long IMFixedDamage(void) { return atomic_load(&sFixedDamage); }

void IMSetFixedDamage(long long value) {
    if (value < 0) value = 0;
    if (value > IM_FIXED_DAMAGE_MAX) value = IM_FIXED_DAMAGE_MAX;
    atomic_store(&sFixedDamage, value);
}

double IMDamageMultiplier(void) {
    return (double)atomic_load(&sDamageMultiplierScaled) / (double)kScale;
}

void IMSetDamageMultiplier(double value) {
    value = IMClampD(value, 0.0, IM_MULTIPLIER_MAX);
    atomic_store(&sDamageMultiplierScaled, (long long)llround(value * (double)kScale));
}

double IMDefenseMultiplier(void) {
    return (double)atomic_load(&sDefenseMultiplierScaled) / (double)kScale;
}

void IMSetDefenseMultiplier(double value) {
    value = IMClampD(value, 0.0, IM_MULTIPLIER_MAX);
    atomic_store(&sDefenseMultiplierScaled, (long long)llround(value * (double)kScale));
}

BOOL IMInfiniteEnergy(void) { return atomic_load(&sInfiniteEnergy); }
void IMSetInfiniteEnergy(BOOL on) { atomic_store(&sInfiniteEnergy, on); }

BOOL IMFreezeAI(void) { return atomic_load(&sFreezeAI); }
void IMSetFreezeAI(BOOL on) { atomic_store(&sFreezeAI, on); }

BOOL IMBypassRequirements(void) { return atomic_load(&sBypassRequirements); }
void IMSetBypassRequirements(BOOL on) { atomic_store(&sBypassRequirements, on); }

BOOL IMAutoCampaign(void) { return atomic_load(&sAutoCampaign); }

void IMSetAutoCampaign(BOOL on) {
    atomic_store(&sAutoCampaign, on);
    if (!on) {
        atomic_store(&sCombatStartMs, 0);
        atomic_store(&sLastAutoStartMs, 0);
        atomic_store(&sLastAutoFightMs, 0);
        atomic_store(&sLastAutoSummaryMs, 0);
        atomic_store(&sLastChapterAdvanceMs, 0);
    }
}

double IMAutoCampaignDelay(void) {
    return (double)atomic_load(&sAutoCampaignDelayMs) / 1000.0;
}

void IMSetAutoCampaignDelay(double seconds) {
    if (seconds < 0.0) seconds = 0.0;
    if (seconds > 30.0) seconds = 30.0;
    atomic_store(&sAutoCampaignDelayMs, (long long)llround(seconds * 1000.0));
}

BOOL IMAutoCampaignShouldFinish(void) {
    if (!atomic_load(&sAutoCampaign)) return NO;
    long long started = atomic_load(&sCombatStartMs);
    if (started <= 0) return NO;
    return (IMNowMs() - started) >= atomic_load(&sAutoCampaignDelayMs);
}

BOOL IMAutoCampaignMayPressSummary(void) {
    if (!atomic_load(&sAutoCampaign)) return NO;
    long long now = IMNowMs();
    long long last = atomic_load(&sLastAutoSummaryMs);
    if (last > 0 && now - last < 4000LL) return NO;
    atomic_store(&sLastAutoSummaryMs, now);
    return YES;
}

BOOL IMAutoCampaignMayAdvanceChapter(void) {
    if (!atomic_load(&sAutoCampaign)) return NO;
    long long now = IMNowMs();
    long long last = atomic_load(&sLastChapterAdvanceMs);
    if (last > 0 && now - last < 20000LL) return NO;
    atomic_store(&sLastChapterAdvanceMs, now);
    return YES;
}

BOOL IMAutoCampaignMayPressFight(void) {
    if (!atomic_load(&sAutoCampaign)) return NO;
    long long now = IMNowMs();
    long long last = atomic_load(&sLastAutoFightMs);
    if (last > 0 && now - last < 4000LL) return NO;
    atomic_store(&sLastAutoFightMs, now);
    return YES;
}

BOOL IMAutoCampaignMayStartBattle(void) {
    if (!atomic_load(&sAutoCampaign)) return NO;
    long long now = IMNowMs();
    long long last = atomic_load(&sLastAutoStartMs);
    if (last > 0 && now - last < 4000LL) return NO;
    atomic_store(&sLastAutoStartMs, now);
    return YES;
}

BOOL IMInCombat(void) {
    long long last = atomic_load(&sLastSeenMs);
    if (last <= 0) return NO;
    return (IMNowMs() - last) < 1500LL;
}

static atomic_int sTrace[IMTraceCount];

void IMTraceBump(IMTraceEvent event) {
    if (event < 0 || event >= IMTraceCount) return;
    atomic_fetch_add(&sTrace[event], 1);
}

int IMTraceValue(IMTraceEvent event) {
    if (event < 0 || event >= IMTraceCount) return 0;
    return atomic_load(&sTrace[event]);
}

void IMTraceReset(void) {
    for (int i = 0; i < IMTraceCount; i++) atomic_store(&sTrace[i], 0);
}

static void IMNoteCombatTick(void) {
    long long now = IMNowMs();
    long long last = atomic_load(&sLastSeenMs);
    if (last <= 0 || now - last > kStaleMs) atomic_store(&sCombatStartMs, now);
}

BOOL IMBypassVPNCheck(void) { return atomic_load(&sBypassVPNCheck); }
void IMSetBypassVPNCheck(BOOL on) { atomic_store(&sBypassVPNCheck, on); }

IMSettingsSnapshot IMCaptureSettings(void) {
    IMSettingsSnapshot s;
    s.godMode            = IMGodMode();
    s.oneHitKill         = IMOneHitKill();
    s.freezeAll          = IMFreezeAll();
    s.infiniteEnergy     = IMInfiniteEnergy();
    s.freezeAI           = IMFreezeAI();
    s.fixedDamageEnabled = IMFixedDamageEnabled();
    s.bypassVPNCheck     = IMBypassVPNCheck();
    s.fixedDamage        = IMFixedDamage();
    s.damageMultiplier   = IMDamageMultiplier();
    s.defenseMultiplier  = IMDefenseMultiplier();
    return s;
}

void IMApplySettings(IMSettingsSnapshot s) {
    IMSetGodMode(s.godMode);
    IMSetOneHitKill(s.oneHitKill);
    IMSetFreezeAll(s.freezeAll);
    IMSetInfiniteEnergy(s.infiniteEnergy);
    IMSetFreezeAI(s.freezeAI);
    IMSetFixedDamageEnabled(s.fixedDamageEnabled);
    IMSetBypassVPNCheck(s.bypassVPNCheck);
    IMSetFixedDamage(s.fixedDamage);
    IMSetDamageMultiplier(s.damageMultiplier);
    IMSetDefenseMultiplier(s.defenseMultiplier);
}

void IMRequestHeal(void) { atomic_store(&sHealRequested, true); }
BOOL IMConsumeHealRequest(void) { return atomic_exchange(&sHealRequested, false); }

void IMTriggerAutoWin(void) {
    atomic_store(&sAutoWinDeadlineMs, IMNowMs() + 2500LL);
}

BOOL IMAutoWinActive(void) {
    return IMNowMs() < atomic_load(&sAutoWinDeadlineMs);
}

void IMPublishPlayerHealth(int hp, int max) {
    IMNoteCombatTick();
    atomic_store(&sPlayerHP, hp);
    atomic_store(&sPlayerMax, max);
    atomic_store(&sLastSeenMs, IMNowMs());
}

void IMPublishEnemyHealth(int hp, int max) {
    IMNoteCombatTick();
    atomic_store(&sEnemyHP, hp);
    atomic_store(&sEnemyMax, max);
    atomic_store(&sLastSeenMs, IMNowMs());
}

IMHealthSnapshot IMReadHealth(void) {
    IMHealthSnapshot s;
    s.playerHP  = atomic_load(&sPlayerHP);
    s.playerMax = atomic_load(&sPlayerMax);
    s.enemyHP   = atomic_load(&sEnemyHP);
    s.enemyMax  = atomic_load(&sEnemyMax);
    s.stale     = (IMNowMs() - atomic_load(&sLastSeenMs)) > kStaleMs;
    return s;
}

static NSString *sLastTapjoyURL = @"";

void IMPublishTapjoyURL(NSString *urlString) {
    if (!urlString || urlString.length == 0) return;
    @synchronized(sLastTapjoyURL) {
        sLastTapjoyURL = [urlString copy];
    }
    NSLog(@"[TapjoyURL] Captured Offerwall URL: %@", urlString);
}

NSString *IMGetLastTapjoyURL(void) {
    @synchronized(sLastTapjoyURL) {
        return [sLastTapjoyURL copy];
    }
}
