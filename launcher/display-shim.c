/* Shared display support for the original 32-bit NTSD executable.
 * Forward DirectDraw unchanged. Intercept only the final full-window GDI copy:
 * the engine continues drawing at its original size, then we aspect-fit it into
 * the current client and map mouse messages back to that same logical canvas.
 * System API callers still see the real window; the game's own GetWindowRect
 * sees the original dimensions to bypass its faulty resized mouse calculation.
 * Shared by ARM64 Wine/FEX and Intel Wine/Rosetta. */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include "MinHook.h"
#include <ddraw.h>
#include <stdint.h>
#include <stdio.h>
#include <windows.h>

static HMODULE self_module, backend;
static INIT_ONCE backend_once = INIT_ONCE_STATIC_INIT;
static DWORD recursion_slot;
static HWND game_window;
static WNDPROC old_proc;
static int canvas_w, canvas_h, last_w, last_h, frame_w, frame_h;
static BOOL fullscreen;
static LONG windowed_style;
static WINDOWPLACEMENT windowed_placement;
static BYTE *game_base;
static DWORD game_bytes;
static BOOL(WINAPI *real_bitblt)(HDC, int, int, int, int, HDC, int, int,
                                 DWORD) = BitBlt;
static BOOL(WINAPI *real_stretchblt)(HDC, int, int, int, int, HDC, int, int,
                                     int, int, DWORD) = StretchBlt;
static BOOL(WINAPI *real_client)(HWND, RECT *) = GetClientRect;
static BOOL(WINAPI *real_window)(HWND, RECT *) = GetWindowRect;

static BOOL(WINAPI *real_ntbitblt)(HDC, int, int, int, int, HDC, int, int,
                                   DWORD, DWORD, DWORD);
static BOOL(WINAPI *real_ntstretch)(HDC, int, int, int, int, HDC, int, int, int,
                                    int, DWORD, COLORREF);

