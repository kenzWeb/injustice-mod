#pragma once
#import <Foundation/Foundation.h>

BOOL  IMRuntimeResolveImage(void);
BOOL  IMRuntimeVersionMatches(void);
void *IMRuntimeAddress(uintptr_t rva);
const void *IMRuntimeImageBase(void);
uintptr_t IMRuntimeSlide(void);

BOOL IMIsPlayerCharacter(void *character);
int  IMCharacterCurrentHealth(void *character);
int  IMCharacterMaxHealth(void *character);
