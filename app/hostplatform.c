/* Small SDL3 adapter for APIs absent from Goose v2026.4's gfx package.
   All Goose-facing functions run on the main thread. The asynchronous file
   dialog callback only publishes an owned result under a mutex. */
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "vendor/tomlc99/toml.h"
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#else
extern char *realpath(const char *, char *);
#endif

typedef struct { const uint8_t *data; int64_t len; } hs_in;
typedef struct { uint8_t *data; int64_t len; } hs_out;
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Gamepad SDL_Gamepad;
typedef struct SDL_Mutex SDL_Mutex;
typedef struct SDL_IOStream SDL_IOStream;
typedef struct SDL_Surface SDL_Surface;
extern SDL_IOStream *SDL_IOFromConstMem(const void *, size_t);
extern SDL_Surface *SDL_LoadBMP_IO(SDL_IOStream *, bool);
extern bool SDL_SetWindowIcon(SDL_Window *, SDL_Surface *);
extern void SDL_DestroySurface(SDL_Surface *);
typedef struct { const char *name; const char *pattern; } SDL_DialogFileFilter;
extern SDL_Window **SDL_GetWindows(int *);
extern void SDL_free(void *);
extern bool SDL_RaiseWindow(SDL_Window *);
extern SDL_Window *SDL_GetKeyboardFocus(void);
extern bool SDL_SetWindowSize(SDL_Window *, int, int);
extern bool SDL_SetWindowFullscreen(SDL_Window *, bool);
extern uint64_t SDL_GetWindowFlags(SDL_Window *);
extern float SDL_GetWindowDisplayScale(SDL_Window *);
extern float SDL_GetWindowPixelDensity(SDL_Window *);
extern bool SDL_OpenURL(const char *);
extern bool SDL_InitSubSystem(uint32_t);
extern uint32_t *SDL_GetGamepads(int *);
extern SDL_Gamepad *SDL_OpenGamepad(uint32_t);
extern void SDL_CloseGamepad(SDL_Gamepad *);
extern bool SDL_GamepadConnected(SDL_Gamepad *);
extern bool SDL_GetGamepadButton(SDL_Gamepad *, int);
extern const char *SDL_GetGamepadName(SDL_Gamepad *);
extern const char *SDL_GetGamepadStringForButton(int);
extern SDL_Mutex *SDL_CreateMutex(void);
extern void SDL_LockMutex(SDL_Mutex *);
extern void SDL_UnlockMutex(SDL_Mutex *);
extern void SDL_ShowOpenFileDialog(void (*)(void *, const char *const *, int),
    void *, SDL_Window *, const SDL_DialogFileFilter *, int, const char *, bool);

static SDL_Window *window;
static SDL_Gamepad *pad;
static SDL_Mutex *dialog_mutex;
static bool dialog_pending;
static int dialog_status;
static char *dialog_result;
static char *dialog_location;
static toml_table_t *config;
static char config_error[256];

