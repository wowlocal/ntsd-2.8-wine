// NTSD launcher.
//
// First run: copies the game out of the (read-only) bundle, creates a private
// ARM64 Wine prefix, showing a small
// progress window. Later runs start the game straight away, without any UI.
// The game's Wine process appears in the Dock under this app's name and icon.
// Hold Option while opening the app for extra actions.

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

static BOOL IsRussian(void) {
    NSString *lang = NSLocale.preferredLanguages.firstObject ?: @"en";
    return [lang hasPrefix:@"ru"] || [lang hasPrefix:@"uk"] || [lang hasPrefix:@"be"] || [lang hasPrefix:@"kk"];
}

static NSString *T(NSString *ru, NSString *en) { return IsRussian() ? ru : en; }

#pragma mark - Paths

static NSString *Res(NSString *path) {
    return [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:path];
}

static NSString *SupportDir(void) {
    NSString *override = NSProcessInfo.processInfo.environment[@"NTSD_SUPPORT_DIR"];
    if (override.length && override.isAbsolutePath) return override;
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return [base stringByAppendingPathComponent:@"NTSD"];
}

static NSString *PrefixDir(void) { return [SupportDir() stringByAppendingPathComponent:@"Prefix-arm64"]; }
static NSString *GameDir(void) { return [SupportDir() stringByAppendingPathComponent:@"Game"]; }
static NSString *StampFile(void) { return [SupportDir() stringByAppendingPathComponent:@".setup-version-arm64"]; }
static NSString *LogFile(void) { return [SupportDir() stringByAppendingPathComponent:@"Logs/NTSD.log"]; }
static NSString *Wine(NSString *tool) { return Res([@"runtime/dist/bin" stringByAppendingPathComponent:tool]); }
static NSString *BuildID(void) { return NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"0"; }

#pragma mark - State checks

static BOOL NeedsSetup(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *stamp = [NSString stringWithContentsOfFile:StampFile() encoding:NSUTF8StringEncoding error:nil];
    return !([stamp isEqualToString:BuildID()]
             && [fm fileExistsAtPath:[GameDir() stringByAppendingPathComponent:@"NTSD.exe"]]
             && [fm fileExistsAtPath:[PrefixDir() stringByAppendingPathComponent:@"system.reg"]]);
}

static BOOL OptionKeyDown(void) {
    return (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & kCGEventFlagMaskAlternate) != 0;
}

#pragma mark - Wine

// forSetup: wineboot runs without the Mac display driver so it can't pop up
// its own "updating configuration" window over ours.
static NSDictionary<NSString *, NSString *> *WineEnvironment(BOOL forSetup) {
    // Only named settings reach Windows processes; do not inherit host secrets,
    // Intel runtime paths, injected libraries or a caller's Wine prefix.
    NSDictionary *host = NSProcessInfo.processInfo.environment;
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"HOME", @"USER", @"LOGNAME", @"LANG", @"TMPDIR"]) {
        if (host[key]) env[key] = host[key];
    }
    env[@"PATH"] = @"/usr/bin:/bin:/usr/sbin:/sbin";
    NSString *gst = Res(@"runtime/dist/gstreamer");
    env[@"HADRON_SUPPORT"] = [SupportDir() stringByAppendingPathComponent:@"ARM64"];
    env[@"HADRON_PROGRAM"] = @"1";
    env[@"HADRON_APP_NAME"] = @"NTSD";
    env[@"HADRON_D3D9"] = @"wined3d";
    // This small DirectDraw game needs no persistent translator cache.
    env[@"FEX_DISKCACHE"] = @"0";
    env[@"DYLD_FALLBACK_LIBRARY_PATH"] = Res(@"runtime/dist/ext/lib");
    env[@"WINEPREFIX"] = PrefixDir();
    env[@"WINEDEBUG"] = host[@"NTSD_WINEDEBUG"] ?: @"-all";
    env[@"MVK_CONFIG_LOG_LEVEL"] = @"0";
    env[@"WINEDLLOVERRIDES"] = forSetup ? @"mscoree,mshtml=;winemenubuilder.exe=d;winemac.drv=d"
                                        : @"mscoree,mshtml=;winemenubuilder.exe=d";
    env[@"GST_PLUGIN_SYSTEM_PATH_1_0"] = [gst stringByAppendingPathComponent:@"lib/gstreamer-1.0"];
    env[@"GST_PLUGIN_SCANNER_1_0"] = [gst stringByAppendingPathComponent:@"libexec/gstreamer-1.0/gst-plugin-scanner"];
    env[@"GST_REGISTRY_1_0"] = [SupportDir() stringByAppendingPathComponent:@"ARM64/cache/gstreamer-registry-0.3.1.bin"];
    return env;
}

