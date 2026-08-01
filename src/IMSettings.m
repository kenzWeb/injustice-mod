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

IMSettingsSnapshot IMCaptureSettings(void) {
    IMSettingsSnapshot s;
    s.godMode            = IMGodMode();
    s.oneHitKill         = IMOneHitKill();
    s.freezeAll          = IMFreezeAll();
    s.infiniteEnergy     = IMInfiniteEnergy();
    s.freezeAI           = IMFreezeAI();
    s.fixedDamageEnabled = IMFixedDamageEnabled();
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
    atomic_store(&sPlayerHP, hp);
    atomic_store(&sPlayerMax, max);
    atomic_store(&sLastSeenMs, IMNowMs());
}

void IMPublishEnemyHealth(int hp, int max) {
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
