/* Nonblocking pipes between the GUI thread and the Swan Revival worker. */
#include <stdbool.h>
#include <stdio.h>
#include "hostslice.h"

typedef struct SDL_Process SDL_Process;
typedef struct SDL_IOStream SDL_IOStream;
extern const char *SDL_GetBasePath(void);
extern SDL_Process *SDL_CreateProcess(const char *const *, bool);
extern SDL_IOStream *SDL_GetProcessInput(SDL_Process *);
extern SDL_IOStream *SDL_GetProcessOutput(SDL_Process *);
extern bool SDL_KillProcess(SDL_Process *, bool);
extern bool SDL_WaitProcess(SDL_Process *, bool, int *);
extern void SDL_DestroyProcess(SDL_Process *);
extern size_t SDL_ReadIO(SDL_IOStream *, void *, size_t);
extern size_t SDL_WriteIO(SDL_IOStream *, const void *, size_t);
extern int SDL_GetIOStatus(SDL_IOStream *);
extern bool SDL_OpenURL(const char *);

enum { MAX_FRAME = 8192, QUEUE_SIZE = 32768, IO_NOT_READY = 3 };
extern const char *hostlink_worker_name(void);

static SDL_Process *worker;
static SDL_IOStream *input, *output;
static uint8_t tx[QUEUE_SIZE], rx[MAX_FRAME + 3];
static size_t tx_length, rx_length;

void hostlink_stop(void) {
    if (worker) {
        if (!SDL_WaitProcess(worker, false, NULL)) {
            SDL_KillProcess(worker, true);
            SDL_WaitProcess(worker, true, NULL);
        }
        SDL_DestroyProcess(worker);
    }
    worker = NULL;
    input = output = NULL;
    memset(tx, 0, tx_length);
    tx_length = rx_length = 0;
}

bool hostlink_open(hs_in token_path) {
    hostlink_stop();
    const char *base = SDL_GetBasePath();
    const char *name = hostlink_worker_name();
    char *token = hs_string(token_path);
    if (!base || !token) { free(token); return false; }
    size_t size = strlen(base) + strlen(name) + 1;
    char *path = malloc(size);
    if (!path) { free(token); return false; }
    snprintf(path, size, "%s%s", base, name);
    const char *args[] = {path, token, NULL};
    worker = SDL_CreateProcess(args, true);
    free(path);
    free(token);
    if (worker) {
        input = SDL_GetProcessInput(worker);
        output = SDL_GetProcessOutput(worker);
        if (input && output) return true;
    }
    hostlink_stop();
    return false;
}

bool hostlink_send(uint8_t kind, hs_in payload) {
    if (!worker || payload.len < 0 || payload.len > MAX_FRAME ||
        (size_t)payload.len + 3 > sizeof(tx) - tx_length) return false;
    size_t n = (size_t)payload.len;
    tx[tx_length++] = kind;
    tx[tx_length++] = (uint8_t)n;
    tx[tx_length++] = (uint8_t)(n >> 8);
    if (n) memcpy(tx + tx_length, payload.data, n);
    tx_length += n;
    return true;
}

/* Return the size including the type byte, 0 if empty, or -1 on pipe failure. */
int64_t hostlink_poll(hs_out frame) {
    if (!worker) return -1;
    size_t space = sizeof(rx) - rx_length;
    size_t received = space ? SDL_ReadIO(output, rx + rx_length, space) : 0;
    rx_length += received;
    if (rx_length >= 3) {
        size_t n = rx[1] | ((size_t)rx[2] << 8);
        if (n > MAX_FRAME || (int64_t)n >= frame.len) return -1;
        if (rx_length >= n + 3) {
            frame.data[0] = rx[0];
            memcpy(frame.data + 1, rx + 3, n);
            rx_length -= n + 3;
            memmove(rx, rx + n + 3, rx_length);
            return (int64_t)n + 1;
        }
    }
    if (space && !received && SDL_GetIOStatus(output) != IO_NOT_READY) return -1;
    if (tx_length) {
        size_t sent = SDL_WriteIO(input, tx, tx_length);
        if (!sent && SDL_GetIOStatus(input) != IO_NOT_READY) return -1;
        tx_length -= sent;
        memmove(tx, tx + sent, tx_length);
        memset(tx + tx_length, 0, sent);
    }
    return 0;
}

bool hostlink_open_site(bool account) {
    return SDL_OpenURL(account ? "https://swanrevival.com/account/" : "https://swanrevival.com/link-play/");
}
