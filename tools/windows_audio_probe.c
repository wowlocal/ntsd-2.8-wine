#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <mmsystem.h>
#include <dsound.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
int main(void) {
 setvbuf(stdout,NULL,_IONBF,0);IDirectSound *sound=NULL;
 const char *drivers=getenv("ALSOFT_DRIVERS");
 if(!drivers || strcmp(drivers,"null")) {puts("Start this probe with ALSOFT_DRIVERS=null and WINEDLLOVERRIDES=dsound=n");return 2;}
 HMODULE module=LoadLibraryA("dsound.dll");if(!module){printf("LoadLibrary failed=%lu\n",GetLastError());return 88;}
 char path[MAX_PATH]={0};GetModuleFileNameA(module,path,sizeof path);printf("sound provider=%s\n",path);
 typedef HRESULT (WINAPI *create_fn)(LPCGUID,LPDIRECTSOUND*,LPUNKNOWN);
 create_fn create=(create_fn)GetProcAddress(module,"DirectSoundCreate");if(!create)return 89;
 HRESULT hr=create(NULL,&sound,NULL);printf("DirectSoundCreate=%08lx\n",(DWORD)hr);if(FAILED(hr))return 90;
 hr=IDirectSound_SetCooperativeLevel(sound,GetDesktopWindow(),DSSCL_PRIORITY);printf("cooperative level=%08lx\n",(DWORD)hr);if(FAILED(hr))return 91;
 WAVEFORMATEX fmt={WAVE_FORMAT_PCM,2,48000,192000,4,16,0};
 DSBUFFERDESC desc={0};desc.dwSize=sizeof desc;desc.dwFlags=DSBCAPS_GLOBALFOCUS;desc.dwBufferBytes=4096;desc.lpwfxFormat=&fmt;
 IDirectSoundBuffer *buffer=NULL;hr=IDirectSound_CreateSoundBuffer(sound,&desc,&buffer,NULL);printf("create buffer=%08lx\n",(DWORD)hr);if(FAILED(hr))return 92;
 void *a=NULL,*b=NULL;DWORD na=0,nb=0;hr=IDirectSoundBuffer_Lock(buffer,0,4096,&a,&na,&b,&nb,0);printf("lock buffer=%08lx\n",(DWORD)hr);if(FAILED(hr))return 93;
 memset(a,0,na);if(b)memset(b,0,nb);IDirectSoundBuffer_Unlock(buffer,a,na,b,nb);
 hr=IDirectSoundBuffer_Play(buffer,0,0,0);printf("play buffer=%08lx\n",(DWORD)hr);Sleep(50);
 IDirectSoundBuffer_Stop(buffer);IDirectSoundBuffer_Release(buffer);IDirectSound_Release(sound);
 puts("software audio probe complete");return FAILED(hr)?94:0;
}