static char *hs_string(hs_in s) {
    if (s.len < 0 || s.len > 1024 * 1024) return NULL;
    char *p = malloc((size_t)s.len + 1);
    if (p) { memcpy(p, s.data, (size_t)s.len); p[s.len] = 0; }
    return p;
}
static int64_t hs_copy(hs_out out, const char *s) {
    size_t n = s ? strlen(s) : 0;
    if (out.len > 0) memcpy(out.data, s ? s : "", n < (size_t)out.len ? n : (size_t)out.len);
    return (int64_t)n;
}
void hostplatform_open(void) {
    int n = 0;
    SDL_Window **windows = SDL_GetWindows(&n);
    window = n > 0 ? windows[0] : NULL;
    SDL_free(windows);
    dialog_mutex = SDL_CreateMutex();
    SDL_InitSubSystem(0x00002000u); /* SDL_INIT_GAMEPAD */
}
void hostplatform_close(void) {
    if (pad) SDL_CloseGamepad(pad);
    pad = NULL;
    window = NULL;
    /* A native dialog may still own its callback at exit. The mutex and
       result stay process-owned until then; never free callback storage early. */
}
void hostwindow_icon(hs_in data) {
    if (!window || data.len <= 0) return;
    SDL_IOStream *io = SDL_IOFromConstMem(data.data, (size_t)data.len);
    if (!io) return;
    SDL_Surface *surface = SDL_LoadBMP_IO(io, true);
    if (surface) { SDL_SetWindowIcon(window, surface); SDL_DestroySurface(surface); }
}
bool hostwindow_focused(void) { return window && SDL_GetKeyboardFocus() == window; }
bool hostwindow_restore_focus(void) {
    if (!window) return false;
    SDL_RaiseWindow(window);
    return SDL_GetKeyboardFocus() == window;
}
bool hostwindow_present(void) { return window != NULL; }
bool hostwindow_size(int64_t w, int64_t h) {
    if (!window) return false;
    float pixels = SDL_GetWindowPixelDensity(window);
    float scale = pixels > 0.0f ? SDL_GetWindowDisplayScale(window) / pixels : 1.0f;
    if (scale <= 0.0f) scale = 1.0f;
    return SDL_SetWindowSize(window, (int)((float)w * scale), (int)((float)h * scale));
}
bool hostwindow_fullscreen(bool on) {
    return window && SDL_SetWindowFullscreen(window, on);
}
bool hostwindow_is_fullscreen(void) {
    return window && (SDL_GetWindowFlags(window) & 1u) != 0;
}
float hostwindow_scale(void) {
    return window ? SDL_GetWindowDisplayScale(window) : 1.0f;
}
int64_t hostconfig_dir(hs_out out) {
#ifdef _WIN32
    const char *base = getenv("APPDATA");
    const char *suffix = "/gooswan";
#elif defined(__APPLE__)
    const char *base = getenv("HOME");
    const char *suffix = "/Library/Application Support/gooswan";
#else
    const char *base = getenv("XDG_CONFIG_HOME");
    const char *suffix = "/gooswan";
    if (!base || !*base) { base = getenv("HOME"); suffix = "/.config/gooswan"; }
#endif
    if (!base || !*base) return 0;
    size_t n = strlen(base) + strlen(suffix);
    char *path = malloc(n + 1);
    if (!path) return 0;
    strcpy(path, base); strcat(path, suffix);
    int64_t result = hs_copy(out, path);
    free(path);
    return result;
}
bool host_open_directory(hs_in path) {
    /* Percent-encode UTF-8 bytes so #, spaces and non-ASCII paths work. */
    static const char hex[] = "0123456789ABCDEF";
    if (path.len < 0 || path.len > 16384) return false;
    char *url = malloc((size_t)path.len * 3 + 16);
    if (!url) return false;
    strcpy(url, "file://");
    size_t j = 7;
#ifdef _WIN32
    url[j++] = '/';
#endif
    for (int64_t i = 0; i < path.len; ++i) {
        unsigned char c = path.data[i];
#ifdef _WIN32
        if (c == '\\') c = '/';
#endif
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '/' || c == ':' || c == '-' || c == '_' || c == '.') url[j++] = (char)c;
        else { url[j++] = '%'; url[j++] = hex[c >> 4]; url[j++] = hex[c & 15]; }
    }
    url[j] = 0;
    bool ok = SDL_OpenURL(url);
    free(url);
    return ok;
}
static void dialog_done(void *unused, const char *const *files, int filter) {
    (void)unused; (void)filter;
    SDL_LockMutex(dialog_mutex);
    if (files && files[0]) {
        size_t n = strlen(files[0]);
        dialog_result = malloc(n + 1);
        if (dialog_result) memcpy(dialog_result, files[0], n + 1);
        dialog_status = dialog_result ? 1 : -1;
    } else dialog_status = files ? 2 : -1; /* cancelled / failed */
    free(dialog_location);
    dialog_location = NULL;
    SDL_UnlockMutex(dialog_mutex);
}
bool hostdialog_open(hs_in location) {
    if (!dialog_mutex) return false;
    SDL_LockMutex(dialog_mutex);
    if (dialog_pending) { SDL_UnlockMutex(dialog_mutex); return false; }
    dialog_location = hs_string(location);
    dialog_pending = true;
    dialog_status = 0;
    SDL_UnlockMutex(dialog_mutex);
    static const SDL_DialogFileFilter filters[] = {{"WonderSwan ROM", "ws;wsc"}, {"All files", "*"}};
    SDL_ShowOpenFileDialog(dialog_done, NULL, window, filters, 2, dialog_location, false);
    return true;
}
/* Returns 0 while pending, 1 selected, 2 cancelled, -1 failed. */
int64_t hostdialog_poll(hs_out out) {
    if (!dialog_mutex) return -1;
    SDL_LockMutex(dialog_mutex);
    int result = dialog_status;
    if (result != 0) {
        if (result == 1 && hs_copy(out, dialog_result) >= out.len) result = -1;
        free(dialog_result); dialog_result = NULL;
        dialog_status = 0; dialog_pending = false;
    }
    SDL_UnlockMutex(dialog_mutex);
    return result;
}
/* One active controller, following Swanium's frontend. SDL handles hotplug. */
void hostpad_poll(void) {
    if (pad && !SDL_GamepadConnected(pad)) { SDL_CloseGamepad(pad); pad = NULL; }
    if (!pad) {
        int n = 0;
        uint32_t *ids = SDL_GetGamepads(&n);
        if (n > 0) pad = SDL_OpenGamepad(ids[0]);
        SDL_free(ids);
    }
}
bool hostpad_down(int64_t button) {
    return pad && button >= 0 && button < 26 && SDL_GetGamepadButton(pad, (int)button);
}
int64_t hostpad_name(hs_out out) { return hs_copy(out, pad ? SDL_GetGamepadName(pad) : "No controller connected"); }
int64_t hostpad_button_name(int64_t button, hs_out out) {
    return hs_copy(out, button < 0 ? "Unbound" : SDL_GetGamepadStringForButton((int)button));
}
bool hostconfig_parse(hs_in source) {
    if (config) toml_free(config);
    config = NULL;
    config_error[0] = 0;
    char *text = hs_string(source);
    if (!text) return false;
    config = toml_parse(text, config_error, sizeof config_error);
    free(text);
    return config != NULL;
}
void hostconfig_free(void) { if (config) toml_free(config); config = NULL; }
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
int64_t hostconfig_error(hs_out out) { return hs_copy(out, config_error); }

/* Canonical UTF-8 paths keep CLI-relative and file-picker opens in one slot. */
int64_t host_absolute_path(hs_in input, hs_out out) {
    char *path = hs_string(input);
    if (!path) return 0;
    char *absolute = NULL;
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    wchar_t *wide = n > 0 ? malloc((size_t)n * sizeof(wchar_t)) : NULL;
    if (wide) {
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, n);
        wchar_t *resolved = _wfullpath(NULL, wide, 0);
        if (resolved) {
            n = WideCharToMultiByte(CP_UTF8, 0, resolved, -1, NULL, 0, NULL, NULL);
            absolute = n > 0 ? malloc((size_t)n) : NULL;
            if (absolute) WideCharToMultiByte(CP_UTF8, 0, resolved, -1, absolute, n, NULL, NULL);
            free(resolved);
        }
        free(wide);
    }
#else
    absolute = realpath(path, NULL);
#endif
    int64_t result = hs_copy(out, absolute);
    free(absolute); free(path);
    return result;
}
