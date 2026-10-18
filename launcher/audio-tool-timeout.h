// Included after LogFile() is defined in each launcher.
#include <signal.h>
#include <unistd.h>

static int RunAudioTool(NSString *path, NSArray<NSString *> *args,
                        NSDictionary *environment, NSTimeInterval timeout) {
    NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:LogFile()];
    if (!log) {
        [NSFileManager.defaultManager createFileAtPath:LogFile() contents:nil attributes:nil];
        log = [NSFileHandle fileHandleForWritingAtPath:LogFile()];
    }
    [log seekToEndOfFile];
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = args;
    if (environment) task.environment = environment;
    task.standardOutput = log;
    task.standardError = log;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return -1;

    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + timeout;
    while (task.running && NSProcessInfo.processInfo.systemUptime < deadline) usleep(20000);
    BOOL expired = task.running;
    if (expired) kill(task.processIdentifier, SIGKILL);
    [task waitUntilExit];
    if (expired) {
        [log seekToEndOfFile];
        NSString *message = [NSString stringWithFormat:@"Audio helper timed out after %.1f seconds.\n", timeout];
        [log writeData:[message dataUsingEncoding:NSUTF8StringEncoding]];
        return 124;
    }
    return task.terminationStatus;
}