static char **EnvironmentBlock(NSDictionary<NSString *, NSString *> *env) {
    char **block = calloc(env.count + 1, sizeof(char *));
    __block NSUInteger i = 0;
    [env enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        block[i++] = strdup([NSString stringWithFormat:@"%@=%@", key, value].UTF8String);
    }];
    return block;
}

// Hadron's play script supplies the FEX/graphics/media environment and watchdog.
static int SpawnGame(pid_t *pid) {
    const char *runner = Res(@"runtime/scripts/play").fileSystemRepresentation;
    const char *exe = [GameDir() stringByAppendingPathComponent:@"NTSD.exe"].fileSystemRepresentation;
    char *argv[] = {(char *)runner, "ntsd", (char *)exe, NULL};
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addchdir(&actions, GameDir().fileSystemRepresentation);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, LogFile().fileSystemRepresentation,
                                     O_WRONLY | O_CREAT | O_APPEND, 0644);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    char **env = EnvironmentBlock(WineEnvironment(NO));
    int rc = posix_spawn(pid, runner, &actions, NULL, argv, env);
    for (char **entry = env; *entry; entry++) free(*entry);
    free(env);
    posix_spawn_file_actions_destroy(&actions);
    return rc;
}

// Hadron's per-game Wine loader bundle switches to a regular app once its
// window is up. Match its path too, so isolated test installs stay independent.
static NSRunningApplication *GameApplication(void) {
    NSString *bundle = @"com.broyojo.hadron.game.ntsd";
    NSString *expected = [[SupportDir() stringByAppendingPathComponent:@"ARM64/apps/ntsd/NTSD.app"] stringByResolvingSymlinksInPath];
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle]) {
        if (![[app.bundleURL.path stringByResolvingSymlinksInPath] isEqualToString:expected]) continue;
        if (app.processIdentifier != getpid() && app.activationPolicy == NSApplicationActivationPolicyRegular) return app;
    }
    return nil;
}

static int RunTool(NSString *path, NSArray<NSString *> *args, NSDictionary *env) {
    NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:LogFile()];
    if (!log) {
        [NSFileManager.defaultManager createFileAtPath:LogFile() contents:nil attributes:nil];
        log = [NSFileHandle fileHandleForWritingAtPath:LogFile()];
    }
    [log seekToEndOfFile];
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = args;
    if (env) task.environment = env;
    task.standardOutput = log;
    task.standardError = log;
    NSError *error;
    if (![task launchAndReturnError:&error]) return -1;
    [task waitUntilExit];
    return task.terminationStatus;
}

#pragma mark - App

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property BOOL showOptions;
@property(strong) NSWindow *window;
@property(strong) NSTextField *statusLabel;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self buildMenu];
    if (self.showOptions) {
        [self comeForward];
        [self showOptionsMenu];
    } else {
        [self start];
    }
}

