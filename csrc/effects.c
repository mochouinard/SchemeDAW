#include "effects.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static float fx_clampf(float x, float lo, float hi) {
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
}

/* ================================================================
 *  DELAY
 * ================================================================ */

void delay_init(DelayEffect *d, float sample_rate) {
    memset(d, 0, sizeof(DelayEffect));
    d->sample_rate = sample_rate;
    d->buf_size = MAX_DELAY_SAMPLES;
    d->buffer_l = (float *)calloc(d->buf_size, sizeof(float));
    d->buffer_r = (float *)calloc(d->buf_size, sizeof(float));
    d->delay_time = 0.375f; /* 3/8 second (dotted eighth at 120bpm) */
    d->feedback = 0.4f;
    d->mix = 0.3f;
    d->active = 1;
}

void delay_set_params(DelayEffect *d, float time, float feedback, float mix) {
    d->delay_time = fx_clampf(time, 0.001f, 2.0f);
    d->feedback = fx_clampf(feedback, 0.0f, 0.95f);
    d->mix = fx_clampf(mix, 0.0f, 1.0f);
}

void delay_process(DelayEffect *d, float *left, float *right, int frames) {
    if (!d->active || !d->buffer_l || !d->buffer_r) return;

    int delay_samples = (int)(d->delay_time * d->sample_rate);
    if (delay_samples >= d->buf_size) delay_samples = d->buf_size - 1;
    if (delay_samples < 1) delay_samples = 1;

    for (int i = 0; i < frames; i++) {
        int read_pos = (d->write_pos - delay_samples + d->buf_size) % d->buf_size;

        float delayed_l = d->buffer_l[read_pos];
        float delayed_r = d->buffer_r[read_pos];

        /* Write input + feedback into buffer */
        d->buffer_l[d->write_pos] = left[i] + delayed_l * d->feedback;
        d->buffer_r[d->write_pos] = right[i] + delayed_r * d->feedback;

        /* Mix dry/wet */
        left[i]  = left[i]  * (1.0f - d->mix) + delayed_l * d->mix;
        right[i] = right[i] * (1.0f - d->mix) + delayed_r * d->mix;

        d->write_pos = (d->write_pos + 1) % d->buf_size;
    }
}

void delay_destroy(DelayEffect *d) {
    if (d->buffer_l) { free(d->buffer_l); d->buffer_l = NULL; }
    if (d->buffer_r) { free(d->buffer_r); d->buffer_r = NULL; }
}

/* ================================================================
 *  REVERB (Schroeder)
 * ================================================================ */

/* Comb filter delay lengths (in samples at 44100 Hz, scaled for other rates) */
static const int comb_lengths[REVERB_NUM_COMBS] = { 1116, 1188, 1277, 1356 };
static const int allpass_lengths[REVERB_NUM_ALLPASS] = { 556, 441 };
/* Stereo spread: right channel uses slightly longer delays */
#define STEREO_SPREAD 23

static void delay_line_init(ReverbDelayLine *dl, int size) {
    dl->size = size;
    dl->pos = 0;
    dl->buffer = (float *)calloc(size, sizeof(float));
}

static void delay_line_destroy(ReverbDelayLine *dl) {
    if (dl->buffer) { free(dl->buffer); dl->buffer = NULL; }
}

static float delay_line_read(ReverbDelayLine *dl) {
    return dl->buffer[dl->pos];
}

static void delay_line_write(ReverbDelayLine *dl, float value) {
    dl->buffer[dl->pos] = value;
    dl->pos = (dl->pos + 1) % dl->size;
}

