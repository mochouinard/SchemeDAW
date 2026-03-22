#include "sample-engine.h"
#include <SDL2/SDL.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

void sample_engine_init(SampleEngine *se, float sample_rate) {
    memset(se, 0, sizeof(SampleEngine));
    se->sample_rate = sample_rate;
}

int sample_engine_load(SampleEngine *se, const char *filename, int slot) {
    if (slot < 0 || slot >= MAX_SAMPLES) return -1;

    /* Unload existing sample in this slot */
    if (se->slots[slot].loaded) {
        sample_engine_unload(se, slot);
    }

    /* Load WAV using SDL */
    SDL_AudioSpec wav_spec;
    Uint8 *wav_buf = NULL;
    Uint32 wav_len = 0;

    if (SDL_LoadWAV(filename, &wav_spec, &wav_buf, &wav_len) == NULL) {
        fprintf(stderr, "Failed to load WAV '%s': %s\n", filename, SDL_GetError());
        return -1;
    }

    /* Convert to float stereo at engine sample rate */
    SDL_AudioCVT cvt;
    int src_format = wav_spec.format;
    int src_channels = wav_spec.channels;
    int src_rate = wav_spec.freq;

    /* First convert to float */
    if (SDL_BuildAudioCVT(&cvt, src_format, src_channels, src_rate,
                           AUDIO_F32SYS, 2, (int)se->sample_rate) < 0) {
        fprintf(stderr, "Failed to build audio CVT: %s\n", SDL_GetError());
        SDL_FreeWAV(wav_buf);
        return -1;
    }

    cvt.len = (int)wav_len;
    cvt.buf = (Uint8 *)malloc(cvt.len * cvt.len_mult);
    if (!cvt.buf) {
        SDL_FreeWAV(wav_buf);
        return -1;
    }
    memcpy(cvt.buf, wav_buf, wav_len);
    SDL_FreeWAV(wav_buf);

    if (SDL_ConvertAudio(&cvt) < 0) {
        fprintf(stderr, "Failed to convert audio: %s\n", SDL_GetError());
        free(cvt.buf);
        return -1;
    }

    /* Store as float samples */
    int total_samples = cvt.len_cvt / (int)sizeof(float);
    int frames = total_samples / 2; /* stereo */

    Sample *s = &se->slots[slot];
    s->data = (float *)malloc(total_samples * sizeof(float));
    if (!s->data) {
        free(cvt.buf);
        return -1;
    }
    memcpy(s->data, cvt.buf, total_samples * sizeof(float));
    free(cvt.buf);

    s->frames = frames;
    s->channels = 2;
    s->sample_rate = (int)se->sample_rate;
    s->loaded = 1;

    /* Store filename as name */
    const char *basename = strrchr(filename, '/');
    if (basename) basename++; else basename = filename;
    strncpy(s->name, basename, sizeof(s->name) - 1);
    s->name[sizeof(s->name) - 1] = '\0';

    fprintf(stderr, "Loaded sample '%s' into slot %d (%d frames)\n",
            s->name, slot, frames);
    return slot;
}

void sample_engine_unload(SampleEngine *se, int slot) {
    if (slot < 0 || slot >= MAX_SAMPLES) return;
    Sample *s = &se->slots[slot];

    /* Stop all voices using this sample */
    sample_engine_stop_sample(se, slot);

    if (s->data) {
        free(s->data);
        s->data = NULL;
    }
    s->loaded = 0;
    s->frames = 0;
    s->name[0] = '\0';
}

