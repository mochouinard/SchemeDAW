#include "audio-backend.h"
#include <SDL2/SDL.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/*
 * Load a built-in preset into a track.
 * Presets configure all track parameters for a specific sound.
 */
static void load_builtin_preset(Track *t, int preset_id) {
    /* Reset to defaults first */
    float vol = t->volume;
    float pan = t->pan;
    int mute = t->mute, solo = t->solo;
    track_init(t);
    t->volume = vol; t->pan = pan; t->mute = mute; t->solo = solo;

    switch (preset_id) {
        case 0: /* Supersaw Lead - thick detuned saws */
            t->synth_type = 0;
            t->default_osc_count = 3;
            t->default_waveform = WAVE_SAW;
            t->default_osc2_wave = WAVE_SAW;
            t->default_osc3_wave = WAVE_SAW;
            t->default_osc2_detune = 0.12f;   /* slight sharp */
            t->default_osc3_detune = -0.12f;  /* slight flat */
            t->default_osc2_mix = 0.9f;
            t->default_osc3_mix = 0.9f;
            t->default_cutoff = 5000.0f;
            t->default_resonance = 0.25f;
            t->default_filt_env_amount = 3000.0f;
            t->default_amp_a = 0.01f; t->default_amp_d = 0.15f;
            t->default_amp_s = 0.8f;  t->default_amp_r = 0.4f;
            t->default_filt_a = 0.01f; t->default_filt_d = 0.3f;
            t->default_filt_s = 0.4f;  t->default_filt_r = 0.5f;
            t->default_exp_envelope = 1;
            break;

        case 1: /* Deep Sub Bass - sine + sub octave */
            t->synth_type = 0;
            t->default_osc_count = 2;
            t->default_waveform = WAVE_SINE;
            t->default_osc2_wave = WAVE_SINE;
            t->default_osc2_octave = -1.0f;  /* sub octave */
            t->default_osc2_mix = 0.7f;
            t->default_cutoff = 500.0f;
            t->default_resonance = 0.1f;
            t->default_filt_env_amount = 200.0f;
            t->default_amp_a = 0.005f; t->default_amp_d = 0.3f;
            t->default_amp_s = 0.6f;   t->default_amp_r = 0.2f;
            t->default_exp_envelope = 1;
            break;

        case 2: /* Acid Bass 303 - resonant saw with sharp filter env */
            t->synth_type = 0;
            t->default_osc_count = 1;
            t->default_waveform = WAVE_SAW;
            t->default_cutoff = 400.0f;
            t->default_resonance = 0.75f;
            t->default_filt_env_amount = 8000.0f;
            t->default_amp_a = 0.003f; t->default_amp_d = 0.15f;
            t->default_amp_s = 0.0f;   t->default_amp_r = 0.08f;
            t->default_filt_a = 0.003f; t->default_filt_d = 0.12f;
            t->default_filt_s = 0.0f;   t->default_filt_r = 0.1f;
            t->default_exp_envelope = 1;
            break;

        case 3: /* Warm Pad - slow detuned saws */
            t->synth_type = 0;
            t->default_osc_count = 3;
            t->default_waveform = WAVE_SAW;
            t->default_osc2_wave = WAVE_SAW;
            t->default_osc3_wave = WAVE_TRIANGLE;
            t->default_osc2_detune = 0.08f;
            t->default_osc3_detune = -0.05f;
            t->default_osc3_octave = 1.0f;   /* octave up shimmer */
            t->default_osc2_mix = 0.8f;
            t->default_osc3_mix = 0.3f;
            t->default_cutoff = 2500.0f;
            t->default_resonance = 0.15f;
            t->default_filt_env_amount = 1500.0f;
            t->default_amp_a = 0.6f;  t->default_amp_d = 0.5f;
            t->default_amp_s = 0.75f; t->default_amp_r = 1.5f;
            t->default_filt_a = 0.5f;  t->default_filt_d = 0.8f;
            t->default_filt_s = 0.4f;  t->default_filt_r = 1.5f;
            t->default_exp_envelope = 1;
            break;

        case 4: /* FM Bell - inharmonic metallic bell */
            t->synth_type = 1;  /* FM mode */
            t->default_osc_count = 1;
            t->default_waveform = WAVE_SINE;
            t->default_fm_ratio = 3.5f;
            t->default_fm_index = 5.0f;
            t->default_cutoff = 12000.0f;
            t->default_resonance = 0.05f;
            t->default_filt_env_amount = 0.0f;
            t->default_amp_a = 0.001f; t->default_amp_d = 2.5f;
            t->default_amp_s = 0.0f;   t->default_amp_r = 2.0f;
            t->default_exp_envelope = 1;
            break;

        case 5: /* FM Electric Piano - classic DX7 Rhodes */
            t->synth_type = 1;
            t->default_osc_count = 1;
            t->default_waveform = WAVE_SINE;
            t->default_fm_ratio = 7.0f;
            t->default_fm_index = 2.5f;
            t->default_cutoff = 8000.0f;
            t->default_resonance = 0.1f;
            t->default_filt_env_amount = 0.0f;
            t->default_amp_a = 0.001f; t->default_amp_d = 1.2f;
            t->default_amp_s = 0.25f;  t->default_amp_r = 0.8f;
            t->default_exp_envelope = 1;
            break;

        case 6: /* 808 Kick - pitch-dropping sine */
            t->synth_type = 0;
            t->default_osc_count = 1;
            t->default_waveform = WAVE_SINE;
            t->default_cutoff = 20000.0f;
            t->default_resonance = 0.0f;
            t->default_filt_env_amount = 0.0f;
            t->default_amp_a = 0.001f; t->default_amp_d = 0.5f;
            t->default_amp_s = 0.0f;   t->default_amp_r = 0.3f;
            t->default_pitch_env_amount = 48.0f; /* 4 octaves drop */
            t->default_pitch_env_decay = 0.07f;
            t->default_exp_envelope = 1;
            break;

        case 7: /* Snare - noise + sine body */
            t->synth_type = 0;
            t->default_osc_count = 2;
            t->default_waveform = WAVE_SINE;
            t->default_osc2_wave = WAVE_NOISE;
            t->default_osc2_mix = 1.2f;
            t->default_cutoff = 6000.0f;
            t->default_resonance = 0.1f;
            t->default_filter_type = FILTER_LP;
            t->default_filt_env_amount = 3000.0f;
            t->default_amp_a = 0.001f; t->default_amp_d = 0.18f;
            t->default_amp_s = 0.0f;   t->default_amp_r = 0.1f;
            t->default_filt_a = 0.001f; t->default_filt_d = 0.08f;
            t->default_filt_s = 0.0f;   t->default_filt_r = 0.05f;
            t->default_pitch_env_amount = 12.0f;
            t->default_pitch_env_decay = 0.02f;
            t->default_exp_envelope = 1;
            break;

        case 8: /* Hi-Hat Closed - filtered noise */
            t->synth_type = 0;
            t->default_osc_count = 1;
            t->default_waveform = WAVE_NOISE;
            t->default_cutoff = 10000.0f;
            t->default_resonance = 0.3f;
            t->default_filter_type = FILTER_HP;
            t->default_filt_env_amount = 2000.0f;
            t->default_amp_a = 0.001f; t->default_amp_d = 0.06f;
            t->default_amp_s = 0.0f;   t->default_amp_r = 0.04f;
            t->default_exp_envelope = 1;
            break;

        case 9: /* Hi-Hat Open - longer noise */
            t->synth_type = 0;
            t->default_osc_count = 1;
            t->default_waveform = WAVE_NOISE;
            t->default_cutoff = 9000.0f;
            t->default_resonance = 0.35f;
            t->default_filter_type = FILTER_HP;
            t->default_filt_env_amount = 3000.0f;
            t->default_amp_a = 0.001f; t->default_amp_d = 0.35f;
            t->default_amp_s = 0.0f;   t->default_amp_r = 0.25f;
            t->default_exp_envelope = 1;
            break;

        case 10: /* Clap - noise burst with pre-delay feel */
            t->synth_type = 0;
            t->default_osc_count = 1;
            t->default_waveform = WAVE_NOISE;
            t->default_cutoff = 3000.0f;
            t->default_resonance = 0.2f;
            t->default_filter_type = FILTER_BP;
            t->default_filt_env_amount = 4000.0f;
            t->default_amp_a = 0.001f; t->default_amp_d = 0.2f;
            t->default_amp_s = 0.0f;   t->default_amp_r = 0.15f;
            t->default_filt_a = 0.001f; t->default_filt_d = 0.1f;
            t->default_filt_s = 0.0f;   t->default_filt_r = 0.08f;
            t->default_exp_envelope = 1;
            break;

        case 11: /* Pluck - bright attack, fast decay */
            t->synth_type = 0;
            t->default_osc_count = 2;
            t->default_waveform = WAVE_SAW;
            t->default_osc2_wave = WAVE_SQUARE;
            t->default_osc2_detune = 0.05f;
            t->default_osc2_mix = 0.6f;
            t->default_cutoff = 6000.0f;
            t->default_resonance = 0.35f;
            t->default_filt_env_amount = 6000.0f;
            t->default_amp_a = 0.001f; t->default_amp_d = 0.4f;
            t->default_amp_s = 0.0f;   t->default_amp_r = 0.3f;
            t->default_filt_a = 0.001f; t->default_filt_d = 0.2f;
            t->default_filt_s = 0.0f;   t->default_filt_r = 0.15f;
            t->default_exp_envelope = 1;
            break;

        case 12: /* Stab - short chord-like hit */
            t->synth_type = 0;
            t->default_osc_count = 3;
            t->default_waveform = WAVE_SAW;
            t->default_osc2_wave = WAVE_SAW;
            t->default_osc3_wave = WAVE_SAW;
            t->default_osc2_detune = 0.15f;
            t->default_osc3_detune = -0.15f;
            t->default_osc2_mix = 0.9f;
            t->default_osc3_mix = 0.9f;
            t->default_cutoff = 3000.0f;
            t->default_resonance = 0.4f;
            t->default_filt_env_amount = 5000.0f;
            t->default_amp_a = 0.001f; t->default_amp_d = 0.2f;
            t->default_amp_s = 0.0f;   t->default_amp_r = 0.15f;
            t->default_filt_a = 0.001f; t->default_filt_d = 0.15f;
            t->default_filt_s = 0.0f;   t->default_filt_r = 0.1f;
            t->default_exp_envelope = 1;
            break;

        case 13: /* Reese Bass - detuned saws, very low */
            t->synth_type = 0;
            t->default_osc_count = 2;
            t->default_waveform = WAVE_SAW;
            t->default_osc2_wave = WAVE_SAW;
            t->default_osc2_detune = 0.06f;
            t->default_osc2_mix = 1.0f;
            t->default_cutoff = 1200.0f;
            t->default_resonance = 0.35f;
            t->default_filt_env_amount = 2000.0f;
            t->default_amp_a = 0.01f; t->default_amp_d = 0.3f;
            t->default_amp_s = 0.7f;  t->default_amp_r = 0.3f;
            t->default_filt_a = 0.01f; t->default_filt_d = 0.5f;
            t->default_filt_s = 0.2f;  t->default_filt_r = 0.4f;
            t->default_exp_envelope = 1;
            break;

        case 14: /* Strings - slow attack detuned ensemble */
            t->synth_type = 0;
            t->default_osc_count = 3;
            t->default_waveform = WAVE_SAW;
            t->default_osc2_wave = WAVE_SAW;
            t->default_osc3_wave = WAVE_SAW;
            t->default_osc2_detune = 0.1f;
            t->default_osc3_detune = -0.1f;
            t->default_osc2_mix = 0.85f;
            t->default_osc3_mix = 0.85f;
            t->default_cutoff = 3500.0f;
            t->default_resonance = 0.1f;
            t->default_filt_env_amount = 1000.0f;
            t->default_amp_a = 0.8f;  t->default_amp_d = 0.3f;
            t->default_amp_s = 0.85f; t->default_amp_r = 1.0f;
            t->default_filt_a = 0.6f;  t->default_filt_d = 0.5f;
            t->default_filt_s = 0.6f;  t->default_filt_r = 0.8f;
            t->default_exp_envelope = 1;
            break;

        case 15: /* Brass - bright attack, sustained */
            t->synth_type = 0;
            t->default_osc_count = 2;
            t->default_waveform = WAVE_SAW;
            t->default_osc2_wave = WAVE_SAW;
            t->default_osc2_detune = 0.03f;
            t->default_osc2_mix = 0.9f;
            t->default_cutoff = 2000.0f;
            t->default_resonance = 0.2f;
            t->default_filt_env_amount = 6000.0f;
            t->default_amp_a = 0.05f; t->default_amp_d = 0.2f;
            t->default_amp_s = 0.8f;  t->default_amp_r = 0.2f;
            t->default_filt_a = 0.03f; t->default_filt_d = 0.3f;
            t->default_filt_s = 0.5f;  t->default_filt_r = 0.2f;
            t->default_exp_envelope = 1;
            break;
    }
}

