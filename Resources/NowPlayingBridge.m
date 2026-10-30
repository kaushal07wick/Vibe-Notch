#import <Foundation/Foundation.h>
#include <dlfcn.h>
// Loaded by /usr/bin/perl (allowed by mediaremoted) to read/drive system now-playing.
typedef void (*GetInfo)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetPlaying)(dispatch_queue_t, void (^)(BOOL));
typedef BOOL (*SendCmd)(int, NSDictionary *);
static void *mr(void) { return dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW); }
void vn_get(void *a, void *b) {
  @autoreleasepool {
    void *h = mr(); GetInfo f = (GetInfo)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    __block NSMutableDictionary *out = [NSMutableDictionary dictionary];
    f(dispatch_get_global_queue(0, 0), ^(NSDictionary *i) {
      NSString *t = i[@"kMRMediaRemoteNowPlayingInfoTitle"], *ar = i[@"kMRMediaRemoteNowPlayingInfoArtist"];
      if (t) out[@"title"] = t; if (ar) out[@"artist"] = ar;
      NSNumber *rate = i[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]; out[@"playing"] = @(rate.doubleValue > 0);
      NSData *art = i[@"kMRMediaRemoteNowPlayingInfoArtworkData"]; if (art) out[@"art"] = [art base64EncodedStringWithOptions:0];
      dispatch_semaphore_signal(s);
    });
    dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    NSData *j = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
    fwrite(j.bytes, 1, j.length, stdout); fflush(stdout);
  }
}
void vn_cmd(void *a, void *b) {
  const char *c = getenv("VN_CMD"); if (!c) return;
  SendCmd f = (SendCmd)dlsym(mr(), "MRMediaRemoteSendCommand");
  f(atoi(c), nil);   // 2 toggle play/pause, 4 next, 5 previous
  CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false); // let the XPC send go out before exit
}
