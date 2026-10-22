#import <Foundation/Foundation.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#include <dlfcn.h>
#include <signal.h>
#include <unistd.h>
#include "SMCParamStruct.h"
@interface NSObject (PowerUIProbe)
- (id)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
@end
static volatile sig_atomic_t interrupted;
static void interruptProbe(int sig) { interrupted = sig; }
static void observeHardware(void) {
    io_service_t battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (battery) {
        CFMutableDictionaryRef properties = NULL;
        if (IORegistryEntryCreateCFProperties(battery, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS && properties) {
            NSDictionary *values = CFBridgingRelease(properties);
            printf("battery AC=%s charging=%s percent=%s current_mA=%lld instant_mA=%lld voltage_mV=%s\n",
                [[values[@"ExternalConnected"] description] UTF8String], [[values[@"IsCharging"] description] UTF8String],
                [[values[@"CurrentCapacity"] description] UTF8String], [values[@"Amperage"] longLongValue],
                [values[@"InstantAmperage"] longLongValue], [[values[@"Voltage"] description] UTF8String]);
        }
        IOObjectRelease(battery);
    }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return;
    io_connect_t connection = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 1, &connection);
    IOObjectRelease(service);
    if (kr) { printf("state_smc_open=0x%x\n", kr); return; }
    IOConnectCallMethod(connection, 0, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL);
    const uint32_t keys[] = {0x43484c54, 0x62664730};
    const char *names[] = {"CHLT", "bfG0"};
    for (int i = 0; i < 2; i++) {
        SMCParamStruct input = {0}, output = {0}; size_t size = sizeof(output);
        input.key = keys[i]; input.data8 = kSMCReadKey; input.keyInfo.dataSize = 3;
        kr = IOConnectCallStructMethod(connection, 2, &input, sizeof(input), &output, &size);
        printf("state key=%s io=0x%x smc=%u", names[i], kr, output.result);
        if (!kr && !output.result) printf(" bytes=%02x%02x%02x", output.bytes[0], output.bytes[1], output.bytes[2]);
        puts("");
    }
    IOConnectCallMethod(connection, 1, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL);
    IOServiceClose(connection);
}
static void observe(const char *stage) {
    printf("stage=%s time=%s\n", stage, [[[NSDate date] description] UTF8String]);
    system("/usr/bin/pmset -g batt; /usr/bin/pmset -g battlimit");
    observeHardware();
}
static BOOL onAC(void) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return NO;
    CFStringRef source = IOPSGetProvidingPowerSourceType(info);
    BOOL result = source && CFEqual(source, CFSTR(kIOPSACPowerValue));
    CFRelease(info);
    return result;
}
static BOOL apply(id client, unsigned char limit) {
    NSError *error = nil;
    BOOL ok = [client setMCLLimit:limit error:&error];
    printf("set limit=%u accepted=%s error=%s\n", limit, ok ? "YES" : "NO", error ? [[error description] UTF8String] : "none");
    return ok && !error;
}
int main(int argc, const char **argv) {
    setbuf(stdout, NULL);
    BOOL extended = argc == 2 && strcmp(argv[1], "--long-test-80-and-restore") == 0;
    BOOL test = extended || (argc == 2 && strcmp(argv[1], "--test-80-and-restore") == 0);
    if (argc != 2 || (!test && strcmp(argv[1], "--read") != 0)) {
        puts("Usage: powerui-probe --read | --test-80-and-restore | --long-test-80-and-restore"); return 1;
    }
    @autoreleasepool {
        void *framework = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW);
        if (!framework) { fprintf(stderr, "%s\n", dlerror()); return 2; }
        Class cls = NSClassFromString(@"PowerUISmartChargeClient");
        if (!cls || ![cls instancesRespondToSelector:@selector(initWithClientName:)]) return 3;
        id client = [[cls alloc] initWithClientName:@"TetheredDiagnosticProbe"];
        if (!client || ![client respondsToSelector:@selector(isMCLSupported)] || ![client respondsToSelector:@selector(getMCLLimitWithError:)] || ![client respondsToSelector:@selector(setMCLLimit:error:)]) return 4;
        BOOL supported = [client isMCLSupported];
        NSError *error = nil;
        unsigned char original = [client getMCLLimitWithError:&error];
        printf("uid=%u supported=%s original_limit=%u getter_error=%s\n", getuid(), supported ? "YES" : "NO", original, error ? [[error description] UTF8String] : "none");
        observe("baseline");
        if (!test) return error ? 5 : 0;
        if (!supported || error || original < 80 || original > 100 || original == 80 || !onAC()) {
            puts("ABORT: need support, original limit 81..100, successful getter and AC power"); return 6;
        }
        signal(SIGINT, interruptProbe); signal(SIGTERM, interruptProbe); signal(SIGHUP, interruptProbe);
        BOOL accepted = apply(client, 80);
        if (accepted) {
            observe("80-immediate");
            for (int i = 0; i < (extended ? 24 : 5) && !interrupted; i++) {
                sleep(5); observe("80-observation");
            }
        }
        BOOL restored = NO;
        for (int i = 0; i < 3 && !restored; i++) restored = apply(client, original);
        error = nil;
        unsigned char current = [client getMCLLimitWithError:&error];
        printf("restore original=%u getter=%u verified=%s error=%s\n", original, current, restored && !error && current == original ? "YES" : "NO", error ? [[error description] UTF8String] : "none");
        observe("restored-immediate");
        if (restored) for (int i = 0; i < (extended ? 12 : 6) && !interrupted; i++) {
            sleep(5); observe("restored-observation");
        }
        return accepted && restored && !error && current == original ? 0 : 7;
    }
}
