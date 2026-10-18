// Exercise the same DirectSound output path as the game, without audible sound.
// The macOS parent bounds this process: third-party HAL drivers can hang here.
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <mmsystem.h>
#include <dsound.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    IDirectSound8 *sound = NULL;
    IDirectSoundBuffer *buffer = NULL;
    HRESULT result = DirectSoundCreate8(NULL, &sound, NULL);
    printf("DirectSound probe: create=%08lx\n", (DWORD)result);
    fflush(stdout);
    if (FAILED(result)) return 1;

    result = IDirectSound8_SetCooperativeLevel(sound, GetDesktopWindow(), DSSCL_NORMAL);
    if (FAILED(result)) { IDirectSound8_Release(sound); return 2; }

    WAVEFORMATEX format = {0};
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = 2;
    format.nSamplesPerSec = 44100;
    format.wBitsPerSample = 16;
    format.nBlockAlign = 4;
    format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
    DSBUFFERDESC desc = {0};
    desc.dwSize = sizeof(desc);
    desc.dwFlags = DSBCAPS_GLOBALFOCUS | DSBCAPS_GETCURRENTPOSITION2;
    desc.dwBufferBytes = format.nAvgBytesPerSec / 10;
    desc.lpwfxFormat = &format;
    result = IDirectSound8_CreateSoundBuffer(sound, &desc, &buffer, NULL);
    printf("DirectSound probe: buffer=%08lx\n", (DWORD)result);
    fflush(stdout);
    if (FAILED(result)) { IDirectSound8_Release(sound); return 3; }

    void *first = NULL, *second = NULL;
    DWORD first_bytes = 0, second_bytes = 0;
    result = IDirectSoundBuffer_Lock(buffer, 0, 0, &first, &first_bytes,
                                    &second, &second_bytes, DSBLOCK_ENTIREBUFFER);
    if (SUCCEEDED(result)) {
        if (first_bytes) memset(first, 0, first_bytes);
        if (second_bytes) memset(second, 0, second_bytes);
        IDirectSoundBuffer_Unlock(buffer, first, first_bytes, second, second_bytes);
        result = IDirectSoundBuffer_Play(buffer, 0, 0, DSBPLAY_LOOPING);
        if (SUCCEEDED(result)) { Sleep(60); IDirectSoundBuffer_Stop(buffer); }
    }
    printf("DirectSound probe: playback=%08lx\n", (DWORD)result);
    fflush(stdout);
    IDirectSoundBuffer_Release(buffer);
    IDirectSound8_Release(sound);
    return SUCCEEDED(result) ? 0 : 4;
}
