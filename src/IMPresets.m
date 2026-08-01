#import "IMPresets.h"
#import "IMSettings.h"

static NSString *IMPresetKey(NSInteger slot) {
    return [NSString stringWithFormat:@"IMMod.preset.%ld", (long)slot];
}

static BOOL IMSlotValid(NSInteger slot) {
    return slot >= 0 && slot < IM_PRESET_SLOTS;
}

void IMPresetSave(NSInteger slot) {
    if (!IMSlotValid(slot)) return;
    IMSettingsSnapshot s = IMCaptureSettings();
    NSDictionary *payload = @{
        @"godMode"            : @(s.godMode),
        @"oneHitKill"         : @(s.oneHitKill),
        @"freezeAll"          : @(s.freezeAll),
        @"infiniteEnergy"     : @(s.infiniteEnergy),
        @"freezeAI"           : @(s.freezeAI),
        @"fixedDamageEnabled" : @(s.fixedDamageEnabled),
        @"fixedDamage"        : @(s.fixedDamage),
        @"damageMultiplier"   : @(s.damageMultiplier),
        @"defenseMultiplier"  : @(s.defenseMultiplier),
    };
    [NSUserDefaults.standardUserDefaults setObject:payload forKey:IMPresetKey(slot)];
}

BOOL IMPresetExists(NSInteger slot) {
    if (!IMSlotValid(slot)) return NO;
    return [NSUserDefaults.standardUserDefaults dictionaryForKey:IMPresetKey(slot)] != nil;
}

BOOL IMPresetLoad(NSInteger slot) {
    if (!IMSlotValid(slot)) return NO;
    NSDictionary *payload =
        [NSUserDefaults.standardUserDefaults dictionaryForKey:IMPresetKey(slot)];
    if (!payload) return NO;

    IMSettingsSnapshot s;
    s.godMode            = [payload[@"godMode"] boolValue];
    s.oneHitKill         = [payload[@"oneHitKill"] boolValue];
    s.freezeAll          = [payload[@"freezeAll"] boolValue];
    s.infiniteEnergy     = [payload[@"infiniteEnergy"] boolValue];
    s.freezeAI           = [payload[@"freezeAI"] boolValue];
    s.fixedDamageEnabled = [payload[@"fixedDamageEnabled"] boolValue];
    s.fixedDamage        = [payload[@"fixedDamage"] longLongValue];
    s.damageMultiplier   = [payload[@"damageMultiplier"] doubleValue];
    s.defenseMultiplier  = [payload[@"defenseMultiplier"] doubleValue];
    IMApplySettings(s);
    return YES;
}
