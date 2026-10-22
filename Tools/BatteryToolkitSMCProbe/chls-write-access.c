#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "SMCParamStruct.h"
static uint32_t key(const char *s) { return (uint32_t)s[0]<<24 | (uint32_t)s[1]<<16 | (uint32_t)s[2]<<8 | (uint32_t)s[3]; }
static int readState(io_connect_t c, const char *name, unsigned char bytes[3]) {
    SMCParamStruct in={0},out={0};size_t size=sizeof(out);
    in.key=key(name);in.keyInfo.dataSize=3;in.data8=kSMCReadKey;
    kern_return_t kr=IOConnectCallStructMethod(c,kSMCHandleYPCEvent,&in,sizeof(in),&out,&size);
    printf("read key=%s io=0x%x smc=%u",name,kr,out.result);
    if(!kr&&!out.result&&size==sizeof(out)) {
        memcpy(bytes,out.bytes,3);
        printf(" bytes=%02x%02x%02x\n",bytes[0],bytes[1],bytes[2]);return 1;
    }
    puts("");return 0;
}
int main(int argc,char **argv) {
    setbuf(stdout,NULL);
    if(argc!=2 || strcmp(argv[1],"--write-current-unrestricted-state") || geteuid()!=0) {
        puts("Usage: sudo chls-write-access --write-current-unrestricted-state");return 1;
    }
    if(sizeof(SMCParamStruct)!=80)return 2;
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
    if(!service)return 3;
    io_connect_t c=0;kern_return_t kr=IOServiceOpen(service,mach_task_self(),1,&c);IOObjectRelease(service);
    printf("uid=%u open=0x%x\n",getuid(),kr);if(kr)return 4;
    kr=IOConnectCallMethod(c,kSMCUserClientOpen,NULL,0,NULL,0,NULL,NULL,NULL,NULL);
    printf("client_open=0x%x\n",kr);if(kr){IOServiceClose(c);return 5;}
    unsigned char a[3]={0},b[3]={0};int result=6;
    if(!readState(c,"CHLT",a)||!readState(c,"bfG0",b))goto done;
    if(memcmp(a,b,3)||a[0]||a[1]||a[2]) {
        puts("ABORT: both state keys must report 000000; set native limit to 100% first");goto done;
    }
    puts("Submitting one raw CHLS operation=6 size=2 payload=0000; metadata lookup bypassed");
    SMCParamStruct in={0},out={0};size_t size=sizeof(out);
    in.key=key("CHLS");in.keyInfo.dataSize=2;in.data8=kSMCWriteKey;
    kr=IOConnectCallStructMethod(c,kSMCHandleYPCEvent,&in,sizeof(in),&out,&size);
    printf("raw_write key=CHLS io=0x%x smc=%u returned_struct_size=%zu\n",kr,out.result,size);
    result=kr||out.result?7:0;
    readState(c,"CHLT",a);readState(c,"bfG0",b);
    puts("State reads are indirect observations, not direct CHLS readback or proof of charging control");
done:
    IOConnectCallMethod(c,kSMCUserClientClose,NULL,0,NULL,0,NULL,NULL,NULL,NULL);
    IOServiceClose(c);return result;
}
