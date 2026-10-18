/* Stress the 32/64-bit bridge used when returning from an exception handler.
 * Every worker repeatedly resumes a modified CPU context through NtContinue. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

#define WORKERS 4
#define ITERATIONS 500
static volatile LONG caught, failures;

__attribute__((naked, noinline)) static DWORD fault_and_resume(void) {
    __asm__("xorl %eax,%eax;ud2;movl $0x12345678,%eax;ret");
}

static LONG CALLBACK handler(EXCEPTION_POINTERS *p) {
    if (p->ExceptionRecord->ExceptionCode != EXCEPTION_ILLEGAL_INSTRUCTION ||
        p->ContextRecord->Eip != (DWORD)(ULONG_PTR)fault_and_resume + 2)
        return EXCEPTION_CONTINUE_SEARCH;
    InterlockedIncrement(&caught);
    p->ContextRecord->Eip += 2;
    return EXCEPTION_CONTINUE_EXECUTION;
}

static DWORD WINAPI worker(void *unused) {
    (void)unused;
    for (unsigned i = 0; i < ITERATIONS; i++) {
        if (fault_and_resume() != 0x12345678) InterlockedIncrement(&failures);
        SwitchToThread();
    }
    return 0;
}

int main(void) {
    HANDLE threads[WORKERS];
    PVOID h = AddVectoredExceptionHandler(1, handler);
    if (!h) return 90;
    for (unsigned i = 0; i < WORKERS; i++) {
        threads[i] = CreateThread(NULL, 0, worker, NULL, 0, NULL);
        if (!threads[i]) return 91;
    }
    if (WaitForMultipleObjects(WORKERS, threads, TRUE, 30000) != WAIT_OBJECT_0) return 92;
    for (unsigned i = 0; i < WORKERS; i++) CloseHandle(threads[i]);
    RemoveVectoredExceptionHandler(h);
    printf("context resumes=%ld expected=%u failures=%ld\n", caught, WORKERS * ITERATIONS, failures);
    return caught == WORKERS * ITERATIONS && !failures ? 0 : 20;
}
