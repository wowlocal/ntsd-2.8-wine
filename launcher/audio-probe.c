#include <AudioToolbox/AudioToolbox.h>
#include <stdio.h>
#include <unistd.h>
int main(void) {
 alarm(8);
 setvbuf(stdout,NULL,_IONBF,0);
 AudioComponentDescription d={kAudioUnitType_Output,kAudioUnitSubType_HALOutput,kAudioUnitManufacturer_Apple,0,0};
 AudioComponent c=AudioComponentFindNext(NULL,&d);if(!c)return 90;
 AudioComponentInstance instance=NULL;puts("native HAL instance create start");
 OSStatus s=AudioComponentInstanceNew(c,&instance);printf("native HAL create status=%d\n",(int)s);
 if(!s) {s=AudioComponentInstanceDispose(instance);printf("native HAL dispose status=%d\n",(int)s);}
 return s?20:0;
}
