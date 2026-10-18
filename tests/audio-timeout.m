#import <Foundation/Foundation.h>
static NSString *LogFile(void) {
  return [NSTemporaryDirectory()
      stringByAppendingPathComponent:@"ntsd-audio-timeout-test.log"];
}
#include "../launcher/audio-tool-timeout.h"
int main(void) {
  @autoreleasepool {
    if (RunAudioTool(@"/usr/bin/true", @[], nil, 1.0) != 0)
      return 1;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    int result = RunAudioTool(@"/bin/sleep", @[ @"30" ], nil, 0.15);
    NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - started;
    printf("audio timeout: result=%d elapsed=%.3f seconds\n", result, elapsed);
    return result == 124 && elapsed < 1.5 ? 0 : 2;
  }
}
