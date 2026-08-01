#pragma once
#import <Foundation/Foundation.h>

#define IM_PRESET_SLOTS 3

void IMPresetSave(NSInteger slot);
BOOL IMPresetLoad(NSInteger slot);
BOOL IMPresetExists(NSInteger slot);
