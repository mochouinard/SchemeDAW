#include "dsp-core.h"
#include <math.h>
#include <string.h>
#include <stdlib.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define TWO_PI (2.0f * (float)M_PI)

/* ---- Utility ---- */

float midi_to_freq(int note) {
    return 440.0f * powf(2.0f, (note - 69) / 12.0f);
}

static float clampf(float x, float lo, float hi) {
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
}

/* Simple pseudo-random for noise */
static uint32_t noise_seed = 12345;
static float noise_sample(void) {
    noise_seed = noise_seed * 1664525u + 1013904223u;
    return (float)(int32_t)noise_seed / (float)INT32_MAX;
}

/* ---- Oscillator ---- */

void osc_init(Oscillator *osc, int waveform, float frequency, float sample_rate) {
    osc->phase = 0.0f;
    osc->waveform = waveform;
    osc->frequency = frequency;
    osc->phase_inc = frequency / sample_rate;
    osc->detune = 0.0f;
    osc->mix_level = 1.0f;
}

void osc_set_frequency(Oscillator *osc, float frequency, float sample_rate) {
    float detune_mult = powf(2.0f, osc->detune / 12.0f);
    osc->frequency = frequency;
    osc->phase_inc = (frequency * detune_mult) / sample_rate;
}

float osc_process_sample(Oscillator *osc) {
    float out = 0.0f;
    float p = osc->phase;

    switch (osc->waveform) {
        case WAVE_SINE:
            out = sinf(TWO_PI * p);
            break;
        case WAVE_SAW:
            out = 2.0f * p - 1.0f;
            break;
        case WAVE_SQUARE:
            out = (p < 0.5f) ? 1.0f : -1.0f;
            break;
        case WAVE_TRIANGLE:
            out = 4.0f * fabsf(p - 0.5f) - 1.0f;
            break;
        case WAVE_NOISE:
            out = noise_sample();
            break;
    }

    osc->phase += osc->phase_inc;
    if (osc->phase >= 1.0f) osc->phase -= 1.0f;

    return out * osc->mix_level;
}

/* ---- Filter (State-Variable) ---- */

void filter_init(Filter *f, int type, float cutoff, float resonance) {
    f->type = type;
    f->cutoff = cutoff;
    f->resonance = clampf(resonance, 0.0f, 1.0f);
    f->low = 0.0f;
    f->high = 0.0f;
    f->band = 0.0f;
    f->notch = 0.0f;
}

void filter_process(Filter *f, float *buf, int frames, float sample_rate) {
    /* State-variable filter (Chamberlin) */
    float fc = 2.0f * sinf((float)M_PI * clampf(f->cutoff, 20.0f, sample_rate * 0.45f) / sample_rate);
    float q = 1.0f - clampf(f->resonance, 0.0f, 0.99f);

    for (int i = 0; i < frames; i++) {
        float input = buf[i];
        f->low  += fc * f->band;
        f->high  = input - f->low - q * f->band;
        f->band += fc * f->high;
        f->notch = f->high + f->low;

        switch (f->type) {
            case FILTER_LP: buf[i] = f->low;  break;
            case FILTER_HP: buf[i] = f->high; break;
            case FILTER_BP: buf[i] = f->band; break;
        }
    }
}

/* ---- Envelope (ADSR) ---- */

void envelope_init(Envelope *e, float a, float d, float s, float r, float sample_rate) {
    e->attack = a;
    e->decay = d;
    e->sustain = clampf(s, 0.0f, 1.0f);
    e->release = r;
    e->level = 0.0f;
    e->stage = ENV_IDLE;
    e->sample_rate = sample_rate;
}

void envelope_gate_on(Envelope *e) {
    e->stage = ENV_ATTACK;
    /* Don't reset level to 0 - allows re-triggering without click */
}

void envelope_gate_off(Envelope *e) {
    if (e->stage != ENV_IDLE) {
        e->stage = ENV_RELEASE;
    }
}