/*
 * Process a single command from the ring buffer.
 * Called from within the audio callback (real-time context).
 */
static void process_command(AudioBackend *ab, const AudioCommand *cmd) {
    AudioEngine *engine = &ab->engine;

    switch (cmd->type) {
        case CMD_NOTE_ON:
            engine_note_on(engine, cmd->track, cmd->param1, cmd->param2);
            break;

        case CMD_NOTE_OFF:
            engine_note_off(engine, cmd->track, cmd->param1);
            break;

        case CMD_ALL_NOTES_OFF:
            engine_all_notes_off(engine, cmd->track);
            break;

        case CMD_SET_VOLUME:
            if (cmd->track < MAX_TRACKS) {
                engine->tracks[cmd->track].volume = cmd->fvalue;
            }
            break;

        case CMD_SET_PAN:
            if (cmd->track < MAX_TRACKS) {
                engine->tracks[cmd->track].pan = cmd->fvalue;
            }
            break;

        case CMD_MUTE_TRACK:
            if (cmd->track < MAX_TRACKS) {
                engine->tracks[cmd->track].mute = cmd->param1;
            }
            break;

        case CMD_SOLO_TRACK:
            if (cmd->track < MAX_TRACKS) {
                engine->tracks[cmd->track].solo = cmd->param1;
            }
            break;

        case CMD_SET_WAVEFORM:
            if (cmd->track < MAX_TRACKS) {
                engine->tracks[cmd->track].default_waveform = cmd->param1;
            }
            break;

        case CMD_SET_FILTER:
            if (cmd->track < MAX_TRACKS) {
                Track *t = &engine->tracks[cmd->track];
                /* param1: filter type, param2: unused */
                t->default_filter_type = cmd->param1;
                /* fvalue encodes cutoff in upper 16 bits area, but simpler: */
                /* We use param index for what to set */
                /* param1=0: set cutoff (fvalue), param1=1: set resonance (fvalue),
                   param1=2: set type (param2) */
                switch (cmd->param1) {
                    case 0: t->default_cutoff = cmd->fvalue; break;
                    case 1: t->default_resonance = cmd->fvalue; break;
                    case 2: t->default_filter_type = cmd->param2; break;
                }
            }
            break;

        case CMD_SET_ENVELOPE:
            if (cmd->track < MAX_TRACKS) {
                Track *t = &engine->tracks[cmd->track];
                /* param1: which envelope (0=amp, 1=filter)
                   param2: which stage (0=A, 1=D, 2=S, 3=R)
                   fvalue: value */
                if (cmd->param1 == 0) {
                    switch (cmd->param2) {
                        case 0: t->default_amp_a = cmd->fvalue; break;
                        case 1: t->default_amp_d = cmd->fvalue; break;
                        case 2: t->default_amp_s = cmd->fvalue; break;
                        case 3: t->default_amp_r = cmd->fvalue; break;
                    }
                } else if (cmd->param1 == 1) {
                    switch (cmd->param2) {
                        case 0: t->default_filt_a = cmd->fvalue; break;
                        case 1: t->default_filt_d = cmd->fvalue; break;
                        case 2: t->default_filt_s = cmd->fvalue; break;
                        case 3: t->default_filt_r = cmd->fvalue; break;
                    }
                }
            }
            break;

        case CMD_SET_PARAM:
            /* Generic parameter setting - param1 is parameter index */
            if (cmd->track < MAX_TRACKS) {
                Track *t = &engine->tracks[cmd->track];
                switch (cmd->param1) {
                    case 0: t->default_cutoff = cmd->fvalue; break;
                    case 1: t->default_resonance = cmd->fvalue; break;
                    case 2: t->default_filt_env_amount = cmd->fvalue; break;
                    case 3: t->default_waveform = (int)cmd->fvalue; break;
                }
            }
            break;

        case CMD_SET_OSC_COUNT:
            if (cmd->track < MAX_TRACKS) {
                engine->tracks[cmd->track].default_osc_count = cmd->param1;
            }
            break;

        case CMD_SET_OSC2:
            if (cmd->track < MAX_TRACKS) {
                Track *t = &engine->tracks[cmd->track];
                switch (cmd->param1) {
                    case 0: t->default_osc2_wave = cmd->param2; break;
                    case 1: t->default_osc2_detune = cmd->fvalue; break;
                    case 2: t->default_osc2_mix = cmd->fvalue; break;
                    case 3: t->default_osc2_octave = cmd->fvalue; break;
                }
            }
            break;

        case CMD_SET_OSC3:
            if (cmd->track < MAX_TRACKS) {
                Track *t = &engine->tracks[cmd->track];
                switch (cmd->param1) {
                    case 0: t->default_osc3_wave = cmd->param2; break;
                    case 1: t->default_osc3_detune = cmd->fvalue; break;
                    case 2: t->default_osc3_mix = cmd->fvalue; break;
                    case 3: t->default_osc3_octave = cmd->fvalue; break;
                }
            }
            break;

        case CMD_SET_FM:
            if (cmd->track < MAX_TRACKS) {
                Track *t = &engine->tracks[cmd->track];
                switch (cmd->param1) {
                    case 0: t->default_fm_ratio = cmd->fvalue; break;
                    case 1: t->default_fm_index = cmd->fvalue; break;
                }
            }
            break;

        case CMD_SET_PITCH_ENV:
            if (cmd->track < MAX_TRACKS) {
                Track *t = &engine->tracks[cmd->track];
                switch (cmd->param1) {
                    case 0: t->default_pitch_env_amount = cmd->fvalue; break;
                    case 1: t->default_pitch_env_decay = cmd->fvalue; break;
                }
            }
            break;

        case CMD_SET_SYNTH_TYPE:
            if (cmd->track < MAX_TRACKS) {
                engine->tracks[cmd->track].synth_type = cmd->param1;
            }
            break;

        case CMD_SET_EXP_ENV:
            if (cmd->track < MAX_TRACKS) {
                engine->tracks[cmd->track].default_exp_envelope = cmd->param1;
            }
            break;

        case CMD_LOAD_PRESET:
            if (cmd->track < MAX_TRACKS) {
                Track *t = &engine->tracks[cmd->track];
                /* Built-in preset loader - see presets below */
                load_builtin_preset(t, cmd->param1);
            }
            break;

        default:
            break;
    }
}

