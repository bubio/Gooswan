#include <stdbool.h>
#include "hostpath.h"

extern bool SDL_OpenURL(const char *);

int64_t host_copy_config_dir(hs_out out, const char *base, const char *suffix) {
    if (!base || !*base) return 0;
    size_t base_len = strlen(base);
    size_t suffix_len = strlen(suffix);
    char *path = malloc(base_len + suffix_len + 1);
    if (!path) return 0;
    memcpy(path, base, base_len);
    memcpy(path + base_len, suffix, suffix_len + 1);
    int64_t result = hs_copy(out, path);
    free(path);
    return result;
}

/* Use one save slot for CLI-relative and file-picker paths. */
int64_t host_absolute_path(hs_in input, hs_out out) {
    char *path = hs_string(input);
    if (!path) return 0;

    char *absolute = host_resolve_path(path);
    int64_t result = hs_copy(out, absolute);
    free(absolute);
    free(path);
    return result;
}

bool host_open_directory(hs_in path) {
    /* Percent-encode UTF-8 bytes so #, spaces and non-ASCII paths work. */
    static const char hex[] = "0123456789ABCDEF";
    if (path.len < 0 || path.len > 16384) return false;
    size_t prefix_len = strlen(host_file_url_prefix);
    char *url = malloc(prefix_len + (size_t)path.len * 3 + 1);
    if (!url) return false;
    memcpy(url, host_file_url_prefix, prefix_len);
    size_t j = prefix_len;
    for (int64_t i = 0; i < path.len; ++i) {
        unsigned char c = path.data[i];
        if (c == host_path_separator) c = '/';
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '/' || c == ':' || c == '-' || c == '_' || c == '.') {
            url[j++] = (char)c;
        } else {
            url[j++] = '%';
            url[j++] = hex[c >> 4];
            url[j++] = hex[c & 15];
        }
    }
    url[j] = 0;
    bool ok = SDL_OpenURL(url);
    free(url);
    return ok;
}
