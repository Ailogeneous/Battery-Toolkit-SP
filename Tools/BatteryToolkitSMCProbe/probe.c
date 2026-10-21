#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "SMCParamStruct.h"
static kern_return_t query(io_connect_t c, SMCParamStruct *in, SMCParamStruct *out) {
    size_t size = sizeof(*out);
    memset(out, 0, size);
    return IOConnectCallStructMethod(c, kSMCHandleYPCEvent, in, sizeof(*in), out, &size);
}
int main(void) {
    if (sizeof(SMCParamStruct) != 80) return 1;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 2;
    io_connect_t c = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 1, &c);
    IOObjectRelease(service);
    if (kr) { fprintf(stderr, "SMC open failed: 0x%x\n", kr); return 3; }
    kr = IOConnectCallMethod(c, kSMCUserClientOpen, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL);
    if (kr) { IOServiceClose(c); return 4; }
    SMCParamStruct in = {0}, out = {0};
    in.key = 0x234b4559; in.data8 = kSMCReadKey; in.keyInfo.dataSize = 4;
    kr = query(c, &in, &out);
    if (kr || out.result) { IOServiceClose(c); return 5; }
    uint32_t count = (uint32_t)out.bytes[0]<<24 | (uint32_t)out.bytes[1]<<16 | (uint32_t)out.bytes[2]<<8 | out.bytes[3];
    if (count > 20000) { IOServiceClose(c); return 6; }
    printf("{\"kind\":\"directory\",\"count\":%u,\"uid\":%u}\n", count, getuid());
    unsigned failures = 0;
    for (uint32_t i = 0; i < count; i++) {
        memset(&in, 0, sizeof(in)); in.data8 = kSMCGetKeyFromIndex; in.data32 = i;
        kr = query(c, &in, &out);
        if (kr || out.result) {
            failures++;
            printf("{\"kind\":\"index_error\",\"index\":%u,\"io\":%u,\"smc\":%u}\n", i, kr, out.result);
            continue;
        }
        uint32_t key = out.key;
        unsigned char a = key>>24, b = key>>16;
        int candidate = ((a=='C' && b=='H') || (a=='A' && b=='C') || (a=='B') || (a=='b' && b=='f'));
        printf("{\"kind\":\"key\",\"index\":%u,\"key\":%u,\"candidate\":%s}\n", i, key, candidate?"true":"false");
        if (!candidate) continue;
        memset(&in, 0, sizeof(in)); in.key = key; in.data8 = kSMCGetKeyInfo;
        kr = query(c, &in, &out);
        printf("{\"kind\":\"metadata\",\"key\":%u,\"io\":%u,\"smc\":%u,\"size\":%u,\"type\":%u,\"attributes\":%u}\n", key, kr, out.result, out.keyInfo.dataSize, out.keyInfo.dataType, out.keyInfo.dataAttributes);
        if (kr || out.result || !out.keyInfo.dataSize || out.keyInfo.dataSize > 32) continue;
        uint32_t bytes = out.keyInfo.dataSize;
        memset(&in, 0, sizeof(in)); in.key = key; in.data8 = kSMCReadKey; in.keyInfo.dataSize = bytes;
        kr = query(c, &in, &out);
        printf("{\"kind\":\"value\",\"key\":%u,\"io\":%u,\"smc\":%u,\"hex\":\"", key, kr, out.result);
        if (!kr && !out.result) for (uint32_t j=0;j<bytes;j++) printf("%02x",out.bytes[j]);
        printf("\"}\n");
    }
    printf("{\"kind\":\"summary\",\"enumeration_failures\":%u}\n", failures);
    IOConnectCallMethod(c, kSMCUserClientClose, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL);
    IOServiceClose(c);
    return failures ? 7 : 0;
}
