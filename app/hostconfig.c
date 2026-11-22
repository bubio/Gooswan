#include <stdbool.h>
#include "hostslice.h"
#include "vendor/tomlc99/toml.h"

static toml_table_t *config;

void hostconfig_free(void) {
    if (config) toml_free(config);
    config = NULL;
}

bool hostconfig_parse(hs_in source) {
    hostconfig_free();
    char *text = hs_string(source);
    if (!text) return false;
    config = toml_parse(text, NULL, 0);
    free(text);
    return config != NULL;
}
static toml_table_t *config_table(hs_in section) {
    if (section.len == 0) return config;
    char *name = hs_string(section);
    toml_table_t *t = name && config ? toml_table_in(config, name) : NULL;
    free(name);
    return t;
}
int64_t hostconfig_int(hs_in section, hs_in key, int64_t fallback) {
    toml_table_t *t = config_table(section);
    char *k = hs_string(key);
    toml_datum_t v = t && k ? toml_int_in(t, k) : (toml_datum_t){0};
    free(k);
    return v.ok ? v.u.i : fallback;
}
bool hostconfig_bool(hs_in section, hs_in key, bool fallback) {
    toml_table_t *t = config_table(section);
    char *k = hs_string(key);
    toml_datum_t v = t && k ? toml_bool_in(t, k) : (toml_datum_t){0};
    free(k);
    return v.ok ? v.u.b != 0 : fallback;
}
int64_t hostconfig_string(hs_in section, hs_in key, int64_t index, hs_out out) {
    toml_table_t *t = config_table(section);
    char *k = hs_string(key);
    toml_datum_t v = {0};
    if (t && k) {
        if (index < 0) v = toml_string_in(t, k);
        else {
            toml_array_t *a = toml_array_in(t, k);
            if (a && index < toml_array_nelem(a)) v = toml_string_at(a, (int)index);
        }
    }
    free(k);
    if (!v.ok) return -1;
    int64_t n = hs_copy(out, v.u.s);
    free(v.u.s);
    return n;
}