// The bundle is an LSUIElement so Wine's helper processes stay out of the
// Dock; the launcher opts into a Dock icon only while it shows UI.
- (void)comeForward {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    if (@available(macOS 14, *)) [NSApp activate];
    else [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildMenu {
    NSString *name = NSBundle.mainBundle.infoDictionary[@"CFBundleName"];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:[NSString stringWithFormat:T(@"Завершить %@", @"Quit %@"), name]
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    NSMenuItem *appItem = [NSMenuItem new];
    appItem.submenu = appMenu;
    NSMenu *mainMenu = [NSMenu new];
    [mainMenu addItem:appItem];
    NSApp.mainMenu = mainMenu;
}

- (void)showOptionsMenu {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Naruto: The Setting Dawn";
    alert.informativeText = T(@"Настройки игры и сохранения при сбросе Wine не удаляются.",
                              @"Resetting Wine keeps your game settings and recordings.");
    [alert addButtonWithTitle:T(@"Играть", @"Play")];
    [alert addButtonWithTitle:T(@"Открыть папку игры", @"Open Game Folder")];
    [alert addButtonWithTitle:T(@"Сбросить Wine", @"Reset Wine")];
    [alert addButtonWithTitle:T(@"Отмена", @"Cancel")];
    switch ([alert runModal]) {
        case NSAlertFirstButtonReturn:
            [self start];
            break;
        case NSAlertSecondButtonReturn:
            [self revealGameFolder];
            break;
        case NSAlertThirdButtonReturn:
            [self resetWine];
            break;
        default:
            [NSApp terminate:nil];
    }
}

- (void)revealGameFolder {
    NSString *exe = [GameDir() stringByAppendingPathComponent:@"NTSD.exe"];
    if ([NSFileManager.defaultManager fileExistsAtPath:exe]) {
        [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:exe]]];
        [NSApp terminate:nil];
    } else {
        [self start];  // nothing copied yet: do the first-run setup first
    }
}

- (void)resetWine {
    RunTool(Wine(@"wineserver"), @[@"-k"], WineEnvironment(YES));
    [NSFileManager.defaultManager removeItemAtPath:PrefixDir() error:nil];
    [NSFileManager.defaultManager removeItemAtPath:StampFile() error:nil];
    [self start];
}

- (void)start {
    NSRunningApplication *running = GameApplication();
    if (running) {  // already playing: just bring it forward
        [running activateWithOptions:NSApplicationActivateAllWindows];
        [NSApp terminate:nil];
        return;
    }
    if (!NeedsSetup()) {
        [self launchAndQuit];
        return;
    }
    [self comeForward];
    [self showWindow];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = [self performSetup];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) [self fail:error];
            else [self launchAndQuit];
        });
    });
}

- (NSString *)performSetup {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:SupportDir() withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:LogFile().stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:[SupportDir() stringByAppendingPathComponent:@"ARM64/cache"] withIntermediateDirectories:YES attributes:nil error:nil];

    [self setStatus:T(@"Копирую файлы игры…", @"Copying game files…")];
    // Key bindings the player changed since the last setup survive the refresh;
    // untouched ones pick up the new bundled defaults.
    NSString *controls = [GameDir() stringByAppendingPathComponent:@"data/control.txt"];
    NSDate *changed = [fm attributesOfItemAtPath:controls error:nil].fileModificationDate;
    NSDate *setUp = [fm attributesOfItemAtPath:StampFile() error:nil].fileModificationDate;
    NSData *playerControls = (changed && (!setUp || [changed compare:setUp] == NSOrderedDescending))
                                 ? [NSData dataWithContentsOfFile:controls] : nil;

    // ditto merges: bundled files are refreshed, the player's own files stay.
    if (RunTool(@"/usr/bin/ditto", @[Res(@"game"), GameDir()], nil) != 0)
        return T(@"Не удалось скопировать файлы игры.", @"Couldn't copy the game files.");
    [playerControls writeToFile:controls atomically:YES];

    [self setStatus:T(@"Настраиваю Wine…", @"Setting up Wine…")];
    NSDictionary *env = WineEnvironment(YES);
    if (RunTool(Wine(@"wine"), @[@"wineboot", @"-u"], env) != 0)
        return T(@"Wine не смог создать окружение.", @"Wine couldn't create its environment.");
    if (RunTool(Wine(@"wineserver"), @[@"-w"], env) != 0)
        return T(@"Не удалось завершить настройку Wine.", @"Wine setup did not finish.");

    [BuildID() writeToFile:StampFile() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return nil;
}

