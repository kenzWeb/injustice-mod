#import <Foundation/Foundation.h>
#import "IMLog.h"

// Network observer: logs the game's HTTP traffic (Hydra backend) so we can see
// exactly what the server enforces for solo-raid battles — request bodies and,
// where a completion handler is used, response bodies. Ad/analytics hosts are
// filtered out to keep the log focused on the game backend.

static BOOL IMNetIsNoise(NSString *host) {
    if (host.length == 0) return YES;
    static NSArray *bad;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bad = @[@"facebook", @"fbcdn", @"google", @"gstatic", @"crashlytics",
                @"firebase", @"ironsrc", @"ironsource", @"supersonicads", @"tapjoy",
                @"adjust", @"singular", @"swrve", @"unity3d", @"unityads", @"applovin",
                @"doubleclick", @"amazon-adsystem", @"branch", @"appsflyer", @"sentry",
                @"bugsnag", @"app-measurement", @"crashlyticsreports", @"gvt1", @"gvt2",
                @"moatads", @"mopub", @"vungle", @"chartboost", @"inmobi", @"adcolony"];
    });
    for (NSString *b in bad) {
        if ([host rangeOfString:b options:NSCaseInsensitiveSearch].location != NSNotFound)
            return YES;
    }
    return NO;
}

static NSString *IMNetBody(NSData *d) {
    if (d.length == 0) return @"(empty)";
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (s.length) return s.length > 3000 ? [s substringToIndex:3000] : s;
    const unsigned char *b = (const unsigned char *)d.bytes;
    NSMutableString *h = [NSMutableString stringWithFormat:@"(bin %lu) ", (unsigned long)d.length];
    for (NSUInteger i = 0; i < MIN(d.length, (NSUInteger)200); i++) [h appendFormat:@"%02x", b[i]];
    return h;
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    NSString *host = request.URL.host;
    if (IMNetIsNoise(host)) return %orig;

    NSString *url = request.URL.absoluteString ?: @"?";
    NSString *method = request.HTTPMethod ?: @"GET";
    IMLog("NET-> %s %s body=%s", method.UTF8String, url.UTF8String,
          IMNetBody(request.HTTPBody).UTF8String);

    if (!handler) return %orig;
    void (^wrap)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *resp, NSError *err) {
            long code = [resp isKindOfClass:NSHTTPURLResponse.class]
                            ? (long)[(NSHTTPURLResponse *)resp statusCode] : -1;
            IMLog("NET<- [%ld] %s resp=%s", code, url.UTF8String, IMNetBody(data).UTF8String);
            handler(data, resp, err);
        };
    return %orig(request, wrap);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSString *host = request.URL.host;
    if (!IMNetIsNoise(host)) {
        IMLog("NET-> (delegate) %s %s body=%s",
              (request.HTTPMethod ?: @"GET").UTF8String,
              (request.URL.absoluteString ?: @"?").UTF8String,
              IMNetBody(request.HTTPBody).UTF8String);
    }
    return %orig;
}

%end

// --- WebSocket (Hydra realtime may run over this) ---------------------------
static NSString *IMWSBody(NSURLSessionWebSocketMessage *m) {
    if (m.type == NSURLSessionWebSocketMessageTypeData) return IMNetBody(m.data);
    NSString *s = m.string ?: @"";
    return s.length > 3000 ? [s substringToIndex:3000] : s;
}

%hook NSURLSessionWebSocketTask

- (void)sendMessage:(NSURLSessionWebSocketMessage *)message
  completionHandler:(void (^)(NSError *))handler {
    IMLog("WS-> %s %s", self.currentRequest.URL.absoluteString.UTF8String ?: "?",
          IMWSBody(message).UTF8String);
    %orig;
}

- (void)receiveMessageWithCompletionHandler:(void (^)(NSURLSessionWebSocketMessage *, NSError *))handler {
    void (^wrap)(NSURLSessionWebSocketMessage *, NSError *) =
        ^(NSURLSessionWebSocketMessage *message, NSError *error) {
            if (message) IMLog("WS<- %s %s",
                               self.currentRequest.URL.absoluteString.UTF8String ?: "?",
                               IMWSBody(message).UTF8String);
            if (handler) handler(message, error);
        };
    %orig(wrap);
}

%end