/*
 * SDL2 audio callback. Runs on a separate OS thread created by SDL.
 * Must be real-time safe: no allocations, no locks, no Scheme calls.
 */
static void audio_callback(void *userdata, Uint8 *stream, int len) {
    AudioBackend *ab = (AudioBackend *)userdata;
    float *output = (float *)stream;
    int frames = len / (int)(2 * sizeof(float)); /* stereo float */

    /* Drain all pending commands from the ring buffer */
    AudioCommand cmd;
    while (ringbuffer_read(&ab->cmd_ring, &cmd)) {
        process_command(ab, &cmd);
    }

    /* Render audio */
    engine_render(&ab->engine, output, frames);
}

AudioBackend* backend_create(int sample_rate, int buffer_size) {
    AudioBackend *ab = (AudioBackend *)calloc(1, sizeof(AudioBackend));
    if (!ab) return NULL;

    engine_init(&ab->engine, (float)sample_rate, buffer_size);
    ringbuffer_init(&ab->cmd_ring);
    ab->device_id = 0;
    ab->running = 0;

    return ab;
}

int backend_start(AudioBackend *ab) {
    if (ab->running) return 0;

    if (SDL_Init(SDL_INIT_AUDIO) < 0) {
        fprintf(stderr, "SDL_Init(AUDIO) failed: %s\n", SDL_GetError());
        return -1;
    }

    SDL_AudioSpec desired, obtained;
    memset(&desired, 0, sizeof(desired));
    desired.freq = (int)ab->engine.sample_rate;
    desired.format = AUDIO_F32SYS;
    desired.channels = 2;
    desired.samples = (Uint16)ab->engine.block_size;
    desired.callback = audio_callback;
    desired.userdata = ab;

    ab->device_id = SDL_OpenAudioDevice(NULL, 0, &desired, &obtained, 0);
    if (ab->device_id == 0) {
        fprintf(stderr, "SDL_OpenAudioDevice failed: %s\n", SDL_GetError());
        return -1;
    }

    /* Update engine with actual sample rate if different */
    if (obtained.freq != desired.freq) {
        ab->engine.sample_rate = (float)obtained.freq;
        fprintf(stderr, "Note: got sample rate %d (requested %d)\n",
                obtained.freq, desired.freq);
    }

    /* Unpause to start audio */
    SDL_PauseAudioDevice(ab->device_id, 0);
    ab->running = 1;

    fprintf(stderr, "Audio started: %d Hz, %d channels, buffer %d samples\n",
            obtained.freq, obtained.channels, obtained.samples);

    return 0;
}

void backend_stop(AudioBackend *ab) {
    if (ab->running && ab->device_id) {
        SDL_PauseAudioDevice(ab->device_id, 1);
        ab->running = 0;
    }
}

void backend_destroy(AudioBackend *ab) {
    if (!ab) return;

    if (ab->device_id) {
        SDL_CloseAudioDevice(ab->device_id);
        ab->device_id = 0;
    }

    free(ab);
}

int backend_send_command(AudioBackend *ab, uint8_t type, uint8_t track,
                         uint8_t p1, uint8_t p2, float fval) {
    AudioCommand cmd;
    cmd.type = type;
    cmd.track = track;
    cmd.param1 = p1;
    cmd.param2 = p2;
    cmd.fvalue = fval;
    return ringbuffer_write(&ab->cmd_ring, &cmd);
}

AudioEngine* backend_get_engine(AudioBackend *ab) {
    return &ab->engine;
}
