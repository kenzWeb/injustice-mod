#import "IMLog.h"
#import <QuartzCore/QuartzCore.h>
#import <stdarg.h>
#import <stdio.h>
#import <pthread.h>

static FILE *sLogFile;
static NSString *sLogPath;
static pthread_mutex_t sLogLock = PTHREAD_MUTEX_INITIALIZER;
static double sStart;

NSString *IMLogPath(void) {
    return sLogPath ?: @"";
}

void IMLogInit(void) {
    if (sLogFile) return;

    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                        NSUserDomainMask, YES);
    NSString *dir = dirs.firstObject ?: NSTemporaryDirectory();
    sLogPath = [dir stringByAppendingPathComponent:@"immod.log"];
    sStart = CACurrentMediaTime();

    sLogFile = fopen(sLogPath.UTF8String, "w");
    if (!sLogFile) return;

    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    fprintf(sLogFile, "=== InjusticeMod log ===\n");
    fprintf(sLogFile, "build %s (%s)\n",
            [info[@"CFBundleShortVersionString"] UTF8String] ?: "?",
            [info[@"CFBundleVersion"] UTF8String] ?: "?");
    fflush(sLogFile);
}

void IMLog(const char *format, ...) {
    if (!sLogFile) return;

    pthread_mutex_lock(&sLogLock);
    fprintf(sLogFile, "[%8.3f] ", CACurrentMediaTime() - sStart);
    va_list args;
    va_start(args, format);
    vfprintf(sLogFile, format, args);
    va_end(args);
    fputc('\n', sLogFile);
    fflush(sLogFile);
    pthread_mutex_unlock(&sLogLock);
}

NSString *IMLogTail(int lines) {
    if (!sLogPath) return @"no log";

    pthread_mutex_lock(&sLogLock);
    if (sLogFile) fflush(sLogFile);
    NSString *whole = [NSString stringWithContentsOfFile:sLogPath
                                                encoding:NSUTF8StringEncoding
                                                   error:NULL];
    pthread_mutex_unlock(&sLogLock);

    if (!whole.length) return @"empty log";

    NSString *separator = [NSString stringWithFormat:@"%c", 10];
    NSArray<NSString *> *all = [whole componentsSeparatedByString:separator];
    NSUInteger take = MIN((NSUInteger)MAX(lines, 1), all.count);
    NSArray<NSString *> *tail =
        [all subarrayWithRange:NSMakeRange(all.count - take, take)];
    return [tail componentsJoinedByString:separator];
}