float envelope_process_sample(Envelope *e) {
    float rate;

    switch (e->stage) {
        case ENV_ATTACK:
            rate = (e->attack > 0.001f) ? 1.0f / (e->attack * e->sample_rate) : 1.0f;
            e->level += rate;
            if (e->level >= 1.0f) {
                e->level = 1.0f;
                e->stage = ENV_DECAY;
            }
            break;
        case ENV_DECAY:
            rate = (e->decay > 0.001f) ? 1.0f / (e->decay * e->sample_rate) : 1.0f;
            e->level -= rate;
            if (e->level <= e->sustain) {
                e->level = e->sustain;
                e->stage = ENV_SUSTAIN;
            }
            break;
        case ENV_SUSTAIN:
            e->level = e->sustain;
            break;
        case ENV_RELEASE:
            rate = (e->release > 0.001f) ? 1.0f / (e->release * e->sample_rate) : 1.0f;
            e->level -= rate;
            if (e->level <= 0.0f) {
                e->level = 0.0f;
                e->stage = ENV_IDLE;
            }
            break;
        case ENV_IDLE:
        default:
            e->level = 0.0f;
            break;
    }

    return e->level;
}

/* Exponential envelope - sounds much more natural for musical use.
 * Uses multiplicative decay instead of linear subtraction. */
float envelope_process_sample_exp(Envelope *e) {
    switch (e->stage) {
        case ENV_ATTACK: {
            float rate = (e->attack > 0.001f) ? 1.0f / (e->attack * e->sample_rate) : 1.0f;
            e->level += rate;
            if (e->level >= 1.0f) {
                e->level = 1.0f;
                e->stage = ENV_DECAY;
            }
            break;
        }
        case ENV_DECAY: {
            /* Exponential decay toward sustain level */
            float target = e->sustain;
            float coeff = expf(-1.0f / (e->decay * e->sample_rate + 1.0f));
            e->level = target + (e->level - target) * coeff;
            if (fabsf(e->level - target) < 0.001f) {
                e->level = target;
                e->stage = ENV_SUSTAIN;
            }
            break;
        }
        case ENV_SUSTAIN:
            e->level = e->sustain;
            break;
        case ENV_RELEASE: {
            /* Exponential decay toward zero */
            float coeff = expf(-1.0f / (e->release * e->sample_rate + 1.0f));
            e->level *= coeff;
            if (e->level < 0.0001f) {
                e->level = 0.0f;
                e->stage = ENV_IDLE;
            }
            break;
        }
        case ENV_IDLE:
        default:
            e->level = 0.0f;
            break;
    }
    return e->level;
}

/* ---- Voice ---- */

void voice_init(Voice *v) {
    memset(v, 0, sizeof(Voice));
    v->active = 0;
    v->osc_count = 1;
    v->pan = 0.0f;
    v->velocity = 1.0f;
}

void voice_note_on(Voice *v, int note, float velocity, float sample_rate,
                   Track *track, uint32_t age) {
    v->active = 1;
    v->note = note;
    v->velocity = velocity;
    v->age = age;

    float freq = midi_to_freq(note);

    /* Set up oscillators from track defaults */
    v->osc_count = track->default_osc_count;
    if (v->osc_count < 1) v->osc_count = 1;
    if (v->osc_count > MAX_OSC_PER_VOICE) v->osc_count = MAX_OSC_PER_VOICE;

    /* Osc 1: main oscillator */
    osc_init(&v->osc[0], track->default_waveform, freq, sample_rate);
    v->osc[0].mix_level = 1.0f;

    /* Osc 2: detuned / octave shifted */
    if (v->osc_count >= 2) {
        float osc2_freq = freq * powf(2.0f, track->default_osc2_octave)
                              * powf(2.0f, track->default_osc2_detune / 12.0f);
        osc_init(&v->osc[1], track->default_osc2_wave, osc2_freq, sample_rate);
        v->osc[1].mix_level = track->default_osc2_mix;
        v->osc[1].detune = track->default_osc2_detune;
    }

    /* Osc 3: sub / texture layer */
    if (v->osc_count >= 3) {
        float osc3_freq = freq * powf(2.0f, track->default_osc3_octave)
                              * powf(2.0f, track->default_osc3_detune / 12.0f);
        osc_init(&v->osc[2], track->default_osc3_wave, osc3_freq, sample_rate);
        v->osc[2].mix_level = track->default_osc3_mix;
        v->osc[2].detune = track->default_osc3_detune;
    }

    /* Filter from track defaults */
    filter_init(&v->filter, track->default_filter_type,
                track->default_cutoff, track->default_resonance);

    /* Amp envelope */
    envelope_init(&v->amp_env,
                  track->default_amp_a, track->default_amp_d,
                  track->default_amp_s, track->default_amp_r,
                  sample_rate);
    envelope_gate_on(&v->amp_env);

    /* Filter envelope */
    envelope_init(&v->filter_env,
                  track->default_filt_a, track->default_filt_d,
                  track->default_filt_s, track->default_filt_r,
                  sample_rate);
    v->filter_env_amount = track->default_filt_env_amount;
    envelope_gate_on(&v->filter_env);
}