// Since macOS 14 an app can't bring itself forward unless the user launched
// it, and the game runs in Wine's own process. So the launcher, which the user
// did launch, waits for the game window, activates it, and only then quits.
- (void)launchAndQuit {
    if (self.window) self.statusLabel.stringValue = T(@"Запускаю игру…", @"Starting the game…");
    pid_t pid;
    int rc = SpawnGame(&pid);
    if (rc != 0) {
        [self fail:[NSString stringWithFormat:@"posix_spawn: %s", strerror(rc)]];
        return;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120];
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        int status;
        if (waitpid(pid, &status, WNOHANG) == pid) {
            [timer invalidate];
            [self fail:T(@"Игра закрылась сразу после запуска.", @"The game quit right after starting.")];
            return;
        }
        NSRunningApplication *game = GameApplication();
        if (game) {
            [timer invalidate];
            [game activateWithOptions:NSApplicationActivateAllWindows];
            [self.window orderOut:nil];
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];  // drop our Dock icon now
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
                [NSApp terminate:nil];
            });
        } else if (deadline.timeIntervalSinceNow < 0) {
            [timer invalidate];
            [NSApp terminate:nil];
        }
    }];
}

- (void)fail:(NSString *)message {
    [self.window orderOut:nil];
    [self comeForward];
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = T(@"Не удалось запустить игру", @"Couldn't start the game");
    alert.informativeText = message;
    [alert addButtonWithTitle:T(@"Закрыть", @"Close")];
    [alert addButtonWithTitle:T(@"Показать журнал", @"Show Log")];
    if ([alert runModal] == NSAlertSecondButtonReturn)
        [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:LogFile()]];
    [NSApp terminate:nil];
}

- (void)setStatus:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.stringValue = text; });
}

- (void)showWindow {
    if (self.window) return;
    NSRect frame = NSMakeRect(0, 0, 420, 340);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.movableByWindowBackground = YES;
    window.releasedWhenClosed = NO;

    NSVisualEffectView *background = [[NSVisualEffectView alloc] initWithFrame:frame];
    background.material = NSVisualEffectMaterialUnderWindowBackground;
    background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    background.state = NSVisualEffectStateActive;
    window.contentView = background;

    NSImageView *icon = [NSImageView imageViewWithImage:NSApp.applicationIconImage];
    [icon.widthAnchor constraintEqualToConstant:128].active = YES;
    [icon.heightAnchor constraintEqualToConstant:128].active = YES;

    NSTextField *title = [NSTextField labelWithString:@"Naruto: The Setting Dawn"];
    title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];

    self.statusLabel = [NSTextField labelWithString:T(@"Готовлю игру к первому запуску…", @"Getting the game ready…")];
    self.statusLabel.font = [NSFont systemFontOfSize:13];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;

    NSProgressIndicator *bar = [NSProgressIndicator new];
    bar.style = NSProgressIndicatorStyleBar;
    bar.indeterminate = YES;
    [bar startAnimation:nil];
    [bar.widthAnchor constraintEqualToConstant:280].active = YES;

    NSTextField *hint = [NSTextField wrappingLabelWithString:
        T(@"Это нужно один раз и займёт около минуты. Дальше игра будет открываться сразу.",
          @"This happens once and takes about a minute. After that the game opens right away.")];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = NSColor.tertiaryLabelColor;
    hint.alignment = NSTextAlignmentCenter;
    [hint.widthAnchor constraintEqualToConstant:300].active = YES;

    NSStackView *stack = [NSStackView stackViewWithViews:@[icon, title, self.statusLabel, bar, hint]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 10;
    [stack setCustomSpacing:14 afterView:icon];
    [stack setCustomSpacing:16 afterView:self.statusLabel];
    [stack setCustomSpacing:16 afterView:bar];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [background addSubview:stack];
    [stack.centerXAnchor constraintEqualToAnchor:background.centerXAnchor].active = YES;
    [stack.centerYAnchor constraintEqualToAnchor:background.centerYAnchor constant:6].active = YES;

    self.window = window;
    [window center];
    [window makeKeyAndOrderFront:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Reproducible first-run verification without opening UI or the game.
        if (argc == 2 && strcmp(argv[1], "--prepare-only") == 0) {
            AppDelegate *delegate = [AppDelegate new];
            NSString *error = [delegate performSetup];
            if (error) fprintf(stderr, "%s\n", error.UTF8String);
            return error ? 1 : 0;
        }
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new];
        delegate.showOptions = OptionKeyDown();
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
