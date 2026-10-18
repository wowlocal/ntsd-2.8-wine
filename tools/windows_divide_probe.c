/* Exercise architectural integer-division faults and unchanged fault context.
 * Compile with i686-w64-mingw32-clang; all expected results are constants. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>

typedef uint64_t (*divide_fn)(uint32_t,uint32_t,uint32_t);
#define DIVIDER(name, instruction) \
__attribute__((naked,noinline)) static uint64_t name(uint32_t a,uint32_t d,uint32_t c) { \
 __asm__("movl 4(%esp),%eax;movl 8(%esp),%edx;movl 12(%esp),%ecx;stc;" instruction ";ret"); \
}
DIVIDER(u8,"div %cl")
DIVIDER(s8,"idiv %cl")
DIVIDER(u16,"div %cx")
DIVIDER(s16,"idiv %cx")
DIVIDER(u32,"div %ecx")
DIVIDER(s32,"idiv %ecx")
#undef DIVIDER
__attribute__((naked,noinline)) static uint64_t u32_clc(uint32_t a,uint32_t d,uint32_t c) {
 __asm__("movl 4(%esp),%eax;movl 8(%esp),%edx;movl 12(%esp),%ecx;clc;div %ecx;ret");
}
__attribute__((naked,noinline)) static uint64_t s32_clc(uint32_t a,uint32_t d,uint32_t c) {
 __asm__("movl 4(%esp),%eax;movl 8(%esp),%edx;movl 12(%esp),%ecx;clc;idiv %ecx;ret");
}
struct Case {
 const char *name;divide_fn fn;uint32_t low,high,divisor;uint64_t result;unsigned fault;
};
static const struct Case cases[]={
 {"u32 zero carry clear",u32_clc,0,0,0,0,1},
 {"s32 overflow carry clear",s32_clc,0x80000000,0xffffffff,0xffffffff,0,1},
 {"u32 100/3",u32,100,0,3,UINT64_C(0x0000000100000021),0},
 {"u32 maximum",u32,0xffffffff,0,1,UINT64_C(0x00000000ffffffff),0},
 {"u32 high dividend",u32,0,1,2,UINT64_C(0x0000000080000000),0},
 {"u32 zero",u32,0,0,0,0,1},
 {"u32 overflow",u32,0,1,1,0,1},
 {"u32 large overflow",u32,0xffffffff,0xffffffff,0xffffffff,0,1},
 {"s32 positive",s32,100,0,3,UINT64_C(0x0000000100000021),0},
 {"s32 negative dividend",s32,0xffffff9c,0xffffffff,3,UINT64_C(0xffffffffffffffdf),0},
 {"s32 negative divisor",s32,100,0,0xfffffffd,UINT64_C(0x00000001ffffffdf),0},
 {"s32 both negative",s32,0xffffff9c,0xffffffff,0xfffffffd,UINT64_C(0xffffffff00000021),0},
 {"s32 minimum",s32,0x80000000,0xffffffff,1,UINT64_C(0x0000000080000000),0},
 {"s32 minimum quotient",s32,0,0xffffffff,2,UINT64_C(0x0000000080000000),0},
 {"s32 negative boundary",s32,0xffffffff,0xfffffffe,2,UINT64_C(0xffffffff80000000),0},
 {"s32 overflow min/-1",s32,0x80000000,0xffffffff,0xffffffff,0,1},
 {"s32 overflow positive",s32,0xffffffff,0,1,0,1},
 {"s32 overflow negative",s32,0xfffffffe,0xfffffffe,2,0,1},
 {"s32 zero",s32,17,0,0,0,1},
 {"u16 ordinary",u16,100,0,3,UINT64_C(0x0000000100000021),0},
 {"u16 maximum",u16,0xffff,0,1,UINT64_C(0x000000000000ffff),0},
 {"u16 high dividend",u16,0,1,2,UINT64_C(0x0000000000008000),0},
 {"u16 zero",u16,0,0,0,0,1},
 {"u16 overflow",u16,0,1,1,0,1},
 {"s16 negative",s16,0xff9c,0xffff,3,UINT64_C(0x0000ffff0000ffdf),0},
 {"s16 minimum",s16,0x8000,0xffff,1,UINT64_C(0x0000000000008000),0},
 {"s16 minimum quotient",s16,0,0xffff,2,UINT64_C(0x0000000000008000),0},
 {"s16 overflow",s16,0x8000,0xffff,0xffff,0,1},
 {"s16 zero",s16,0,0,0,0,1},
 {"u8 ordinary",u8,100,0,3,UINT64_C(0x121),0},
 {"u8 maximum",u8,255,0,1,UINT64_C(0xff),0},
 {"u8 overflow",u8,256,0,1,0,1},
 {"u8 zero",u8,0,0,0,0,1},
 {"s8 negative",s8,0xff9c,0,3,UINT64_C(0xffdf),0},
 {"s8 negative divisor",s8,100,0,0xfd,UINT64_C(0x1df),0},
 {"s8 minimum",s8,0xff80,0,1,UINT64_C(0x80),0},
 {"s8 overflow",s8,0xff80,0,0xff,0,1},
 {"s8 zero",s8,0,0,0,0,1},
};
static const struct Case *current;
static unsigned failures,caught;
static LONG CALLBACK handler(EXCEPTION_POINTERS *p) {
 const CONTEXT *c=p->ContextRecord;
 if(!current || p->ExceptionRecord->ExceptionCode!=EXCEPTION_INT_DIVIDE_BY_ZERO) return EXCEPTION_CONTINUE_SEARCH;
 caught++;
 if(!current->fault || c->Eip!=(DWORD)(ULONG_PTR)current->fn+13 ||
    c->Eax!=current->low || c->Edx!=current->high || c->Ecx!=current->divisor || (c->EFlags&1)!=(current->fn==u32_clc || current->fn==s32_clc ? 0U : 1U)) {
  printf("bad fault context: %s eip=%08lx eax=%08lx edx=%08lx ecx=%08lx flags=%08lx\n",current->name,c->Eip,c->Eax,c->Edx,c->Ecx,c->EFlags);failures++;
 }
 p->ContextRecord->Eip=(DWORD)(ULONG_PTR)current->fn+((current->fn==u16 || current->fn==s16)?16:15);
 return EXCEPTION_CONTINUE_EXECUTION;
}
int main(void) {
 setvbuf(stdout,NULL,_IONBF,0);
 PVOID h=AddVectoredExceptionHandler(1,handler);if(!h)return 90;
 for(unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);i++) {
  current=&cases[i];unsigned before=caught;
  uint64_t value=current->fn(current->low,current->high,current->divisor);
  if(caught-before!=current->fault || (!current->fault && value!=current->result)) {
   printf("FAIL %s faults=%u result=%016llx expected=%016llx\n",current->name,caught-before,(unsigned long long)value,(unsigned long long)current->result);failures++;
  }
 }
 RemoveVectoredExceptionHandler(h);
 printf("integer divide cases=%u caught=%u failures=%u\n",(unsigned)(sizeof(cases)/sizeof(cases[0])),caught,failures);
 return failures?20:0;
}