void voice_note_off(Voice *v) {
    envelope_gate_off(&v->amp_env);
    envelope_gate_off(&v->filter_env);
}

void voice_render_internal(Voice *v, float *left, float *right, int frames,
                           float sample_rate, Track *track) {
    if (!v->active) return;

    float mono_buf[BLOCK_SIZE];
    int use_exp = track->default_exp_envelope;
    int synth_type = track->synth_type;

    /* Pitch envelope state */
    float pitch_env_amount = track->default_pitch_env_amount;
    float pitch_env_decay = track->default_pitch_env_decay;
    float pitch_env_level = (pitch_env_amount != 0.0f) ? 1.0f : 0.0f;
    float pitch_env_rate = (pitch_env_decay > 0.001f)
        ? 1.0f / (pitch_env_decay * sample_rate) : 1.0f;

    /* FM synthesis parameters */
    float fm_ratio = track->default_fm_ratio;
    float fm_index = track->default_fm_index;

    for (int i = 0; i < frames; i++) {
        float osc_out = 0.0f;
        float total_mix = 0.0f;

        /* Apply pitch envelope (decays from pitch_env_amount to 0 semitones) */
        if (pitch_env_amount != 0.0f && pitch_env_level > 0.001f) {
            float pitch_shift = pitch_env_amount * pitch_env_level;
            float pitch_mult = powf(2.0f, pitch_shift / 12.0f);
            /* Temporarily adjust osc[0] phase_inc */
            float base_freq = v->osc[0].frequency;
            v->osc[0].phase_inc = (base_freq * pitch_mult) / sample_rate;
            pitch_env_level -= pitch_env_rate;
            if (pitch_env_level < 0.0f) pitch_env_level = 0.0f;
        }

        if (synth_type == 1 && fm_ratio > 0.0f && fm_index > 0.0f) {
            /* FM synthesis: osc[0] is carrier, modulator is generated inline */
            float mod_freq = v->osc[0].frequency * fm_ratio;
            static float fm_mod_phase = 0.0f; /* simple static - OK for now */
            float mod_out = sinf(TWO_PI * fm_mod_phase) * fm_index;
            fm_mod_phase += mod_freq / sample_rate;
            if (fm_mod_phase >= 1.0f) fm_mod_phase -= 1.0f;

            /* Modulate carrier phase */
            float carrier_phase = v->osc[0].phase + mod_out;
            osc_out = sinf(TWO_PI * carrier_phase);
            v->osc[0].phase += v->osc[0].phase_inc;
            if (v->osc[0].phase >= 1.0f) v->osc[0].phase -= 1.0f;
            total_mix = 1.0f;
        } else {
            /* Additive: mix all oscillators with their mix levels */
            for (int o = 0; o < v->osc_count; o++) {
                float s = osc_process_sample(&v->osc[o]);
                osc_out += s * v->osc[o].mix_level;
                total_mix += v->osc[o].mix_level;
            }
            /* Normalize by total mix to prevent clipping */
            if (total_mix > 1.0f) {
                osc_out /= total_mix;
            }
        }

        mono_buf[i] = osc_out;
    }

    /* Apply filter with envelope modulation (per-sample for accuracy) */
    float base_cutoff = v->filter.cutoff;
    float fc_min = 20.0f, fc_max = clampf(sample_rate * 0.45f, 20.0f, 20000.0f);

    for (int i = 0; i < frames; i++) {
        float filt_env = use_exp ? envelope_process_sample_exp(&v->filter_env)
                                 : envelope_process_sample(&v->filter_env);
        float fc = base_cutoff + v->filter_env_amount * filt_env;
        v->filter.cutoff = clampf(fc, fc_min, fc_max);

        /* Inline single-sample filter for per-sample cutoff modulation */
        float f = 2.0f * sinf((float)M_PI * v->filter.cutoff / sample_rate);
        float q = 1.0f - clampf(v->filter.resonance, 0.0f, 0.99f);
        float input = mono_buf[i];
        v->filter.low  += f * v->filter.band;
        v->filter.high  = input - v->filter.low - q * v->filter.band;
        v->filter.band += f * v->filter.high;

        switch (v->filter.type) {
            case FILTER_LP: mono_buf[i] = v->filter.low;  break;
            case FILTER_HP: mono_buf[i] = v->filter.high; break;
            case FILTER_BP: mono_buf[i] = v->filter.band; break;
        }
    }
    v->filter.cutoff = base_cutoff;

    /* Apply amp envelope and pan, mix into output */
    float pan_r = (v->pan + 1.0f) * 0.5f;
    float pan_l = 1.0f - pan_r;

    for (int i = 0; i < frames; i++) {
        float amp = use_exp ? envelope_process_sample_exp(&v->amp_env)
                            : envelope_process_sample(&v->amp_env);
        float sample = mono_buf[i] * amp * v->velocity;

        left[i]  += sample * pan_l;
        right[i] += sample * pan_r;
    }

    /* Check if voice finished */
    if (v->amp_env.stage == ENV_IDLE) {
        v->active = 0;
    }
}

