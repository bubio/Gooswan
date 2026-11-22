/* Stateful stereo s16 linear interpolation, matching Swanium's resampler.
   Keeping phase and the previous pair across pushes avoids frame-edge clicks. */
#ifndef GOOSWAN_HOSTRESAMPLE_H
#define GOOSWAN_HOSTRESAMPLE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef struct {
    uint32_t in_rate, out_rate, step;
    uint64_t phase;
    int16_t prev[2];
    bool has_prev;
} ha_resampler;

static void ha_resampler_init(ha_resampler *r, uint32_t in_rate, uint32_t out_rate) {
    *r = (ha_resampler){ .in_rate = in_rate, .out_rate = out_rate, .step = in_rate };
}

/* Output capacity in interleaved samples for `frames` input pairs. */
static size_t ha_resampler_bound(const ha_resampler *r, size_t frames) {
    return (size_t)(((uint64_t)frames * r->out_rate + r->step - 1) / r->step + 1) * 2;
}

static size_t ha_resampler_process(ha_resampler *r, const int16_t *input,
                                   size_t frames, int16_t *output) {
    size_t used = 0;
    for (size_t i = 0; i < frames; i++) {
        const int16_t *current = input + i * 2;
        if (!r->has_prev) {
            output[used++] = current[0]; output[used++] = current[1];
            r->has_prev = true;
            r->phase = r->step;
        } else {
            while (r->phase <= r->out_rate) {
                for (size_t ch = 0; ch < 2; ch++) {
                    /* Widen the product so full-scale transitions cannot overflow. */
                    int64_t delta = (int32_t)current[ch] - r->prev[ch];
                    output[used++] = (int16_t)(r->prev[ch] + delta * (int64_t)r->phase / r->out_rate);
                }
                r->phase += r->step;
            }
            r->phase -= r->out_rate;
        }
        r->prev[0] = current[0]; r->prev[1] = current[1];
    }
    return used;
}
#endif
