#include "audio-backend.h"
#include <SDL2/SDL.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

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