/* Legacy wrapper for compatibility */
void voice_render(Voice *v, float *left, float *right, int frames, float sample_rate) {
    /* Create a temporary default track for backward compat */
    Track tmp;
    track_init(&tmp);
    voice_render_internal(v, left, right, frames, sample_rate, &tmp);
}

/* ---- Track ---- */

void track_init(Track *t) {
    memset(t, 0, sizeof(Track));
    t->volume = 0.8f;
    t->pan = 0.0f;
    t->mute = 0;
    t->solo = 0;
    t->synth_type = 0;
    t->fx_count = 0;

    /* Sensible defaults for subtractive synth */
    t->default_waveform = WAVE_SAW;
    t->default_cutoff = 4000.0f;
    t->default_resonance = 0.3f;
    t->default_filter_type = FILTER_LP;
    t->default_amp_a = 0.01f;
    t->default_amp_d = 0.2f;
    t->default_amp_s = 0.7f;
    t->default_amp_r = 0.3f;
    t->default_filt_a = 0.01f;
    t->default_filt_d = 0.3f;
    t->default_filt_s = 0.3f;
    t->default_filt_r = 0.5f;
    t->default_filt_env_amount = 2000.0f;

    /* Multi-oscillator defaults */
    t->default_osc_count = 1;
    t->default_osc2_wave = WAVE_SAW;
    t->default_osc3_wave = WAVE_SINE;
    t->default_osc2_detune = 0.0f;
    t->default_osc3_detune = 0.0f;
    t->default_osc2_mix = 0.8f;
    t->default_osc3_mix = 0.5f;
    t->default_osc2_octave = 0.0f;
    t->default_osc3_octave = 0.0f;

    /* FM defaults */
    t->default_fm_ratio = 2.0f;
    t->default_fm_index = 0.0f;

    /* Pitch envelope off by default */
    t->default_pitch_env_amount = 0.0f;
    t->default_pitch_env_decay = 0.1f;

    /* Use exponential envelopes by default (sounds better) */
    t->default_exp_envelope = 1;

    for (int i = 0; i < MAX_VOICES; i++) {
        voice_init(&t->voices[i]);
    }
}

