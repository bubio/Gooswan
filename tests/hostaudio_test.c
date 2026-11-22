/* Exercise the production adapter with a deterministic SDL device substitute. */
#include <stdio.h>
#include "../app/hostaudio.c"

struct SDL_AudioStream { int unused; };
static struct SDL_AudioStream device_stream;
static int native_rate = 48000, queued_bytes, source_rate, destroyed, resumed;
static bool format_ok = true;
static int16_t captured[32768];
static size_t captured_count;
bool SDL_InitSubSystem(uint32_t flags) { (void)flags; return true; }
void SDL_QuitSubSystem(uint32_t flags) { (void)flags; }
SDL_AudioStream *SDL_OpenAudioDeviceStream(uint32_t id, const SDL_AudioSpec *spec,
                                          SDL_AudioStreamCallback cb, void *u) {
    (void)id; (void)spec; (void)cb; (void)u; return &device_stream;
}
uint32_t SDL_GetAudioStreamDevice(SDL_AudioStream *s) { (void)s; return 1; }
bool SDL_GetAudioDeviceFormat(uint32_t id, SDL_AudioSpec *spec, int *frames) {
    (void)id; (void)frames; *spec = (SDL_AudioSpec){ 0, 2, native_rate }; return format_ok;
}
bool SDL_SetAudioStreamFormat(SDL_AudioStream *s, const SDL_AudioSpec *src, const SDL_AudioSpec *dst) {
    (void)s; (void)dst; source_rate = src->freq; return true;
}
bool SDL_ResumeAudioStreamDevice(SDL_AudioStream *s) { (void)s; resumed++; return true; }
bool SDL_PutAudioStreamData(SDL_AudioStream *s, const void *buf, int len) {
    (void)s;
    if (len < 0 || captured_count + (size_t)len / 2 > sizeof(captured) / sizeof(*captured)) return false;
    memcpy(captured + captured_count, buf, (size_t)len);
    captured_count += (size_t)len / 2; queued_bytes += len; return true;
}
int SDL_GetAudioStreamQueued(SDL_AudioStream *s) { (void)s; return queued_bytes; }
bool SDL_ClearAudioStream(SDL_AudioStream *s) { (void)s; queued_bytes = 0; captured_count = 0; return true; }
void SDL_DestroyAudioStream(SDL_AudioStream *s) { (void)s; destroyed++; }

static int passed, failed;
static void check(const char *name, bool ok) {
    if (ok) passed++; else { failed++; printf("AUDIO FAIL %s\n", name); }
}

int64_t hostaudio_self_test(void) {
    check("invalid source rates rejected", !hostaudio_open(0) && !hostaudio_open(-1));
    const int16_t input[] = {0, 10, 100, 30, 200, 50};
    const int16_t expected[] = {0, 10, 50, 20, 100, 30, 150, 40, 200, 50};
    check("open", hostaudio_open(24000));
    check("stream consumes native-rate samples", source_rate == 48000);
    hostaudio_push((ha_i16_slice){input, 2}, 0);
    hostaudio_push((ha_i16_slice){input + 2, 4}, 0);
    check("interpolation across pushes", captured_count == 10 && !memcmp(captured, expected, sizeof(expected)));
    queued_bytes = 10176;
    check("queue converted to source-rate frames", hostaudio_queued() == 1272);
    hostaudio_clear();
    hostaudio_push((ha_i16_slice){input + 4, 2}, 0);
    check("clear resets previous pair and phase", captured_count == 2 && captured[0] == 200 && captured[1] == 50);
    hostaudio_clear(); hostaudio_volume(27);
    const int16_t signed_pair[] = {-101, 101};
    hostaudio_push((ha_i16_slice){signed_pair, 2}, 0);
    check("volume uses signed integer truncation", captured_count == 2 && captured[0] == -27 && captured[1] == 27);
    hostaudio_clear(); hostaudio_volume(100);
    // Feed 318 source frames per tick while the simulated device consumes
    // slightly more or less than the nominal 636 output frames.
    const int16_t silence[636] = {0};
    const ha_i16_slice frame = {silence, 636};
    const int64_t target = 1272;
    const int drains[] = {633, 639};
    for (size_t device = 0; device < sizeof(drains) / sizeof(*drains); device++) {
        hostaudio_clear();
        queued_bytes = (int)target * 8;
        bool stable = true;
        for (int tick = 0; tick < 3000; tick++) {
            captured_count = 0;
            hostaudio_push(frame, target);
            queued_bytes -= drains[device] * 4;
            int64_t queued = hostaudio_queued();
            if (queued < 600 || queued > 1900) stable = false;
        }
        check(device == 0 ? "queue adapts to a slower device" : "queue adapts to a faster device", stable);
    }
    hostaudio_clear();
    for (int i = 0; i < 20; i++) {
        captured_count = 0;
        hostaudio_push(frame, target);
    }
    check("queue stays bounded when the device stops draining", hostaudio_queued() == 2 * target);
    hostaudio_clear();
    check("clear restores the nominal conversion step", ha_resample.step == ha_resample.in_rate);
    hostaudio_close();
    check("close releases scratch", !ha_converted && ha_capacity == 0);
    hostaudio_volume(100);

    int16_t signal[514], whole[8192], split[8192];
    for (size_t i = 0; i < 514; i++) signal[i] = (int16_t)((int)i * 127 - 32000);
    const uint32_t rates[] = {16000, 24000, 44100, 48000, 96000};
    for (size_t k = 0; k < sizeof(rates)/sizeof(*rates); k++) {
        ha_resampler a, b;
        ha_resampler_init(&a, 24000, rates[k]); ha_resampler_init(&b, 24000, rates[k]);
        size_t n = ha_resampler_process(&a, signal, 257, whole), m = 0;
        for (size_t i = 0; i < 257; i++) m += ha_resampler_process(&b, signal + i * 2, 1, split + m);
        check("chunk boundaries do not alter PCM", n == m && !memcmp(whole, split, n * sizeof(*whole)));
        check("output bound sufficient", n <= ha_resampler_bound(&a, 257));
        check("output cadence", n == (rates[k] == 24000 ? 514 : ((uint64_t)256 * rates[k] / 24000 + 1) * 2));
        check("empty push preserves phase", ha_resampler_process(&a, signal, 0, whole) == 0 && a.phase == b.phase);
        if (rates[k] == 24000) check("same rate unchanged", !memcmp(whole, signal, sizeof(signal)));
    }
    ha_resampler r;
    ha_resampler_init(&r, 24000, 48000);
    const int16_t extreme[] = {32767, -32768, -32768, 32767};
    const int16_t extreme_expected[] = {32767, -32768, 0, -1, -32768, 32767};
    size_t n = ha_resampler_process(&r, extreme, 2, whole);
    check("full-scale transition avoids overflow", n == 6 && !memcmp(whole, extreme_expected, sizeof(extreme_expected)));
    native_rate = 44100; captured_count = 0; queued_bytes = 0;
    check("reopen at fractional device rate", hostaudio_open(24000) && source_rate == native_rate);
    hostaudio_push((ha_i16_slice){input, 6}, 0);
    check("fractional output length", captured_count == 8);
    hostaudio_close();
    format_ok = false;
    int old_destroyed = destroyed, old_resumed = resumed;
    check("failed device query reported", !hostaudio_open(24000));
    check("failed device query cleans up without resume", !ha_stream && destroyed == old_destroyed + 1 && resumed == old_resumed);
    printf("hostaudio_test: %d passed, %d failed\n", passed, failed);
    return failed;
}