void reverb_init(ReverbEffect *r, float sample_rate) {
    memset(r, 0, sizeof(ReverbEffect));
    r->sample_rate = sample_rate;
    float scale = sample_rate / 44100.0f;

    /* Initialize comb filters */
    for (int i = 0; i < REVERB_NUM_COMBS; i++) {
        int len = (int)(comb_lengths[i] * scale);
        delay_line_init(&r->comb_l[i], len);
        delay_line_init(&r->comb_r[i], len + STEREO_SPREAD);
        r->comb_feedback[i] = 0.84f;
    }

    /* Initialize allpass filters */
    for (int i = 0; i < REVERB_NUM_ALLPASS; i++) {
        int len = (int)(allpass_lengths[i] * scale);
        delay_line_init(&r->allpass_l[i], len);
        delay_line_init(&r->allpass_r[i], len + STEREO_SPREAD);
        r->allpass_feedback[i] = 0.5f;
    }

    r->room_size = 0.7f;
    r->damping = 0.5f;
    r->mix = 0.3f;
    r->width = 1.0f;
    r->active = 1;

    memset(r->damp_state_l, 0, sizeof(r->damp_state_l));
    memset(r->damp_state_r, 0, sizeof(r->damp_state_r));
}

void reverb_set_params(ReverbEffect *r, float room_size, float damping,
                       float mix, float width) {
    r->room_size = fx_clampf(room_size, 0.0f, 1.0f);
    r->damping = fx_clampf(damping, 0.0f, 1.0f);
    r->mix = fx_clampf(mix, 0.0f, 1.0f);
    r->width = fx_clampf(width, 0.0f, 1.0f);

    /* Update comb feedback based on room size */
    float feedback = 0.7f + 0.28f * r->room_size;
    for (int i = 0; i < REVERB_NUM_COMBS; i++) {
        r->comb_feedback[i] = feedback;
    }
}

void reverb_process(ReverbEffect *r, float *left, float *right, int frames) {
    if (!r->active) return;

    float damp1 = r->damping;
    float damp2 = 1.0f - damp1;

    for (int i = 0; i < frames; i++) {
        float input = (left[i] + right[i]) * 0.5f; /* mono input to reverb */
        float out_l = 0.0f;
        float out_r = 0.0f;

        /* Parallel comb filters */
        for (int c = 0; c < REVERB_NUM_COMBS; c++) {
            /* Left channel */
            float comb_out_l = delay_line_read(&r->comb_l[c]);
            r->damp_state_l[c] = comb_out_l * damp2 + r->damp_state_l[c] * damp1;
            delay_line_write(&r->comb_l[c],
                             input + r->damp_state_l[c] * r->comb_feedback[c]);
            out_l += comb_out_l;

            /* Right channel */
            float comb_out_r = delay_line_read(&r->comb_r[c]);
            r->damp_state_r[c] = comb_out_r * damp2 + r->damp_state_r[c] * damp1;
            delay_line_write(&r->comb_r[c],
                             input + r->damp_state_r[c] * r->comb_feedback[c]);
            out_r += comb_out_r;
        }

        /* Series allpass filters */
        for (int a = 0; a < REVERB_NUM_ALLPASS; a++) {
            /* Left */
            float ap_out_l = delay_line_read(&r->allpass_l[a]);
            delay_line_write(&r->allpass_l[a],
                             out_l + ap_out_l * r->allpass_feedback[a]);
            out_l = ap_out_l - out_l * r->allpass_feedback[a];

            /* Right */
            float ap_out_r = delay_line_read(&r->allpass_r[a]);
            delay_line_write(&r->allpass_r[a],
                             out_r + ap_out_r * r->allpass_feedback[a]);
            out_r = ap_out_r - out_r * r->allpass_feedback[a];
        }

        /* Stereo width */
        float wet_l = out_l * r->width + out_r * (1.0f - r->width);
        float wet_r = out_r * r->width + out_l * (1.0f - r->width);

        /* Mix dry/wet */
        left[i]  = left[i]  * (1.0f - r->mix) + wet_l * r->mix * 0.5f;
        right[i] = right[i] * (1.0f - r->mix) + wet_r * r->mix * 0.5f;
    }
}

void reverb_destroy(ReverbEffect *r) {
    for (int i = 0; i < REVERB_NUM_COMBS; i++) {
        delay_line_destroy(&r->comb_l[i]);
        delay_line_destroy(&r->comb_r[i]);
    }
    for (int i = 0; i < REVERB_NUM_ALLPASS; i++) {
        delay_line_destroy(&r->allpass_l[i]);
        delay_line_destroy(&r->allpass_r[i]);
    }
}

/* ================================================================
 *  DISTORTION
 * ================================================================ */

