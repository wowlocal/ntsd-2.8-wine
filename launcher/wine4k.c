#include <spawn.h>
#include <mach-o/dyld.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
extern char **environ;
int main(int argc, char **argv) {
    (void)argc;
    char executable[PATH_MAX], resolved[PATH_MAX], loader[PATH_MAX];
    uint32_t size = sizeof executable;
    if (_NSGetExecutablePath(executable, &size) || !realpath(executable, resolved)) return 125;
    char *slash = strrchr(resolved, '/');
    if (!slash) return 125;
    *slash = 0;
    if (snprintf(loader, sizeof loader, "%s/../lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine", resolved) >= sizeof loader) return 125;
    const char *identity = getenv("WINELOADER");
    if (!identity) { setenv("WINELOADER", argv[0], 1); identity = getenv("WINELOADER"); }
    if (identity) setenv("CFProcessPath", identity, 1);
    posix_spawnattr_t attributes;
    int error = posix_spawnattr_init(&attributes);
    if (!error) error = posix_spawnattr_set_4k_page_size_np(&attributes);
    if (!error) error = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETEXEC);
    argv[0] = loader;
    pid_t pid;
    if (!error) error = posix_spawn(&pid, loader, NULL, &attributes, argv, environ);
    fprintf(stderr, "4K Wine launch failed: %s\n", strerror(error));
    return 125;
}