int sample_engine_trigger(SampleEngine *se, int slot, float volume,
                          float pan, float pitch) {
    if (slot < 0 || slot >= MAX_SAMPLES || !se->slots[slot].loaded) return -1;

    /* Find a free voice */
    int voice_id = -1;
    for (int i = 0; i < MAX_SAMPLE_VOICES; i++) {
        if (!se->voices[i].playing) {
            voice_id = i;
            break;
        }
    }

    /* Voice stealing: use the voice closest to its end */
    if (voice_id < 0) {
        float max_progress = -1.0f;
        for (int i = 0; i < MAX_SAMPLE_VOICES; i++) {
            SampleVoice *v = &se->voices[i];
            if (v->playing && v->sample_id >= 0 && v->sample_id < MAX_SAMPLES) {
                Sample *s = &se->slots[v->sample_id];
                if (s->loaded && s->frames > 0) {
                    float progress = v->play_pos / (float)s->frames;
                    if (progress > max_progress) {
                        max_progress = progress;
                        voice_id = i;
                    }
                }
            }
        }
        if (voice_id < 0) voice_id = 0; /* fallback */
    }

    SampleVoice *v = &se->voices[voice_id];
    v->sample_id = slot;
    v->play_pos = 0.0f;
    v->volume = volume;
    v->pan = pan;
    v->pitch = (pitch > 0.0f) ? pitch : 1.0f;
    v->playing = 1;
    v->loop = 0;
    v->loop_start = 0;
    v->loop_end = 0;
    v->reverse = 0;

    return voice_id;
}

void sample_engine_stop_voice(SampleEngine *se, int voice_id) {
    if (voice_id >= 0 && voice_id < MAX_SAMPLE_VOICES) {
        se->voices[voice_id].playing = 0;
    }
}

void sample_engine_stop_sample(SampleEngine *se, int slot) {
    for (int i = 0; i < MAX_SAMPLE_VOICES; i++) {
        if (se->voices[i].playing && se->voices[i].sample_id == slot) {
            se->voices[i].playing = 0;
        }
    }
}

void sample_engine_stop_all(SampleEngine *se) {
    for (int i = 0; i < MAX_SAMPLE_VOICES; i++) {
        se->voices[i].playing = 0;
    }
}

void sample_engine_render(SampleEngine *se, float *left, float *right, int frames) {
    for (int v = 0; v < MAX_SAMPLE_VOICES; v++) {
        SampleVoice *voice = &se->voices[v];
        if (!voice->playing) continue;

        Sample *sample = &se->slots[voice->sample_id];
        if (!sample->loaded || !sample->data) {
            voice->playing = 0;
            continue;
        }

        float pan_r = (voice->pan + 1.0f) * 0.5f;
        float pan_l = 1.0f - pan_r;

        for (int i = 0; i < frames; i++) {
            int pos = (int)voice->play_pos;

            /* Check bounds */
            if (pos >= sample->frames) {
                if (voice->loop) {
                    int loop_end = (voice->loop_end > 0) ? voice->loop_end : sample->frames;
                    voice->play_pos = (float)voice->loop_start;
                    pos = voice->loop_start;
                } else {
                    voice->playing = 0;
                    break;
                }
            }

            if (pos < 0) {
                voice->playing = 0;
                break;
            }

            /* Read stereo sample (interleaved) */
            float sample_l = sample->data[pos * 2];
            float sample_r = sample->data[pos * 2 + 1];

            /* Apply volume and pan, add to output */
            left[i]  += sample_l * voice->volume * pan_l;
            right[i] += sample_r * voice->volume * pan_r;

            /* Advance position */
            if (voice->reverse) {
                voice->play_pos -= voice->pitch;
                if (voice->play_pos < 0.0f) {
                    if (voice->loop) {
                        voice->play_pos = (float)(sample->frames - 1);
                    } else {
                        voice->playing = 0;
                        break;
                    }
                }
            } else {
                voice->play_pos += voice->pitch;
            }
        }
    }
}

void sample_engine_destroy(SampleEngine *se) {
    for (int i = 0; i < MAX_SAMPLES; i++) {
        if (se->slots[i].data) {
            free(se->slots[i].data);
            se->slots[i].data = NULL;
        }
        se->slots[i].loaded = 0;
    }
}
