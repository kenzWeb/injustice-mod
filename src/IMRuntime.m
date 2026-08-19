#import "IMRuntime.h"
#import "Offsets.h"
#import <mach-o/dyld.h>
#import <string.h>

static const struct mach_header *sImageBase;
static uintptr_t sSlide;
static uintptr_t sTextLo;
static uintptr_t sTextHi;
static uintptr_t sImageHi;

static BOOL IMImageNameMatches(const char *name) {
    return name && strstr(name, "Injustice2Mobile") != NULL;
}

BOOL IMRuntimeResolveImage(void) {
    sImageBase = _dyld_get_image_header(0);
    sSlide = (uintptr_t)_dyld_get_image_vmaddr_slide(0);

    if (!IMImageNameMatches(_dyld_get_image_name(0))) {
        sImageBase = NULL;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            if (IMImageNameMatches(_dyld_get_image_name(i))) {
                sImageBase = _dyld_get_image_header(i);
                sSlide = (uintptr_t)_dyld_get_image_vmaddr_slide(i);
                break;
            }
        }
    }
    if (!sImageBase) return NO;

    sTextLo  = (uintptr_t)sImageBase;
    sTextHi  = sTextLo + SEG_TextEnd;
    sImageHi = sTextLo + SEG_ImageEnd;
    return YES;
}

BOOL IMRuntimeVersionMatches(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return [info[@"CFBundleVersion"] isEqualToString:kExpectedBundleVersion] &&
           [info[@"CFBundleShortVersionString"] isEqualToString:kExpectedShortVersion];
}

void *IMRuntimeAddress(uintptr_t rva) {
    return (void *)((uintptr_t)sImageBase + rva);
}

const void *IMRuntimeImageBase(void) { return sImageBase; }
uintptr_t IMRuntimeSlide(void) { return sSlide; }

BOOL IMLooksLikeObject(void *obj) {
    uintptr_t p = (uintptr_t)obj;
    if (p < 0x100000000ULL) return NO;                 // null / too small
    if (p & 0xFFFF000000000000ULL) return NO;          // non-canonical — don't deref
    uintptr_t vptr = *(uintptr_t *)p;                  // safe-ish to read now
    if (vptr & 0xFFFF000000000000ULL) return NO;
    return vptr >= sTextLo && vptr < sImageHi;          // vtable inside game image
}

BOOL IMIsPlayerCharacter(void *character) {
    if (!character) return NO;
    uintptr_t vptr = *(uintptr_t *)character;
    if (vptr < sTextLo || vptr >= sImageHi) return NO;
    uintptr_t fn = *(uintptr_t *)(vptr + VT_IsPlayerCharacter);
    if (fn < sTextLo || fn >= sTextHi) return NO;
    typedef bool (*IMIsPlayerFn)(void *);
    return ((IMIsPlayerFn)fn)(character) ? YES : NO;
}

int IMCharacterCurrentHealth(void *character) {
    return character ? *(int *)((uintptr_t)character + OFF_CurrentHealth) : 0;
}

int IMCharacterMaxHealth(void *character) {
    return character ? *(int *)((uintptr_t)character + OFF_MaxHealth) : 0;
}
