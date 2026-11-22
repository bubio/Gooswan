#define _XOPEN_SOURCE 700
#include "hostpath.h"

const char host_file_url_prefix[] = "file://";
const uint8_t host_path_separator = '/';

char *host_resolve_path(const char *path) {
    return realpath(path, NULL);
}