void track_render(Track *t, float *left, float *right, int frames, float sample_rate,
                  uint32_t *voice_counter) {
    (void)voice_counter;

    memset(left, 0, frames * sizeof(float));
    memset(right, 0, frames * sizeof(float));

    for (int i = 0; i < MAX_VOICES; i++) {
        if (t->voices[i].active) {
            voice_render_internal(&t->voices[i], left, right, frames, sample_rate, t);
        }
    }

    /* Apply track volume and pan */
    float pan_r = (t->pan + 1.0f) * 0.5f;
    float pan_l = 1.0f - pan_r;

    for (int i = 0; i < frames; i++) {
        left[i]  *= t->volume * pan_l;
        right[i] *= t->volume * pan_r;
    }
}

/* ---- Engine ---- */

void engine_init(AudioEngine *engine, float sample_rate, int block_size) {
    memset(engine, 0, sizeof(AudioEngine));
    engine->sample_rate = sample_rate;
    engine->block_size = block_size;
    engine->master_volume = 0.8f;
    engine->voice_counter = 0;
    engine->any_solo = 0;

    for (int t = 0; t < MAX_TRACKS; t++) {
        track_init(&engine->tracks[t]);
    }
}

static Voice* find_free_voice(Track *t) {
    /* Find an idle voice */
    for (int i = 0; i < MAX_VOICES; i++) {
        if (!t->voices[i].active) {
            return &t->voices[i];
        }
    }
    /* Voice stealing: find oldest voice */
    uint32_t min_age = UINT32_MAX;
    int oldest = 0;
    for (int i = 0; i < MAX_VOICES; i++) {
        if (t->voices[i].age < min_age) {
            min_age = t->voices[i].age;
            oldest = i;
        }
    }
    return &t->voices[oldest];
}

void engine_note_on(AudioEngine *engine, int track, int note, int velocity) {
    if (track < 0 || track >= MAX_TRACKS) return;
    if (velocity == 0) {
        engine_note_off(engine, track, note);
        return;
    }

    Track *t = &engine->tracks[track];
    Voice *v = find_free_voice(t);
    float vel_f = (float)velocity / 127.0f;

    voice_note_on(v, note, vel_f, engine->sample_rate, t, engine->voice_counter++);
}

void engine_note_off(AudioEngine *engine, int track, int note) {
    if (track < 0 || track >= MAX_TRACKS) return;

    Track *t = &engine->tracks[track];
    for (int i = 0; i < MAX_VOICES; i++) {
        if (t->voices[i].active && t->voices[i].note == note) {
            voice_note_off(&t->voices[i]);
        }
    }
}

void engine_all_notes_off(AudioEngine *engine, int track) {
    if (track < 0 || track >= MAX_TRACKS) return;

    Track *t = &engine->tracks[track];
    for (int i = 0; i < MAX_VOICES; i++) {
        if (t->voices[i].active) {
            voice_note_off(&t->voices[i]);
        }
    }
}

void engine_render(AudioEngine *engine, float *output, int frames) {
    /* Clear output */
    memset(output, 0, frames * 2 * sizeof(float));

    /* Check if any track is soloed */
    engine->any_solo = 0;
    for (int t = 0; t < MAX_TRACKS; t++) {
        if (engine->tracks[t].solo) {
            engine->any_solo = 1;
            break;
        }
    }

    float left_buf[BLOCK_SIZE];
    float right_buf[BLOCK_SIZE];

    for (int t = 0; t < MAX_TRACKS; t++) {
        Track *track = &engine->tracks[t];

        /* Skip muted tracks, or non-soloed tracks when solo is active */
        if (track->mute) continue;
        if (engine->any_solo && !track->solo) continue;

        track_render(track, left_buf, right_buf, frames, engine->sample_rate,
                     &engine->voice_counter);

        /* Mix into interleaved stereo output */
        for (int i = 0; i < frames; i++) {
            output[i * 2]     += left_buf[i];
            output[i * 2 + 1] += right_buf[i];
        }
    }

    /* Apply master volume and clamp */
    for (int i = 0; i < frames * 2; i++) {
        output[i] *= engine->master_volume;
        output[i] = clampf(output[i], -1.0f, 1.0f);
    }
}
