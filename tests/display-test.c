/* Integration probe: exercise the packaged display DLL against a window owned
 * by this test process. It does not inject input into the game or other apps.
 */
#define WIN32_LEAN_AND_MEAN
#include <ddraw.h>
#include <stdio.h>
#include <windows.h>
static LPARAM mouse;
static LRESULT CALLBACK proc(HWND w, UINT m, WPARAM a, LPARAM b) {
  if (m == WM_MOUSEMOVE)
    mouse = b;
  return DefWindowProcA(w, m, a, b);
}
static void pump(void) {
  MSG m;
  for (int n = 0; n < 30; n++) {
    while (PeekMessageA(&m, NULL, 0, 0, PM_REMOVE)) {
      TranslateMessage(&m);
      DispatchMessageA(&m);
    }
    Sleep(10);
  }
}
int main(void) {
  IDirectDraw *draw = NULL;
  DirectDrawCreate(NULL, &draw, NULL);
  if (draw)
    draw->lpVtbl->Release(draw);
  WNDCLASSA c = {0};
  c.lpfnWndProc = proc;
  c.hInstance = GetModuleHandleA(NULL);
  c.lpszClassName = "NTSDDisplayTest";
  RegisterClassA(&c);
  RECT r = {0, 0, 800, 438};
  AdjustWindowRectEx(&r, WS_OVERLAPPEDWINDOW, FALSE, 0);
  HWND w = CreateWindowA(c.lpszClassName, "NTSD display integration probe",
                         WS_OVERLAPPEDWINDOW, 200, 200, r.right - r.left,
                         r.bottom - r.top, NULL, NULL, c.hInstance, NULL);
  if (!w)
    return 2;
  ShowWindow(w, SW_SHOW);
  pump();
  RECT original;
  GetWindowRect(w, &original);
  HDC dc = GetDC(w), src = CreateCompatibleDC(dc);
  HBITMAP bitmap = CreateCompatibleBitmap(dc, 800, 438);
  HGDIOBJ prev = SelectObject(src, bitmap);
  HBRUSH brush = CreateSolidBrush(RGB(20, 70, 180));
  RECT fill = {0, 0, 800, 438};
  FillRect(src, &fill, brush);
  BitBlt(dc, 0, 0, 800, 438, src, 0, 0, SRCCOPY);
  pump();
  r = (RECT){0, 0, 1000, 800};
  AdjustWindowRectEx(&r, GetWindowLongA(w, GWL_STYLE), FALSE,
                     GetWindowLongA(w, GWL_EXSTYLE));
  SetWindowPos(w, NULL, 250, 250, r.right - r.left, r.bottom - r.top,
               SWP_NOZORDER);
  pump();
  BitBlt(dc, 0, 0, 800, 438, src, 0, 0, SRCCOPY);
  GdiFlush();
  pump();
  RECT client, logical;
  GetClientRect(w, &client);
  GetWindowRect(w, &logical);
  COLORREF edge = GetPixel(dc, 10, 10), center = GetPixel(dc, 500, 400);
  SendMessageA(w, WM_MOUSEMOVE, 0, MAKELPARAM(500, 400));
  int mx = (SHORT)LOWORD(mouse), my = (SHORT)HIWORD(mouse);
  int fail = client.right != 1000 || client.bottom != 800 ||
             logical.right - logical.left != original.right - original.left ||
             edge != RGB(0, 0, 0) || center != RGB(20, 70, 180) ||
             abs(mx - 400) > 1 || abs(my - 219) > 1;
  printf("display client=%ldx%ld logical-frame=%ldx%ld original=%ldx%ld "
         "edge=%06lx center=%06lx mouse=%d,%d result=%s\n",
         client.right, client.bottom, logical.right - logical.left,
         logical.bottom - logical.top, original.right - original.left,
         original.bottom - original.top, edge, center, mx, my,
         fail ? "FAIL" : "PASS");
  fflush(stdout);
  SendMessageA(w, WM_SYSKEYDOWN, VK_RETURN, 0);
  pump();
  GetClientRect(w, &client);
  printf("fullscreen client=%ldx%ld\n", client.right, client.bottom);
  if (client.right <= 1000 || client.bottom <= 800)
    fail = 1;
  SendMessageA(w, WM_SYSKEYDOWN, VK_RETURN, 0);
  pump();
  GetClientRect(w, &client);
  printf("restored client=%ldx%ld\n", client.right, client.bottom);
  if (client.right != 1000 || client.bottom != 800)
    fail = 1;
  SelectObject(src, prev);
  DeleteObject(bitmap);
  DeleteObject(brush);
  DeleteDC(src);
  ReleaseDC(w, dc);
  DestroyWindow(w);
  return fail ? 1 : 0;
}
