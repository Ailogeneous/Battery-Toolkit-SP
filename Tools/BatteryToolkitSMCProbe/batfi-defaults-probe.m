#define main poweruiProbeMain
#include "powerui-probe.m"
#undef main
static CFStringRef domain = CFSTR("com.apple.smartcharging.topoffprotection");
static void notifyDefaults(void) {
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.apple.smartcharging.defaultschanged"), NULL, NULL, true);
}
int main(int argc, const char **argv) {
    setbuf(stdout, NULL);
    @autoreleasepool {
        if (argc != 2 || strcmp(argv[1], "--test-75-and-restore")) return 1;
        if (!onAC() || getuid() == 0) return 2;
        if (!dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW)) return 3;
        id client = [[NSClassFromString(@"PowerUISmartChargeClient") alloc] initWithClientName:@"TetheredDefaultsDiagnostic"];
        NSError *error = nil;
        unsigned char original = [client getMCLLimitWithError:&error];
        if (!client || error || ![client isMCLSupported] || original < 80 || original > 100) return 4;
        NSArray *keys = @[@"mclLimitValue", @"MCLFeatureState"];
        NSMutableDictionary *saved = [NSMutableDictionary dictionary];
        for (NSString *key in keys) {
            id value = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost));
            if (value) saved[key] = value;
        }
        NSString *snapshot = [NSString stringWithFormat:@"/tmp/tethered-charge-defaults-original-%d.plist", getpid()];
        NSDictionary *record = @{@"values": saved, @"originalLimit": @(original), @"uid": @(getuid()), @"domain": (__bridge NSString *)domain};
        if (![record writeToFile:snapshot atomically:YES]) return 5;
        printf("snapshot=%s original_limit=%u uid=%u saved=%s\n", snapshot.UTF8String, original, getuid(), saved.description.UTF8String);
        observe("baseline");
        signal(SIGINT, interruptProbe); signal(SIGTERM, interruptProbe); signal(SIGHUP, interruptProbe);
        CFPreferencesSetValue(CFSTR("mclLimitValue"), (__bridge CFNumberRef)@75, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
        CFPreferencesSetValue(CFSTR("MCLFeatureState"), (__bridge CFNumberRef)@1, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
        notifyDefaults();
        observe("75-requested");
        for (int i = 0; i < 18 && !interrupted; i++) { sleep(5); observe("75-observation"); }
        BOOL restored = NO;
        for (int i = 0; i < 3 && !restored; i++) restored = apply(client, original);
        for (NSString *key in keys) CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)saved[key], domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
        notifyDefaults();
        BOOL exact = YES;
        for (NSString *key in keys) {
            id value = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost));
            exact &= value == nil ? saved[key] == nil : [value isEqual:saved[key]];
        }
        for (int i = 0; i < 6; i++) { sleep(5); observe("restored-observation"); }
        error = nil;
        unsigned char current = [client getMCLLimitWithError:&error];
        printf("restore preference_values_exact=%s original_limit=%u getter=%u verified=%s error=%s\n", exact ? "YES" : "NO", original, current, restored && exact && !error && current == original ? "YES" : "NO", error.description.UTF8String ?: "none");
        return restored && exact && !error && current == original ? 0 : 6;
    }
}
