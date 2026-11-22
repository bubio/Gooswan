#include "hostpath.h"

int64_t hostconfig_dir(hs_out out) {
    return host_copy_config_dir(out, getenv("HOME"), "/Library/Application Support/gooswan");
}
