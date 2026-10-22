#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include "SMCParamStruct.h"
static uint32_t four(const char *s) { return (uint32_t)s[0]<<24 | (uint32_t)s[1]<<16 | (uint32_t)s[2]<<8 | (uint32_t)s[3]; }
int main(void) {
 setbuf(stdout,NULL);
 io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
 if(!service){puts("AppleSMC unavailable");return 1;}
 io_connect_t connection=0;
 kern_return_t kr=IOServiceOpen(service,mach_task_self(),1,&connection);IOObjectRelease(service);
 printf("uid=%u struct_size=%zu open=0x%x\n",getuid(),sizeof(SMCParamStruct),kr);
 if(kr)return 2;
 kr=IOConnectCallMethod(connection,0,NULL,0,NULL,0,NULL,NULL,NULL,NULL);
 printf("client_open=0x%x\n",kr);
 if(kr){IOServiceClose(connection);return 3;}
 const struct {const char *name;uint32_t size;} keys[]={{"#KEY",4},{"CHLS",2},{"CHLT",3},{"bfG0",3},{"CHIE",1}};
 for(unsigned i=0;i<sizeof(keys)/sizeof(keys[0]);i++) {
  SMCParamStruct in={0},out={0};size_t size=sizeof(out);
  in.key=four(keys[i].name);in.keyInfo.dataSize=keys[i].size;in.data8=kSMCReadKey;
  kr=IOConnectCallStructMethod(connection,kSMCHandleYPCEvent,&in,sizeof(in),&out,&size);
  printf("raw_read key=%s requested_size=%u io=0x%x smc=%u returned_struct_size=%zu",keys[i].name,keys[i].size,kr,out.result,size);
  if(!kr&&!out.result){printf(" bytes=");for(unsigned j=0;j<keys[i].size;j++)printf("%02x",out.bytes[j]);}
  puts("");
 }
 IOConnectCallMethod(connection,1,NULL,0,NULL,0,NULL,NULL,NULL,NULL);IOServiceClose(connection);return 0;
}