typedef struct {
  int x, y, w, h, client_w, client_h;
} Viewport;
static BOOL from_game(void *p) {
  return (BYTE *)p >= game_base && (BYTE *)p < game_base + game_bytes;
}
static Viewport viewport(void) {
  RECT r = {0};
  real_client(game_window, &r);
  int w = r.right - r.left, h = r.bottom - r.top;
  Viewport v = {0, 0, canvas_w, canvas_h, w, h};
  if (w > 0 && h > 0 && canvas_w > 0 && canvas_h > 0) {
    double s = (double)w / canvas_w;
    double sy = (double)h / canvas_h;
    if (sy < s)
      s = sy;
    v.w = (int)(canvas_w * s + .5);
    v.h = (int)(canvas_h * s + .5);
    v.x = (w - v.w) / 2;
    v.y = (h - v.h) / 2;
  }
  return v;
}
static void logical_point(POINT *p) {
  Viewport v = viewport();
  if (v.w <= 0 || v.h <= 0)
    return;
  if (p->x < v.x || p->x >= v.x + v.w || p->y < v.y || p->y >= v.y + v.h) {
    p->x = p->y = -1;
    return;
  }
  p->x = (LONG)(((int64_t)(p->x - v.x) * canvas_w) / v.w);
  p->y = (LONG)(((int64_t)(p->y - v.y) * canvas_h) / v.h);
}
static void toggle_fullscreen(HWND win) {
  if (!fullscreen) {
    MONITORINFO info = {.cbSize = sizeof(info)};
    if (!GetMonitorInfoA(MonitorFromWindow(win, MONITOR_DEFAULTTONEAREST),
                         &info))
      return;
    windowed_placement.length = sizeof(windowed_placement);
    if (!GetWindowPlacement(win, &windowed_placement))
      return;
    windowed_style = GetWindowLongA(win, GWL_STYLE);
    fullscreen = TRUE;
    SetWindowLongA(win, GWL_STYLE,
                   (windowed_style & ~WS_OVERLAPPEDWINDOW) | WS_POPUP);
    SetWindowPos(win, HWND_TOP, info.rcMonitor.left, info.rcMonitor.top,
                 info.rcMonitor.right - info.rcMonitor.left,
                 info.rcMonitor.bottom - info.rcMonitor.top,
                 SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
  } else {
    fullscreen = FALSE;
    SetWindowLongA(win, GWL_STYLE, windowed_style);
    SetWindowPlacement(win, &windowed_placement);
    SetWindowPos(win, NULL, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  }
}
static LRESULT CALLBACK window_proc(HWND win, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_SYSKEYDOWN && wp == VK_RETURN) {
    if (!(lp & (1L << 30)))
      toggle_fullscreen(win);
    return 0;
  }
  if (msg == WM_SYSKEYUP && wp == VK_RETURN)
    return 0;
  if (msg == WM_SYSCOMMAND &&
      ((wp & 0xfff0) == SC_SIZE || (wp & 0xfff0) == SC_MAXIMIZE ||
       (wp & 0xfff0) == SC_RESTORE))
    return DefWindowProcA(win, msg, wp, lp);
  if (msg == WM_NCLBUTTONDOWN && wp >= HTLEFT && wp <= HTBOTTOMRIGHT)
    return DefWindowProcA(win, msg, wp, lp);
  if (msg == WM_NCDESTROY) {
    WNDPROC proc = old_proc;
    game_window = NULL;
    old_proc = NULL;
    return CallWindowProcA(proc, win, msg, wp, lp);
  }
  if (msg == WM_GETMINMAXINFO) {
    LRESULT ret = CallWindowProcA(old_proc, win, msg, wp, lp);
    MINMAXINFO *m = (void *)lp;
    RECT r = {0, 0, 320, 175};
    AdjustWindowRectEx(&r, GetWindowLongA(win, GWL_STYLE), GetMenu(win) != NULL,
                       GetWindowLongA(win, GWL_EXSTYLE));
    m->ptMinTrackSize.x = r.right - r.left;
    m->ptMinTrackSize.y = r.bottom - r.top;
    MONITORINFO info = {.cbSize = sizeof(info)};
    if (GetMonitorInfoA(MonitorFromWindow(win, MONITOR_DEFAULTTONEAREST),
                        &info)) {
      m->ptMaxSize.x = info.rcWork.right - info.rcWork.left;
      m->ptMaxSize.y = info.rcWork.bottom - info.rcWork.top;
      m->ptMaxPosition.x = info.rcWork.left - info.rcMonitor.left;
      m->ptMaxPosition.y = info.rcWork.top - info.rcMonitor.top;
    }
    m->ptMaxTrackSize.x = GetSystemMetrics(SM_CXVIRTUALSCREEN) + 128;
    m->ptMaxTrackSize.y = GetSystemMetrics(SM_CYVIRTUALSCREEN) + 128;

    (void)ret;
    return 0;
  }
  // Wine/macOS owns the physical client. Keep the engine's fixed-size
  // buffers out of native resize/fullscreen notifications so restoration
  // cannot leave a display-sized backing image inside the smaller window.
  if (msg == WM_NCCALCSIZE || msg == WM_WINDOWPOSCHANGED)
    return DefWindowProcA(win, msg, wp, lp);
  if (msg == WM_WINDOWPOSCHANGING)
    return 0;
  if (msg == WM_SIZING)
    return TRUE;

  if (msg == WM_NCHITTEST) {
    LRESULT hit = DefWindowProcA(win, msg, wp, lp);
    if (hit >= HTLEFT && hit <= HTBOTTOMRIGHT)
      return hit;
  }
  if (msg == WM_SIZE) {
    last_w = last_h = 0;
    return 0;
  }
  if (msg == WM_ERASEBKGND)
    return 1;
  if (msg == WM_MOUSEMOVE ||
      (msg >= WM_LBUTTONDOWN && msg <= WM_MBUTTONDBLCLK) ||
      (msg >= WM_XBUTTONDOWN && msg <= WM_XBUTTONDBLCLK)) {
    POINT p = {(SHORT)LOWORD(lp), (SHORT)HIWORD(lp)};
    logical_point(&p);
    lp = MAKELPARAM((SHORT)p.x, (SHORT)p.y);
  }
  return CallWindowProcA(old_proc, win, msg, wp, lp);
}
static void ensure_style(void) {
  LONG style = GetWindowLongA(game_window, GWL_STYLE);
  if ((style & WS_CAPTION) == WS_CAPTION && !(style & WS_THICKFRAME)) {
    RECT r = {0};
    real_client(game_window, &r);
    LONG ex = GetWindowLongA(game_window, GWL_EXSTYLE);
    style |= WS_THICKFRAME | WS_MAXIMIZEBOX;
    SetWindowLongA(game_window, GWL_STYLE, style);
    AdjustWindowRectEx(&r, style, GetMenu(game_window) != NULL, ex);
    SetWindowPos(game_window, NULL, 0, 0, r.right - r.left, r.bottom - r.top,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }
}
static BOOL final_copy(HDC dc, int x, int y, int w, int h) {
  if (x || y || w < 640 || h < 360)
    return FALSE;
  HWND win = WindowFromDC(dc);
  if (!win)
    return FALSE;
  DWORD pid = 0;
  GetWindowThreadProcessId(win, &pid);
  if (pid != GetCurrentProcessId())
    return FALSE;
  if (!game_window) {
    RECT r = {0};
    real_client(win, &r);
    if (r.right != w || r.bottom != h)
      return FALSE;
    RECT frame = {0};
    real_window(win, &frame);
    frame_w = frame.right - frame.left;
    frame_h = frame.bottom - frame.top;
    game_window = win;
    canvas_w = w;
    canvas_h = h;
    old_proc = (WNDPROC)(uintptr_t)SetWindowLongPtrA(win, GWLP_WNDPROC,
                                                     (LONG_PTR)window_proc);
    if (!old_proc) {
      game_window = NULL;
      return FALSE;
    }
    fprintf(stderr, "NTSD display: window=%p logical=%dx%d dc=%p type=%lu\n",
            win, w, h, dc, GetObjectType(dc));
    ensure_style();
  }
  if (win != game_window || w != canvas_w || h != canvas_h)
    return FALSE;
  ensure_style();
  return TRUE;
}
static Viewport prepare_viewport(HDC dc) {
  Viewport v = viewport();
  if (v.client_w != last_w || v.client_h != last_h) {
    PatBlt(dc, 0, 0, v.client_w, v.client_h, BLACKNESS);
    last_w = v.client_w;
    last_h = v.client_h;
    fprintf(stderr, "NTSD display: client=%dx%d viewport=%d,%d %dx%d\n",
            v.client_w, v.client_h, v.x, v.y, v.w, v.h);
  }
  if (v.x) {
    PatBlt(dc, 0, 0, v.x, v.client_h, BLACKNESS);
    PatBlt(dc, v.x + v.w, 0, v.client_w - v.x - v.w, v.client_h, BLACKNESS);
  }
  if (v.y) {
    PatBlt(dc, 0, 0, v.client_w, v.y, BLACKNESS);
    PatBlt(dc, 0, v.y + v.h, v.client_w, v.client_h - v.y - v.h, BLACKNESS);
  }
  return v;
}
// NTSD's built-in resized mouse path uses screen origins in its scale divisor.
// Keep its logical window size fixed; this DLL owns scaling and mouse mapping.
static BOOL WINAPI window_rect_hook(HWND win, RECT *r) {
  BOOL ret = real_window(win, r);
  if (ret && win == game_window && from_game(__builtin_return_address(0))) {
    r->right = r->left + frame_w;
    r->bottom = r->top + frame_h;
  }
  return ret;
}
static BOOL WINAPI bitblt_hook(HDC d, int x, int y, int w, int h, HDC s, int sx,
                               int sy, DWORD rop) {
  if (TlsGetValue(recursion_slot))
    return real_bitblt(d, x, y, w, h, s, sx, sy, rop);
  TlsSetValue(recursion_slot, (void *)1);
  BOOL ret;
  if (final_copy(d, x, y, w, h)) {
    Viewport v = prepare_viewport(d);
    if (v.x || v.y || v.w != w || v.h != h)
      ret = real_stretchblt(d, v.x, v.y, v.w, v.h, s, sx, sy, w, h, rop);
    else
      ret = real_bitblt(d, x, y, w, h, s, sx, sy, rop);
  } else
    ret = real_bitblt(d, x, y, w, h, s, sx, sy, rop);
  TlsSetValue(recursion_slot, NULL);
  return ret;
}
static BOOL WINAPI stretch_hook(HDC d, int x, int y, int w, int h, HDC s,
                                int sx, int sy, int sw, int sh, DWORD rop) {
  if (TlsGetValue(recursion_slot))
    return real_stretchblt(d, x, y, w, h, s, sx, sy, sw, sh, rop);
  TlsSetValue(recursion_slot, (void *)1);
  if (final_copy(d, x, y, w, h)) {
    Viewport v = prepare_viewport(d);
    x = v.x;
    y = v.y;
    w = v.w;
    h = v.h;
  }
  BOOL ret = real_stretchblt(d, x, y, w, h, s, sx, sy, sw, sh, rop);
  TlsSetValue(recursion_slot, NULL);
  return ret;
}
static BOOL WINAPI ntbit_hook(HDC d, int x, int y, int w, int h, HDC s, int sx,
                              int sy, DWORD rop, DWORD bg, DWORD flags) {
  if (TlsGetValue(recursion_slot))
    return real_ntbitblt(d, x, y, w, h, s, sx, sy, rop, bg, flags);
  TlsSetValue(recursion_slot, (void *)1);
  BOOL ret;
  if (final_copy(d, x, y, w, h)) {
    Viewport v = prepare_viewport(d);
    if (v.x || v.y || v.w != w || v.h != h)
      ret = real_ntstretch(d, v.x, v.y, v.w, v.h, s, sx, sy, w, h, rop, bg);
    else
      ret = real_ntbitblt(d, x, y, w, h, s, sx, sy, rop, bg, flags);
  } else
    ret = real_ntbitblt(d, x, y, w, h, s, sx, sy, rop, bg, flags);
  TlsSetValue(recursion_slot, NULL);
  return ret;
}
static BOOL WINAPI ntstretch_hook(HDC d, int x, int y, int w, int h, HDC s,
                                  int sx, int sy, int sw, int sh, DWORD rop,
                                  COLORREF bg) {
  if (TlsGetValue(recursion_slot))
    return real_ntstretch(d, x, y, w, h, s, sx, sy, sw, sh, rop, bg);
  TlsSetValue(recursion_slot, (void *)1);
  if (final_copy(d, x, y, w, h)) {
    Viewport v = prepare_viewport(d);
    x = v.x;
    y = v.y;
    w = v.w;
    h = v.h;
  }
  BOOL ret = real_ntstretch(d, x, y, w, h, s, sx, sy, sw, sh, rop, bg);
  TlsSetValue(recursion_slot, NULL);
  return ret;
}
static void add_hook(const WCHAR *module, const char *name, void *detour,
                     void **original) {
  void *target = NULL;
  HMODULE lib = LoadLibraryW(module);
  if (original && !*original && lib)
    *original = (void *)GetProcAddress(lib, name);
  MH_STATUS s = MH_CreateHookApiEx(module, name, detour, original, &target);
  fprintf(stderr, "NTSD display: hook %s %s\n", name, MH_StatusToString(s));
  if (s == MH_OK)
    MH_QueueEnableHook(target);
}
static DWORD WINAPI initialize_display(void *unused) {
  (void)unused;
  Sleep(200);
  game_base = (BYTE *)GetModuleHandleW(NULL);
  IMAGE_DOS_HEADER *dos = (void *)game_base;
  IMAGE_NT_HEADERS32 *nt = (void *)(game_base + dos->e_lfanew);
  game_bytes = nt->OptionalHeader.SizeOfImage;
  MH_STATUS status = MH_Initialize();
  fprintf(stderr, "NTSD display: initialize %s\n", MH_StatusToString(status));
  if (status != MH_OK)
    return 1;
  add_hook(L"gdi32.dll", "BitBlt", bitblt_hook, (void **)&real_bitblt);
  add_hook(L"gdi32.dll", "StretchBlt", stretch_hook, (void **)&real_stretchblt);

  add_hook(L"win32u.dll", "NtGdiStretchBlt", ntstretch_hook,
           (void **)&real_ntstretch);
  add_hook(L"win32u.dll", "NtGdiBitBlt", ntbit_hook, (void **)&real_ntbitblt);
  add_hook(L"user32.dll", "GetWindowRect", window_rect_hook,
           (void **)&real_window);
  fprintf(stderr, "NTSD display: enable begin\n");
  status = MH_ApplyQueued();
  fprintf(stderr, "NTSD display: enable %s\n", MH_StatusToString(status));
  return status == MH_OK ? 0 : 2;
}
static BOOL CALLBACK load_backend(PINIT_ONCE a, PVOID b, PVOID *c) {
  (void)a;
  (void)b;
  (void)c;
  WCHAR p[MAX_PATH];
  GetSystemDirectoryW(p, MAX_PATH);
  lstrcatW(p, L"\\ddraw.dll");
  backend = LoadLibraryW(p);
  if (backend == self_module)
    backend = NULL;
  return TRUE;
}
static FARPROC function(const char *name) {
  InitOnceExecuteOnce(&backend_once, load_backend, NULL, NULL);
  return backend ? GetProcAddress(backend, name) : NULL;
}
HRESULT WINAPI DirectDrawCreate(GUID *id, LPDIRECTDRAW *out, IUnknown *outer) {
  typedef HRESULT(WINAPI * F)(GUID *, LPDIRECTDRAW *, IUnknown *);
  F f = (F)function("DirectDrawCreate");
  return f ? f(id, out, outer) : E_FAIL;
}
HRESULT WINAPI DirectDrawCreateEx(GUID *id, void **out, REFIID iid,
                                  IUnknown *outer) {
  typedef HRESULT(WINAPI * F)(GUID *, void **, REFIID, IUnknown *);
  F f = (F)function("DirectDrawCreateEx");
  return f ? f(id, out, iid, outer) : E_FAIL;
}
HRESULT WINAPI DirectDrawCreateClipper(DWORD flags, LPDIRECTDRAWCLIPPER *out,
                                       IUnknown *outer) {
  typedef HRESULT(WINAPI * F)(DWORD, LPDIRECTDRAWCLIPPER *, IUnknown *);
  F f = (F)function("DirectDrawCreateClipper");
  return f ? f(flags, out, outer) : E_FAIL;
}
HRESULT WINAPI DirectDrawEnumerateA(LPDDENUMCALLBACKA cb, void *ctx) {
  typedef HRESULT(WINAPI * F)(LPDDENUMCALLBACKA, void *);
  F f = (F)function("DirectDrawEnumerateA");
  return f ? f(cb, ctx) : E_FAIL;
}
HRESULT WINAPI DirectDrawEnumerateW(LPDDENUMCALLBACKW cb, void *ctx) {
  typedef HRESULT(WINAPI * F)(LPDDENUMCALLBACKW, void *);
  F f = (F)function("DirectDrawEnumerateW");
  return f ? f(cb, ctx) : E_FAIL;
}
HRESULT WINAPI DirectDrawEnumerateExA(LPDDENUMCALLBACKEXA cb, void *ctx,
                                      DWORD flags) {
  typedef HRESULT(WINAPI * F)(LPDDENUMCALLBACKEXA, void *, DWORD);
  F f = (F)function("DirectDrawEnumerateExA");
  return f ? f(cb, ctx, flags) : E_FAIL;
}
HRESULT WINAPI DirectDrawEnumerateExW(LPDDENUMCALLBACKEXW cb, void *ctx,
                                      DWORD flags) {
  typedef HRESULT(WINAPI * F)(LPDDENUMCALLBACKEXW, void *, DWORD);
  F f = (F)function("DirectDrawEnumerateExW");
  return f ? f(cb, ctx, flags) : E_FAIL;
}
HRESULT WINAPI DllGetClassObject(REFCLSID cls, REFIID iid, void **out) {
  typedef HRESULT(WINAPI * F)(REFCLSID, REFIID, void **);
  F f = (F)function("DllGetClassObject");
  return f ? f(cls, iid, out) : E_FAIL;
}
HRESULT WINAPI DllCanUnloadNow(void) { return S_FALSE; }
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, void *reserved) {
  (void)reserved;
  if (reason == DLL_PROCESS_ATTACH) {
    self_module = module;
    recursion_slot = TlsAlloc();
    DisableThreadLibraryCalls(module);
    HANDLE t = CreateThread(NULL, 0, initialize_display, NULL, 0, NULL);
    if (t)
      CloseHandle(t);
  }
  return TRUE;
}
