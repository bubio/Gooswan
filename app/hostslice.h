#ifndef GOOSWAN_HOSTSLICE_H
#define GOOSWAN_HOSTSLICE_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Goose passes slices to C as a data pointer and a signed 64-bit length. */
typedef struct { const uint8_t *data; int64_t len; } hs_in;
typedef struct { uint8_t *data; int64_t len; } hs_out;

static inline char *hs_string(hs_in s) {
    if (s.len < 0 || s.len > 1024 * 1024) return NULL;
    char *text = malloc((size_t)s.len + 1);
    if (!text) return NULL;
    if (s.len > 0) memcpy(text, s.data, (size_t)s.len);
    text[s.len] = '\0';
    return text;
}
static inline int64_t hs_copy(hs_out out, const char *s) {
    size_t n = s ? strlen(s) : 0;
    if (n > 0 && out.len > 0) memcpy(out.data, s, n < (size_t)out.len ? n : (size_t)out.len);
    return (int64_t)n;
}

#endif
