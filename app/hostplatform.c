/* Small SDL3 adapter for APIs absent from Goose v2026.4's gfx package.
   All Goose-facing functions run on the main thread. The asynchronous file
   dialog callback only publishes an owned result under a mutex. */
#include <stdbool.h>
#include "hostslice.h"

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
