// Both launchers define RunWindowsAudioTool() and WineEnvironment().
// Restore our previous fallback before probing, so a recovered output device
// can be used on the next launch. All checks are bounded and output-only.
static int PrepareAudio(void) {
    NSString *mode = NSProcessInfo.processInfo.environment[@"NTSD_AUDIO"] ?: @"auto";
    silentAudio = [mode isEqualToString:@"silent"];
    NSMutableDictionary *env = [WineEnvironment(NO) mutableCopy];
    env[@"WINEDLLOVERRIDES"] = @"mscoree,mshtml=;winemenubuilder.exe=d;dsound=b";
    int result;
    if (!silentAudio) {
        // A cold Wine/FEX process can spend more than eight seconds starting
        // prefix services before this registry/COM configuration tool runs.
        // Device probes keep their shorter deadlines; configuration gets 30s.
        result = RunWindowsAudioTool(@"audio-config.exe", @[@"system"], env, 30.0);
        if (result != 0) return result;
        silentAudio = RunAudioTool(Res(@"audio-probe"), @[], nil, 9.0) != 0;
        if (!silentAudio)
            silentAudio = RunWindowsAudioTool(@"audio-probe.exe", @[], env, 8.0) != 0;
    }
    if (silentAudio)
        return RunWindowsAudioTool(@"audio-config.exe", @[@"silent"], env, 30.0);
    return 0;
}
