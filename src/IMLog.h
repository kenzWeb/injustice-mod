#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void IMLogInit(void);
void IMLog(const char *format, ...) __attribute__((format(printf, 1, 2)));
NSString *IMLogPath(void);
NSString *IMLogTail(int lines);

#ifdef __cplusplus
}
#endif
