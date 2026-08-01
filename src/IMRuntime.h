#pragma once
#import <Foundation/Foundation.h>

// Tweak.xm is Objective-C++; these live in a plain .m file — keep C linkage.
#ifdef __cplusplus
extern "C" {
#endif

BOOL  IMRuntimeResolveImage(void);
BOOL  IMRuntimeVersionMatches(void);
void *IMRuntimeAddress(uintptr_t rva);
const void *IMRuntimeImageBase(void);
uintptr_t IMRuntimeSlide(void);

BOOL IMIsPlayerCharacter(void *character);
int  IMCharacterCurrentHealth(void *character);
int  IMCharacterMaxHealth(void *character);

#ifdef __cplusplus
}
#endif
