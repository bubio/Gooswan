#include <windows.h>
#include <wchar.h>
#include "hostpath.h"

const char host_file_url_prefix[] = "file:///";
const uint8_t host_path_separator = '\\';

int64_t hostconfig_dir(hs_out out) {
    return host_copy_config_dir(out, getenv("APPDATA"), "/gooswan");
}

char *host_resolve_path(const char *path) {
    int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (length <= 0) return NULL;

    wchar_t *wide = malloc((size_t)length * sizeof(*wide));
    if (!wide) return NULL;

    wchar_t *resolved = NULL;
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, length)) {
        resolved = _wfullpath(NULL, wide, 0);
    }
    free(wide);
    if (!resolved) return NULL;

    length = WideCharToMultiByte(CP_UTF8, 0, resolved, -1, NULL, 0, NULL, NULL);
    char *absolute = length > 0 ? malloc((size_t)length) : NULL;
    if (absolute && !WideCharToMultiByte(CP_UTF8, 0, resolved, -1, absolute, length, NULL, NULL)) {
        free(absolute);
        absolute = NULL;
    }
    free(resolved);
    return absolute;
}
