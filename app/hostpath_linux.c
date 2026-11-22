#include "hostpath.h"

int64_t hostconfig_dir(hs_out out) {
    const char *xdg = getenv("XDG_CONFIG_HOME");
    if (xdg && *xdg) return host_copy_config_dir(out, xdg, "/gooswan");
    return host_copy_config_dir(out, getenv("HOME"), "/.config/gooswan");
}
