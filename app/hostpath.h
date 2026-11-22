#ifndef GOOSWAN_HOSTPATH_H
#define GOOSWAN_HOSTPATH_H

#include "hostslice.h"

/* The resolver returns a heap-allocated UTF-8 path or NULL. */
char *host_resolve_path(const char *path);
extern const char host_file_url_prefix[];
extern const uint8_t host_path_separator;

/* The platform provides the base directory and suffix. */
int64_t host_copy_config_dir(hs_out out, const char *base, const char *suffix);

#endif