void distortion_init(DistortionEffect *d, float sample_rate) {
    memset(d, 0, sizeof(DistortionEffect));
    d->sample_rate = sample_rate;
    d->drive = 5.0f;
    d->tone = 8000.0f;
    d->mix = 0.5f;
    d->output_gain = 0.5f;
    d->active = 1;
}

void distortion_set_params(DistortionEffect *d, float drive, float tone,
                           float mix, float output_gain) {
    d->drive = fx_clampf(drive, 1.0f, 100.0f);
    d->tone = fx_clampf(tone, 200.0f, 20000.0f);
    d->mix = fx_clampf(mix, 0.0f, 1.0f);
    d->output_gain = fx_clampf(output_gain, 0.0f, 2.0f);
}

void distortion_process(DistortionEffect *d, float *left, float *right, int frames) {
    if (!d->active) return;

    /* Simple one-pole LP filter coefficient for tone control */
    float fc = 2.0f * sinf((float)M_PI * d->tone / d->sample_rate);

    for (int i = 0; i < frames; i++) {
        float dry_l = left[i];
        float dry_r = right[i];

        /* Apply drive (soft clipping via tanh) */
        float wet_l = tanhf(dry_l * d->drive) * d->output_gain;
        float wet_r = tanhf(dry_r * d->drive) * d->output_gain;

        /* Tone filter (one-pole LP) */
        d->filter_state_l += fc * (wet_l - d->filter_state_l);
        d->filter_state_r += fc * (wet_r - d->filter_state_r);
        wet_l = d->filter_state_l;
        wet_r = d->filter_state_r;

        /* Mix */
        left[i]  = dry_l * (1.0f - d->mix) + wet_l * d->mix;
        right[i] = dry_r * (1.0f - d->mix) + wet_r * d->mix;
    }
}

/* ================================================================
 *  EFFECT CHAIN
 * ================================================================ */

void effect_chain_init(EffectChain *chain) {
    memset(chain, 0, sizeof(EffectChain));
}

int effect_chain_add(EffectChain *chain, int type, float sample_rate) {
    if (chain->count >= MAX_CHAIN_EFFECTS) return -1;

    int idx = chain->count;
    chain->type[idx] = type;

    switch (type) {
        case EFFECT_DELAY: {
            DelayEffect *d = (DelayEffect *)calloc(1, sizeof(DelayEffect));
            delay_init(d, sample_rate);
            chain->effect[idx] = d;
            break;
        }
        case EFFECT_REVERB: {
            ReverbEffect *r = (ReverbEffect *)calloc(1, sizeof(ReverbEffect));
            reverb_init(r, sample_rate);
            chain->effect[idx] = r;
            break;
        }
        case EFFECT_DISTORTION: {
            DistortionEffect *d = (DistortionEffect *)calloc(1, sizeof(DistortionEffect));
            distortion_init(d, sample_rate);
            chain->effect[idx] = d;
            break;
        }
        default:
            return -1;
    }

    chain->count++;
    return idx;
}

void effect_chain_process(EffectChain *chain, float *left, float *right, int frames) {
    for (int i = 0; i < chain->count; i++) {
        switch (chain->type[i]) {
            case EFFECT_DELAY:
                delay_process((DelayEffect *)chain->effect[i], left, right, frames);
                break;
            case EFFECT_REVERB:
                reverb_process((ReverbEffect *)chain->effect[i], left, right, frames);
                break;
            case EFFECT_DISTORTION:
                distortion_process((DistortionEffect *)chain->effect[i], left, right, frames);
                break;
        }
    }
}

void effect_chain_destroy(EffectChain *chain) {
    for (int i = 0; i < chain->count; i++) {
        switch (chain->type[i]) {
            case EFFECT_DELAY:
                delay_destroy((DelayEffect *)chain->effect[i]);
                free(chain->effect[i]);
                break;
            case EFFECT_REVERB:
                reverb_destroy((ReverbEffect *)chain->effect[i]);
                free(chain->effect[i]);
                break;
            case EFFECT_DISTORTION:
                free(chain->effect[i]);
                break;
        }
        chain->effect[i] = NULL;
    }
    chain->count = 0;
}
