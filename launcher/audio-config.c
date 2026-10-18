// Configure only NTSD's private prefix. Restore settings owned by this fallback.
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <dshow.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const GUID SilentRenderer = {0xc1f400a4,0x3f08,0x11d3,{0x9f,0x0b,0,0x60,8,3,0x9e,0x37}};
static const WCHAR Instance[] = L"NTSD Silent Audio";

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "silent") && strcmp(argv[1], "system"))) return 2;
    const BOOL silent = !strcmp(argv[1], "silent");
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) return 3;
    IFilterMapper2 *mapper = NULL;
    hr = CoCreateInstance(&CLSID_FilterMapper2, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IFilterMapper2, (void**)&mapper);
    if (FAILED(hr)) { printf("FilterMapper2 CoCreate: %08lx\n", (DWORD)hr); return 4; }
    if (silent) {
        REGPINTYPES type = {&MEDIATYPE_Audio, &GUID_NULL};
        REGFILTERPINS2 pin = {0};
        pin.dwFlags = REG_PINFLAG_B_RENDERER; pin.cInstances = 1;
        pin.nMediaTypes = 1; pin.lpMediaType = &type;
        REGFILTER2 filter = {0};
        filter.dwVersion = 2; filter.dwMerit = MERIT_PREFERRED + 1;
        filter.cPins2 = 1; filter.rgPins2 = &pin;
        hr = IFilterMapper2_RegisterFilter(mapper, &SilentRenderer, Instance, NULL,
                                           &CLSID_LegacyAmFilterCategory, Instance, &filter);
    } else {
        // This unique instance leaves Wine's standard Null Renderer untouched.
        hr = IFilterMapper2_UnregisterFilter(mapper, &CLSID_LegacyAmFilterCategory, Instance, &SilentRenderer);
        if (hr == HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND)) hr = S_OK;
    }
    IFilterMapper2_Release(mapper); CoUninitialize();
    if (FAILED(hr)) { printf("audio filter: %08lx\n", (DWORD)hr); return 5; }

    HKEY drivers, saved;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Wine\\Drivers", 0, NULL, 0,
                        KEY_READ|KEY_WRITE, NULL, &drivers, NULL)) return 6;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\NTSD\\AudioFallback", 0, NULL, 0,
                        KEY_READ|KEY_WRITE, NULL, &saved, NULL)) return 7;
    DWORD active = 0, size = sizeof active, type = 0, bytes = 0;
    RegQueryValueExW(saved, L"Active", NULL, NULL, (BYTE*)&active, &size);
    LONG status = RegQueryValueExW(drivers, L"Audio", NULL, &type, NULL, &bytes);
    BYTE *value = calloc(bytes ? bytes : 1, 1);
    if (!value) return 8;
    if (status == ERROR_SUCCESS) status = RegQueryValueExW(drivers, L"Audio", NULL, &type, value, &bytes);
    if (status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND) return 9;
    LONG result = ERROR_SUCCESS;
    if (silent) {
        if (!active) {
            DWORD missing = status == ERROR_FILE_NOT_FOUND;
            result = RegSetValueExW(saved, L"Missing", 0, REG_DWORD, (BYTE*)&missing, sizeof missing);
            if (!result) result = RegSetValueExW(saved, L"Type", 0, REG_DWORD, (BYTE*)&type, sizeof type);
            if (!result) result = RegSetValueExW(saved, L"Value", 0, REG_BINARY, value, bytes);
            active = 1;
            if (!result) result = RegSetValueExW(saved, L"Active", 0, REG_DWORD, (BYTE*)&active, sizeof active);
        }
        if (!result) result = RegSetValueExW(drivers, L"Audio", 0, REG_SZ, (BYTE*)L"", sizeof(WCHAR));
    } else if (active) {
        // Respect a setting changed since fallback was activated.
        if (status == ERROR_SUCCESS && type == REG_SZ && bytes == sizeof(WCHAR) && !*(WCHAR*)value) {
            DWORD missing = 0, originalType = 0, length = sizeof(DWORD), originalBytes = 0;
            RegQueryValueExW(saved, L"Missing", NULL, NULL, (BYTE*)&missing, &length);
            length = sizeof(DWORD);
            RegQueryValueExW(saved, L"Type", NULL, NULL, (BYTE*)&originalType, &length);
            if (missing) result = RegDeleteValueW(drivers, L"Audio");
            else if (!RegQueryValueExW(saved, L"Value", NULL, NULL, NULL, &originalBytes)) {
                BYTE *original = malloc(originalBytes ? originalBytes : 1);
                if (!original) return 8;
                result = RegQueryValueExW(saved, L"Value", NULL, NULL, original, &originalBytes);
                if (!result) result = RegSetValueExW(drivers, L"Audio", 0, originalType, original, originalBytes);
                free(original);
            } else result = ERROR_INVALID_DATA;
        }
        if (!result) { active = 0; result = RegSetValueExW(saved, L"Active", 0, REG_DWORD, (BYTE*)&active, sizeof active); }
    }
    free(value); RegCloseKey(saved); RegCloseKey(drivers);
    printf("NTSD audio: %s (%ld)\n", silent ? "silent fallback" : "system", result);
    return result ? 10 : 0;
}
