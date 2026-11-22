/* Streaming audio output for the frontend: one SDL3 audio stream that the
   main thread feeds with each frame's samples, so consecutive frames play
   back to back. (The audio package only starts independent voices at the
   next device block, which leaves gaps and overlaps between frames.)

   The SDL3 headers are not shipped with Goose, but libSDL3 is linked in
   through the gfx package, so the few declarations needed are written out
   here (SDL3 ABI). Main thread only. */
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include "hostresample.h"

typedef struct SDL_AudioStream SDL_AudioStream;
typedef struct { int format; int channels; int freq; } SDL_AudioSpec;
typedef void (*SDL_AudioStreamCallback)(void *, SDL_AudioStream *, int, int);

extern bool SDL_InitSubSystem(uint32_t flags);
extern void SDL_QuitSubSystem(uint32_t flags);
extern SDL_AudioStream *SDL_OpenAudioDeviceStream(uint32_t devid, const SDL_AudioSpec *spec,
                                                  SDL_AudioStreamCallback cb, void *userdata);
extern bool SDL_ResumeAudioStreamDevice(SDL_AudioStream *stream);
extern uint32_t SDL_GetAudioStreamDevice(SDL_AudioStream *stream);
extern bool SDL_GetAudioDeviceFormat(uint32_t devid, SDL_AudioSpec *spec, int *sample_frames);
extern bool SDL_SetAudioStreamFormat(SDL_AudioStream *stream, const SDL_AudioSpec *src, const SDL_AudioSpec *dst);
extern bool SDL_PutAudioStreamData(SDL_AudioStream *stream, const void *buf, int len);
extern int SDL_GetAudioStreamQueued(SDL_AudioStream *stream);
extern bool SDL_ClearAudioStream(SDL_AudioStream *stream);
extern void SDL_DestroyAudioStream(SDL_AudioStream *stream);

#define HA_INIT_AUDIO 0x00000010u
#define HA_AUDIO_S16LE 0x8010
#define HA_DEFAULT_PLAYBACK 0xFFFFFFFFu

typedef struct { const int16_t *data; int64_t len; } ha_i16_slice;

static SDL_AudioStream *ha_stream;
static ha_resampler ha_resample;
static int16_t *ha_converted;
static size_t ha_capacity;
static int64_t ha_volume = 100;

/* Convert `rate` to the opened device's native rate ourselves. SDL still
   handles device sample-format/channel conversion, but not rate interpolation. */
bool hostaudio_open(int64_t rate) {
    if (ha_stream) return true;
    if (rate <= 0 || rate > INT32_MAX) return false;
    if (!SDL_InitSubSystem(HA_INIT_AUDIO)) return false;
    SDL_AudioSpec spec = { HA_AUDIO_S16LE, 2, (int)rate };
    ha_stream = SDL_OpenAudioDeviceStream(HA_DEFAULT_PLAYBACK, &spec, 0, 0);
    if (!ha_stream) { SDL_QuitSubSystem(HA_INIT_AUDIO); return false; }
    SDL_AudioSpec device;
    if (!SDL_GetAudioDeviceFormat(SDL_GetAudioStreamDevice(ha_stream), &device, 0) || device.freq <= 0) {
        SDL_DestroyAudioStream(ha_stream);
        ha_stream = 0;
        SDL_QuitSubSystem(HA_INIT_AUDIO);
        return false;
    }
    ha_resampler_init(&ha_resample, (uint32_t)rate, (uint32_t)device.freq);
    spec.freq = device.freq;
    if (!SDL_SetAudioStreamFormat(ha_stream, &spec, 0) || !SDL_ResumeAudioStreamDevice(ha_stream)) {
        SDL_DestroyAudioStream(ha_stream);
        ha_stream = 0;
        SDL_QuitSubSystem(HA_INIT_AUDIO);
        return false;
    }
    return true;
}

/* Source-rate stereo frames, so frontend pacing keeps the same time budget
   regardless of whether the native output is 44.1, 48 or another kHz rate. */
int64_t hostaudio_queued(void) {
    if (!ha_stream) return 0;
    int bytes = SDL_GetAudioStreamQueued(ha_stream);
    return bytes > 0 ? ((int64_t)bytes / 4) * ha_resample.in_rate / ha_resample.out_rate : 0;
}

/* Append interleaved stereo samples to the stream. */
void hostaudio_push(ha_i16_slice pcm, int64_t target) {
    if (!ha_stream || pcm.len <= 0) return;
    size_t frames = (size_t)pcm.len / 2;
    // Netplay runs on the wall clock. Adjust output independently to keep
    // the device queue near its target without changing the game clock.
    const int64_t nominal = ha_resample.in_rate;
    int64_t queued = target > 0 ? hostaudio_queued() : 0;
    int64_t correction = target > 0 ? (queued - target) / 4 : 0;
    const int64_t limit = nominal / 50;
    if (correction > limit) correction = limit;
    if (correction < -limit) correction = -limit;
    ha_resample.step = (uint32_t)(nominal + correction);
    size_t needed = ha_resampler_bound(&ha_resample, frames);
    if (needed > ha_capacity) {
        int16_t *grown = realloc(ha_converted, needed * sizeof(*grown));
        if (!grown) return;
        ha_converted = grown; ha_capacity = needed;
    }
    size_t count = ha_resampler_process(&ha_resample, pcm.data, frames, ha_converted);
    // Large bursts after a host stall must not build up unbounded latency.
    // Keep the interpolation history moving even when the queue is full.
    if (target > 0) {
        int64_t remaining = 2 * target - queued;
        if (remaining <= 0) return;
        uint64_t samples = (uint64_t)remaining * ha_resample.out_rate / nominal * 2;
        if (samples < count) count = (size_t)samples;
    }
    if (ha_volume != 100) {
        for (size_t i = 0; i < count; i++) ha_converted[i] = (int16_t)((int32_t)ha_converted[i] * ha_volume / 100);
    }
    if (count) SDL_PutAudioStreamData(ha_stream, ha_converted, (int)(count * sizeof(*ha_converted)));
}

void hostaudio_close(void) {
    if (!ha_stream) return;
    SDL_DestroyAudioStream(ha_stream);
    ha_stream = 0;
    free(ha_converted); ha_converted = 0; ha_capacity = 0;
    SDL_QuitSubSystem(HA_INIT_AUDIO);
}

void hostaudio_clear(void) {
    if (ha_stream) SDL_ClearAudioStream(ha_stream);
    ha_resampler_init(&ha_resample, ha_resample.in_rate, ha_resample.out_rate);
}
void hostaudio_volume(int64_t value) { ha_volume = value < 0 ? 0 : value > 100 ? 100 : value; }
