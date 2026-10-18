#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
static unsigned failures;
static void *readonly_page;
static volatile unsigned readonly_faults;
__attribute__((naked,noinline)) static void attempt_write(void *page) {
    __asm__("movl 4(%esp), %eax; movl $42, (%eax); ret");
}
static LONG CALLBACK readonly_handler(EXCEPTION_POINTERS *p) {
    if (p->ExceptionRecord->ExceptionCode==EXCEPTION_ACCESS_VIOLATION &&
        p->ExceptionRecord->ExceptionInformation[0]==1 &&
        p->ExceptionRecord->ExceptionInformation[1]==(ULONG_PTR)readonly_page &&
        p->ContextRecord->Eip==(DWORD)(ULONG_PTR)attempt_write+4) {
        readonly_faults++; p->ContextRecord->Eip+=6;
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}
static void show(const char *label, void *address, DWORD expected) {
    MEMORY_BASIC_INFORMATION info;
    if (!VirtualQuery(address, &info, sizeof info)) { puts("VirtualQuery failed"); failures++; return; }
    printf("%s protect=%08lx expected=%08lx\n",label,info.Protect,expected);
    if (info.Protect != expected) failures++;
}
static void region_probe(void) {
    unsigned char *p=VirtualAlloc(NULL,12288,MEM_RESERVE|MEM_COMMIT,PAGE_EXECUTE_READWRITE);
    if(!p) { failures++; return; }
    const unsigned char fn[]={0xb8,77,0,0,0,0xc3};
    memcpy(p+4096,fn,sizeof fn);
    FlushInstructionCache(GetCurrentProcess(),p+4096,sizeof fn);
    if(((int(*)(void))(p+4096))()!=77)failures++;
    for(unsigned i=0;i<3;i++) {
        MEMORY_BASIC_INFORMATION info={0};
        VirtualQuery(p+4096*i,&info,sizeof info);
        printf("merged region page=%u base-match=%u size=%lu protect=%08lx\n",i,info.BaseAddress==p+4096*i,(unsigned long)info.RegionSize,info.Protect);
        if(info.BaseAddress!=p+4096*i || info.RegionSize!=12288-4096*i || info.Protect!=PAGE_EXECUTE_READWRITE)failures++;
    }
    DWORD old;
    if(!VirtualProtect(p+4096,4096,PAGE_EXECUTE_READ,&old) || old!=PAGE_EXECUTE_READWRITE)failures++;
    for(unsigned i=0;i<3;i++) {
        MEMORY_BASIC_INFORMATION info={0};
        VirtualQuery(p+4096*i,&info,sizeof info);
        if(info.BaseAddress!=p+4096*i || info.RegionSize!=4096 || info.Protect!=(i==1?PAGE_EXECUTE_READ:PAGE_EXECUTE_READWRITE))failures++;
    }
    VirtualFree(p,0,MEM_RELEASE);
}
static void copy_probe(void) {
    HANDLE file=CreateFileMappingW(INVALID_HANDLE_VALUE,NULL,PAGE_EXECUTE_READWRITE,0,4096,NULL);
    if(!file) { failures++; return; }
    unsigned char *p=MapViewOfFile(file,FILE_MAP_COPY|FILE_MAP_EXECUTE,0,0,4096);
    if(!p) { CloseHandle(file); failures++; return; }
    const unsigned char fn[]={0xb8,41,0,0,0,0xc3};
    memcpy(p,fn,sizeof fn);
    FlushInstructionCache(GetCurrentProcess(),p,sizeof fn);
    if(((int(*)(void))p)()!=41)failures++;
    show("copy after execute",p,PAGE_EXECUTE_WRITECOPY);
    p[1]=42;
    if(((int(*)(void))p)()!=42)failures++;
    show("copy after write",p,PAGE_EXECUTE_WRITECOPY);
    DWORD old;
    if(!VirtualProtect(p,4096,PAGE_EXECUTE_READ,&old) || old!=PAGE_EXECUTE_WRITECOPY)failures++;
    UnmapViewOfFile(p);CloseHandle(file);
}
static void inline_probe(void) {
    unsigned char *p=VirtualAlloc(NULL,4096,MEM_RESERVE|MEM_COMMIT,PAGE_EXECUTE_READWRITE);
    if(!p) { failures++; return; }
    /* STC; MOV BYTE [next immediate],43; MOV EAX,42; ADC EAX,0; RET.
       The write changes an instruction in the currently executing block.
       The emulator must restart that block and preserve the carry flag. */
    unsigned char fn[]={0xf9,0xc6,0x05,0,0,0,0,43,0xb8,42,0,0,0,0x83,0xd0,0,0xc3};
    DWORD target=(DWORD)(ULONG_PTR)(p+9);
    memcpy(fn+3,&target,4);memcpy(p,fn,sizeof fn);
    FlushInstructionCache(GetCurrentProcess(),p,sizeof fn);
    int result=((int(*)(void))p)();
    printf("inline self-modification result=%d expected=44\n",result);
    if(result!=44)failures++;
    VirtualFree(p,0,MEM_RELEASE);
}
int main(void) {
    setvbuf(stdout,NULL,_IONBF,0);
    puts("probe start");
    unsigned char *p=VirtualAlloc(NULL,4096,MEM_RESERVE|MEM_COMMIT,PAGE_EXECUTE_READWRITE);
    if(!p) return 90;
    const unsigned char fn[]={0xb8,123,0,0,0,0xc3};
    memcpy(p,fn,sizeof fn);
    FlushInstructionCache(GetCurrentProcess(),p,sizeof fn);
    show("before execute",p,PAGE_EXECUTE_READWRITE);
    int first=((int(*)(void))p)();
    printf("first=%d\n",first); if(first!=123) failures++;
    show("after execute",p,PAGE_EXECUTE_READWRITE);
    p[1]=124;
    int second=((int(*)(void))p)();
    printf("second=%d\n",second); if(second!=124) failures++;
    show("after modify",p,PAGE_EXECUTE_READWRITE);
    DWORD old=0;
    if(!VirtualProtect(p,4096,PAGE_EXECUTE_READ,&old)) return 91;
    printf("VirtualProtect old=%08lx expected=00000040\n",old); if(old!=PAGE_EXECUTE_READWRITE)failures++;
    show("readonly",p,PAGE_EXECUTE_READ);
    readonly_page=p;
    unsigned char original=p[0];
    PVOID handler=AddVectoredExceptionHandler(1,readonly_handler);
    if(!handler)return 92;
    attempt_write(p);
    RemoveVectoredExceptionHandler(handler);
    printf("readonly write faults=%u unchanged=%u\n",readonly_faults,p[0]==original);
    if(readonly_faults!=1 || p[0]!=original)failures++;
    VirtualFree(p,0,MEM_RELEASE);
    region_probe();
    inline_probe();
    copy_probe();
    printf("memory probe complete failures=%u\n",failures);
    return failures ? 20 : 0;
}
