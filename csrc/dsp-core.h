#ifndef DSP_CORE_H
#define DSP_CORE_H

#include <stdint.h>

#define MAX_VOICES        64
#define MAX_TRACKS        16
#define MAX_FX_PER_TRACK   8
#define MAX_OSC_PER_VOICE  3
#define BLOCK_SIZE       1024

/* Waveform types */
#define WAVE_SINE     0
#define WAVE_SAW      1
#define WAVE_SQUARE   2
#define WAVE_TRIANGLE 3
#define WAVE_NOISE    4

/* Filter types */
#define FILTER_LP  0
#define FILTER_HP  1
#define FILTER_BP  2

/* Envelope stages */
#define ENV_IDLE    0
#define ENV_ATTACK  1
#define ENV_DECAY   2
#define ENV_SUSTAIN 3
#define ENV_RELEASE 4

/* Effect types */
#define FX_NONE       0
#define FX_DELAY      1
#define FX_REVERB     2
#define FX_DISTORTION 3

typedef struct {
    float phase;
    float phase_inc;
    float frequency;
    int   waveform;
    float detune;        /* semitones detune from base frequency */
    float mix_level;     /* 0.0 - 1.0 */
} Oscillator;

typedef struct {
    float cutoff;
    float resonance;
    /* State-variable filter state */
    float low;
    float high;
    float band;
    float notch;
    int   type;          /* FILTER_LP, FILTER_HP, FILTER_BP */
} Filter;

typedef struct {
    float attack;        /* seconds */
    float decay;         /* seconds */
    float sustain;       /* 0.0 - 1.0 */
    float release;       /* seconds */
    float level;         /* current output level */
    int   stage;         /* ENV_IDLE .. ENV_RELEASE */
    float sample_rate;
} Envelope;

typedef struct {
    Oscillator osc[MAX_OSC_PER_VOICE];
    int        osc_count;
    Filter     filter;
    Envelope   amp_env;
    Envelope   filter_env;
    float      filter_env_amount;  /* how much filter env modulates cutoff */
    float      velocity;
    float      pan;                /* -1.0 (left) to 1.0 (right) */
    int        active;
    int        note;               /* MIDI note number */
    uint32_t   age;                /* for voice stealing: incremented each note-on */
} Voice;

typedef struct {
    int   type;                    /* FX_* type */
    float params[8];
    float state[16];
    float *delay_buffer;
    int   delay_buf_size;
    int   delay_write_pos;
} Effect;

typedef struct {
    Voice  voices[MAX_VOICES];
    Effect fx[MAX_FX_PER_TRACK];
    int    fx_count;
    float  volume;
    float  pan;
    int    mute;
    int    solo;
    int    synth_type;             /* 0=subtractive, 1=fm, 2=unison */
    /* Default synth parameters for new voices on this track */
    int    default_waveform;
    float  default_cutoff;
    float  default_resonance;
    int    default_filter_type;
    float  default_amp_a, default_amp_d, default_amp_s, default_amp_r;
    float  default_filt_a, default_filt_d, default_filt_s, default_filt_r;
    float  default_filt_env_amount;
    /* Multi-oscillator / unison */
    int    default_osc_count;      /* 1-3 oscillators */
    int    default_osc2_wave;      /* waveform for osc 2 */
    int    default_osc3_wave;      /* waveform for osc 3 */
    float  default_osc2_detune;    /* semitones */
    float  default_osc3_detune;    /* semitones */
    float  default_osc2_mix;       /* 0.0-1.0 */
    float  default_osc3_mix;       /* 0.0-1.0 */
    float  default_osc2_octave;    /* -2, -1, 0, +1, +2 octave shift */
    float  default_osc3_octave;    /* -2, -1, 0, +1, +2 octave shift */
    /* FM synthesis */
    float  default_fm_ratio;       /* modulator freq ratio */
    float  default_fm_index;       /* modulation depth */
    /* Pitch envelope (for kicks, risers, etc.) */
    float  default_pitch_env_amount; /* semitones sweep */
    float  default_pitch_env_decay;  /* decay time in seconds */
    /* Exponential envelope mode (sounds more natural) */
    int    default_exp_envelope;     /* 0=linear, 1=exponential */
} Track;

typedef struct {
    Track    tracks[MAX_TRACKS];
    float    master_volume;
    float    sample_rate;
    int      block_size;
    uint32_t voice_counter;        /* global counter for voice age */
    int      any_solo;             /* cached: is any track soloed? */
} AudioEngine;

/* ---- Functions ---- */

/* Initialize engine with defaults */
void engine_init(AudioEngine *engine, float sample_rate, int block_size);

/* Convert MIDI note to frequency */
float midi_to_freq(int note);

/* Oscillator */
void osc_init(Oscillator *osc, int waveform, float frequency, float sample_rate);
void osc_set_frequency(Oscillator *osc, float frequency, float sample_rate);
float osc_process_sample(Oscillator *osc);

/* Filter */
void filter_init(Filter *f, int type, float cutoff, float resonance);
void filter_process(Filter *f, float *buf, int frames, float sample_rate);

/* Envelope */
void envelope_init(Envelope *e, float a, float d, float s, float r, float sample_rate);
void envelope_gate_on(Envelope *e);
void envelope_gate_off(Envelope *e);
float envelope_process_sample(Envelope *e);

/* Voice */
void voice_init(Voice *v);
void voice_note_on(Voice *v, int note, float velocity, float sample_rate,
                   Track *track, uint32_t age);
void voice_note_off(Voice *v);
void voice_render(Voice *v, float *left, float *right, int frames, float sample_rate);

/* Track */
void track_init(Track *t);
void track_render(Track *t, float *left, float *right, int frames, float sample_rate,
                  uint32_t *voice_counter);

/* Engine-level rendering (called from audio callback) */
void engine_render(AudioEngine *engine, float *output, int frames);

/* Note on/off at engine level (finds free voice, handles stealing) */
void engine_note_on(AudioEngine *engine, int track, int note, int velocity);
void engine_note_off(AudioEngine *engine, int track, int note);
void engine_all_notes_off(AudioEngine *engine, int track);

#endif /* DSP_CORE_H */
